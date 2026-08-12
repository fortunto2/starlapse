import Foundation

/// A position on the celestial sphere, epoch J2000. Fixed for stars and radiants —
/// this is what a catalogue stores.
public struct EquatorialCoordinates: Sendable, Hashable {
    /// Degrees in `[0, 360)`.
    public var rightAscension: Double
    /// Degrees in `[-90, 90]`.
    public var declination: Double

    public init(rightAscension: Double, declination: Double) {
        self.rightAscension = rightAscension.normalizedDegrees
        self.declination = declination.clamped(to: -90 ... 90)
    }

    /// Build from the hours/minutes notation catalogues print.
    public init(raHours: Double, raMinutes: Double = 0, dec: Double) {
        self.init(
            rightAscension: hoursToDegrees(raHours, raMinutes),
            declination: dec
        )
    }
}

/// Where to actually point the phone: azimuth clockwise from true north, altitude above
/// the horizon. This is what changes minute by minute as the Earth turns.
public struct HorizontalCoordinates: Sendable, Hashable {
    /// Degrees in `[0, 360)`, 0 = true north, 90 = east.
    public var azimuth: Double
    /// Degrees in `[-90, 90]`. Negative means below the horizon.
    public var altitude: Double

    public init(azimuth: Double, altitude: Double) {
        self.azimuth = azimuth.normalizedDegrees
        self.altitude = altitude
    }

    public var isAboveHorizon: Bool { altitude > 0 }

    /// Angular separation from another direction, in degrees. Used to answer
    /// "how far off am I aiming right now".
    public func separation(from other: HorizontalCoordinates) -> Double {
        let lat1 = altitude.radians
        let lat2 = other.altitude.radians
        let deltaAz = (azimuth - other.azimuth).radians
        let cosine = sin(lat1) * sin(lat2) + cos(lat1) * cos(lat2) * cos(deltaAz)
        return acos(cosine.clamped(to: -1 ... 1)).degrees
    }
}

/// Observer position on Earth. East longitude positive, as in every formula here.
public struct GeographicCoordinates: Sendable, Hashable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

extension EquatorialCoordinates {

    /// Convert to a direction to point the camera, for an observer at a place and time.
    ///
    /// The standard rotation from the equatorial to the horizontal frame. Sanity checks
    /// that this satisfies: Polaris (dec ≈ +90°) always lands due north at an altitude
    /// equal to the observer's latitude, and an object on the meridian south of zenith
    /// lands at azimuth 180°.
    public func horizontal(at location: GeographicCoordinates, date: Date) -> HorizontalCoordinates {
        let jd = AstroTime.julianDate(from: date)
        let lst = AstroTime.localSiderealTime(jd: jd, longitude: location.longitude)

        let hourAngle = (lst - rightAscension).radians
        let dec = declination.radians
        let lat = location.latitude.radians

        let sinAltitude = sin(dec) * sin(lat) + cos(dec) * cos(lat) * cos(hourAngle)
        let altitude = asin(sinAltitude.clamped(to: -1 ... 1))

        // atan2 form of the azimuth, measured from true north through east.
        let azimuth = atan2(
            -cos(dec) * sin(hourAngle),
            sin(dec) * cos(lat) - cos(dec) * sin(lat) * cos(hourAngle)
        )

        return HorizontalCoordinates(azimuth: azimuth.degrees, altitude: altitude.degrees)
    }
}

/// Ecliptic longitude/latitude — the frame the Sun and Moon are naturally computed in.
public struct EclipticCoordinates: Sendable, Hashable {
    public var longitude: Double
    public var latitude: Double

    public init(longitude: Double, latitude: Double) {
        self.longitude = longitude
        self.latitude = latitude
    }

    /// Rotate onto the equator by the obliquity. Meeus eq. 13.3–13.4.
    public func equatorial(jd: Double) -> EquatorialCoordinates {
        let eps = AstroTime.obliquityOfEcliptic(jd: jd).radians
        let lon = longitude.radians
        let lat = latitude.radians

        let rightAscension = atan2(
            sin(lon) * cos(eps) - tan(lat) * sin(eps),
            cos(lon)
        )
        let declination = asin(
            (sin(lat) * cos(eps) + cos(lat) * sin(eps) * sin(lon)).clamped(to: -1 ... 1)
        )

        return EquatorialCoordinates(
            rightAscension: rightAscension.degrees,
            declination: declination.degrees
        )
    }
}
