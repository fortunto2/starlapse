import Foundation

/// The galactic frame, so the Milky Way can be drawn as the line it is rather than as a
/// point at its centre.
///
/// The band of light is the galactic equator (latitude 0) seen edge-on from inside the
/// disc. Its brightness is far from uniform: the bulge around the centre in Sagittarius is
/// the richest stretch, the anticentre in Auriga is faint enough to miss under a town sky.
/// `GalacticPoint.brightness` carries that, as a weight the overlay can draw with.
public struct GalacticCoordinates: Sendable, Hashable {
    /// Degrees in `[0, 360)`, 0 toward the galactic centre, increasing toward Cygnus.
    public var longitude: Double
    /// Degrees in `[-90, 90]`, 0 on the plane of the disc.
    public var latitude: Double

    public init(longitude: Double, latitude: Double) {
        self.longitude = longitude.normalizedDegrees
        self.latitude = latitude.clamped(to: -90 ... 90)
    }

    // IAU 1958 definition of the frame, expressed in J2000 (Reid & Brunthaler 2004).
    static let northPoleRA = 192.85948.radians
    static let northPoleDec = 27.12825.radians
    /// Galactic longitude of the celestial north pole.
    static let celestialPoleLongitude = 122.93192.radians

    /// Rotate into the equatorial frame, J2000.
    public var equatorial: EquatorialCoordinates {
        let lat = latitude.radians
        let dl = Self.celestialPoleLongitude - longitude.radians

        let sinDec = sin(lat) * sin(Self.northPoleDec) + cos(lat) * cos(Self.northPoleDec) * cos(dl)
        let dec = asin(sinDec.clamped(to: -1 ... 1))
        let y = cos(lat) * sin(dl)
        let x = sin(lat) * cos(Self.northPoleDec) - cos(lat) * sin(Self.northPoleDec) * cos(dl)
        let ra = Self.northPoleRA + atan2(y, x)

        return EquatorialCoordinates(rightAscension: ra.degrees, declination: dec.degrees)
    }
}

/// One sample of the galactic equator, with how bright that stretch of the band is.
public struct GalacticPoint: Sendable, Hashable {
    public let longitude: Double
    public let position: EquatorialCoordinates
    /// 0…1. Ones near the centre, falling to a floor at the anticentre. A shape, not a
    /// photometric model: it decides line weight, nothing else.
    public let brightness: Double
}

extension SkyCatalog {

    /// The galactic equator sampled every `step` degrees of longitude, starting at the
    /// centre. 10° gives 36 points: smooth as a line across a phone screen, cheap to
    /// resolve once per plan.
    public static func galacticEquator(step: Double = 10) -> [GalacticPoint] {
        stride(from: 0.0, to: 360.0, by: step).map { longitude in
            let offset = abs(longitude.signedDegrees)
            // Bright from the centre out through Scorpius and Cygnus (|l| < 90), then the
            // thin outer arm through Perseus and Auriga.
            let brightness = offset < 90 ? 1.0 - 0.5 * (offset / 90) : 0.5 - 0.3 * ((offset - 90) / 90)
            return GalacticPoint(
                longitude: longitude,
                position: GalacticCoordinates(longitude: longitude, latitude: 0).equatorial,
                brightness: brightness
            )
        }
    }
}
