import Foundation

/// The two bodies that decide whether tonight is worth shooting at all.
///
/// The Sun sets the window — real astronomical darkness needs it 18° below the horizon.
/// The Moon sets the ceiling — a gibbous Moon above the horizon washes out the Milky Way
/// no matter how long you stack. Everything else in the sky is a subject; these two are
/// the lighting conditions.
public enum SolarSystem {

    // MARK: - Sun

    /// Apparent position of the Sun. Meeus ch. 25, low-precision branch (±0.01°).
    public static func sunPosition(jd: Double) -> EquatorialCoordinates {
        let n = jd - 2_451_545.0
        let meanLongitude = (280.460 + 0.985_647_4 * n).normalizedDegrees
        let meanAnomaly = (357.528 + 0.985_600_3 * n).normalizedDegrees.radians

        let eclipticLongitude = meanLongitude
            + 1.915 * sin(meanAnomaly)
            + 0.020 * sin(2 * meanAnomaly)

        return EclipticCoordinates(longitude: eclipticLongitude, latitude: 0)
            .equatorial(jd: jd)
    }

    // MARK: - Moon

    public struct MoonState: Sendable, Hashable {
        public let position: EquatorialCoordinates
        /// Fraction of the disc lit, 0…1.
        public let illuminatedFraction: Double
        /// Distance in kilometres — drives apparent size, and supermoon bragging rights.
        public let distanceKm: Double
        /// Elongation from the Sun in degrees, 0 = new, 180 = full.
        public let elongation: Double

        /// Waxing means the lit limb grows night over night.
        public var isWaxing: Bool { elongation <= 180 }

        public var phaseName: String {
            switch (illuminatedFraction, isWaxing) {
            case (..<0.02, _): "New Moon"
            case (..<0.45, true): "Waxing Crescent"
            case (..<0.55, true): "First Quarter"
            case (..<0.98, true): "Waxing Gibbous"
            case (0.98..., _): "Full Moon"
            case (..<0.45, false): "Waning Crescent"
            case (..<0.55, false): "Last Quarter"
            default: "Waning Gibbous"
            }
        }
    }

    /// Position and phase of the Moon. Meeus ch. 47 truncated to the leading periodic
    /// terms — accurate to roughly 0.3°, which is under the Moon's own diameter and far
    /// tighter than anyone aims a phone.
    public static func moonState(jd: Double) -> MoonState {
        let t = AstroTime.julianCenturies(since: jd)

        let meanLongitude = (218.316_447_7 + 481_267.881_234_21 * t).normalizedDegrees
        let elongationMean = (297.850_192_1 + 445_267.111_403_4 * t).normalizedDegrees.radians
        let sunAnomaly = (357.529_109_2 + 35_999.050_290_9 * t).normalizedDegrees.radians
        let moonAnomaly = (134.963_396_4 + 477_198.867_505_5 * t).normalizedDegrees.radians
        let latitudeArgument = (93.272_095_0 + 483_202.017_523_3 * t).normalizedDegrees.radians

        // Each periodic series is summed term by term. Written as one expression, the Swift
        // type checker gives up on it — these are all plain Doubles, so the split costs
        // nothing at runtime and keeps compile times sane.
        var longitude: Double = meanLongitude
        longitude += 6.289 * sin(moonAnomaly)
        longitude += 1.274 * sin(2 * elongationMean - moonAnomaly)
        longitude += 0.658 * sin(2 * elongationMean)
        longitude += 0.214 * sin(2 * moonAnomaly)
        longitude -= 0.186 * sin(sunAnomaly)
        longitude -= 0.114 * sin(2 * latitudeArgument)

        var latitude: Double = 5.128 * sin(latitudeArgument)
        latitude += 0.281 * sin(moonAnomaly + latitudeArgument)
        latitude -= 0.278 * sin(latitudeArgument - moonAnomaly)
        latitude -= 0.173 * sin(2 * elongationMean - latitudeArgument)

        var distance: Double = 385_001.0
        distance -= 20_905.0 * cos(moonAnomaly)
        distance -= 3_699.0 * cos(2 * elongationMean - moonAnomaly)
        distance -= 2_956.0 * cos(2 * elongationMean)
        distance -= 570.0 * cos(2 * moonAnomaly)

        let position = EclipticCoordinates(longitude: longitude, latitude: latitude)
            .equatorial(jd: jd)

        // Elongation from the Sun drives the phase. Sun at ecliptic latitude 0, so the
        // separation reduces to the longitude difference corrected by the Moon's latitude.
        let sunLongitude = sunEclipticLongitude(jd: jd)
        let separation = acos(
            (cos(latitude.radians) * cos((longitude - sunLongitude).radians))
                .clamped(to: -1 ... 1)
        ).degrees

        // Signed elongation so we can tell waxing from waning.
        let signedElongation = (longitude - sunLongitude).normalizedDegrees
        let illuminated = (1.0 - cos(separation.radians)) / 2.0

        return MoonState(
            position: position,
            illuminatedFraction: illuminated.clamped(to: 0 ... 1),
            distanceKm: distance,
            elongation: signedElongation
        )
    }

    private static func sunEclipticLongitude(jd: Double) -> Double {
        let n = jd - 2_451_545.0
        let meanLongitude = (280.460 + 0.985_647_4 * n).normalizedDegrees
        let meanAnomaly = (357.528 + 0.985_600_3 * n).normalizedDegrees.radians
        return (meanLongitude + 1.915 * sin(meanAnomaly) + 0.020 * sin(2 * meanAnomaly))
            .normalizedDegrees
    }

    // MARK: - Darkness

    public enum TwilightPhase: String, Sendable {
        case day = "Daylight"
        case civil = "Civil twilight"
        case nautical = "Nautical twilight"
        case astronomical = "Astronomical twilight"
        case night = "Astronomical night"

        /// Only true darkness gives faint stars and the Milky Way.
        public var isDarkEnoughForAstrophotography: Bool { self == .night }
    }

    /// Which twilight phase the observer is in, from the Sun's altitude.
    public static func twilightPhase(
        at location: GeographicCoordinates,
        date: Date
    ) -> TwilightPhase {
        let jd = AstroTime.julianDate(from: date)
        let altitude = sunPosition(jd: jd)
            .horizontal(at: location, date: date)
            .altitude

        switch altitude {
        case 0...: return .day
        case -6 ..< 0: return .civil
        case -12 ..< -6: return .nautical
        case -18 ..< -12: return .astronomical
        default: return .night
        }
    }
}
