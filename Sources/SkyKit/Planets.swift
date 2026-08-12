import Foundation

/// A planet visible to the naked eye.
///
/// Worth having in a camera app for a reason beyond completeness: Jupiter and Venus are
/// bright enough to ruin a frame the way a small Moon would, and Mars sitting inside your
/// composition is the difference between "nice shot" and "nice shot with Mars in it". They
/// also make excellent focus targets — a planet is the brightest point source in the sky
/// short of the Moon.
public struct Planet: Sendable, Hashable, Identifiable {
    public var id: String { name }
    public let name: String
    /// Absolute magnitude H, used to estimate brightness at a given geometry.
    let absoluteMagnitude: Double
    let elements: OrbitalElements
}

/// Keplerian elements and their per-century rates, from JPL's "Approximate Positions of
/// the Major Planets". Valid 1800–2050 to well under a degree — far tighter than anyone
/// aims a phone, and a fraction of the code a full VSOP87 series would need.
struct OrbitalElements: Sendable, Hashable {
    /// Semi-major axis, AU.
    let semiMajorAxis: Double
    let eccentricity: Double
    /// Inclination, degrees.
    let inclination: Double
    /// Mean longitude, degrees.
    let meanLongitude: Double
    /// Longitude of perihelion, degrees.
    let perihelionLongitude: Double
    /// Longitude of the ascending node, degrees.
    let ascendingNode: Double

    let semiMajorAxisRate: Double
    let eccentricityRate: Double
    let inclinationRate: Double
    let meanLongitudeRate: Double
    let perihelionLongitudeRate: Double
    let ascendingNodeRate: Double

    /// Advance the elements to a given epoch.
    func advanced(centuries t: Double) -> OrbitalElements {
        OrbitalElements(
            semiMajorAxis: semiMajorAxis + semiMajorAxisRate * t,
            eccentricity: eccentricity + eccentricityRate * t,
            inclination: inclination + inclinationRate * t,
            meanLongitude: meanLongitude + meanLongitudeRate * t,
            perihelionLongitude: perihelionLongitude + perihelionLongitudeRate * t,
            ascendingNode: ascendingNode + ascendingNodeRate * t,
            semiMajorAxisRate: 0, eccentricityRate: 0, inclinationRate: 0,
            meanLongitudeRate: 0, perihelionLongitudeRate: 0, ascendingNodeRate: 0
        )
    }
}

/// A planet's position and brightness at a moment.
public struct PlanetPosition: Sendable, Hashable, Identifiable {
    public var id: String { planet.name }
    public let planet: Planet
    public let position: EquatorialCoordinates
    /// Apparent visual magnitude — lower is brighter.
    public let magnitude: Double
    /// Distance from Earth, AU.
    public let distanceAU: Double

    public var name: String { planet.name }

    /// Bright enough to matter in a photograph, and to find by eye.
    public var isNakedEyeBright: Bool { magnitude < 2.0 }
}

extension Planet {

    public static let catalog: [Planet] = [
        Planet(
            name: "Mercury", absoluteMagnitude: -0.36,
            elements: OrbitalElements(
                semiMajorAxis: 0.387_099_27, eccentricity: 0.205_635_93,
                inclination: 7.004_979_02, meanLongitude: 252.250_323_50,
                perihelionLongitude: 77.457_796_28, ascendingNode: 48.330_765_93,
                semiMajorAxisRate: 0.000_000_37, eccentricityRate: 0.000_019_06,
                inclinationRate: -0.005_947_49, meanLongitudeRate: 149_472.674_111_75,
                perihelionLongitudeRate: 0.160_476_89, ascendingNodeRate: -0.125_340_81
            )
        ),
        Planet(
            name: "Venus", absoluteMagnitude: -4.29,
            elements: OrbitalElements(
                semiMajorAxis: 0.723_335_66, eccentricity: 0.006_776_72,
                inclination: 3.394_676_05, meanLongitude: 181.979_099_50,
                perihelionLongitude: 131.602_467_18, ascendingNode: 76.679_842_55,
                semiMajorAxisRate: 0.000_003_90, eccentricityRate: -0.000_041_07,
                inclinationRate: -0.000_788_90, meanLongitudeRate: 58_517.815_387_29,
                perihelionLongitudeRate: 0.002_683_29, ascendingNodeRate: -0.277_694_18
            )
        ),
        Planet(
            name: "Mars", absoluteMagnitude: -1.52,
            elements: OrbitalElements(
                semiMajorAxis: 1.523_710_34, eccentricity: 0.093_394_10,
                inclination: 1.849_691_42, meanLongitude: -4.553_432_05,
                perihelionLongitude: -23.943_629_59, ascendingNode: 49.559_538_91,
                semiMajorAxisRate: 0.000_018_47, eccentricityRate: 0.000_078_82,
                inclinationRate: -0.008_131_31, meanLongitudeRate: 19_140.302_684_99,
                perihelionLongitudeRate: 0.444_410_88, ascendingNodeRate: -0.292_573_43
            )
        ),
        Planet(
            name: "Jupiter", absoluteMagnitude: -9.25,
            elements: OrbitalElements(
                semiMajorAxis: 5.202_887_00, eccentricity: 0.048_386_24,
                inclination: 1.304_396_95, meanLongitude: 34.396_440_51,
                perihelionLongitude: 14.728_479_83, ascendingNode: 100.473_909_09,
                semiMajorAxisRate: -0.000_116_07, eccentricityRate: -0.000_132_53,
                inclinationRate: -0.001_837_14, meanLongitudeRate: 3_034.746_127_75,
                perihelionLongitudeRate: 0.212_526_68, ascendingNodeRate: 0.204_691_06
            )
        ),
        Planet(
            name: "Saturn", absoluteMagnitude: -8.88,
            elements: OrbitalElements(
                semiMajorAxis: 9.536_675_94, eccentricity: 0.053_861_79,
                inclination: 2.485_991_87, meanLongitude: 49.954_244_23,
                perihelionLongitude: 92.598_878_31, ascendingNode: 113.662_424_48,
                semiMajorAxisRate: -0.001_250_60, eccentricityRate: -0.000_509_91,
                inclinationRate: 0.001_936_09, meanLongitudeRate: 1_222.493_622_01,
                perihelionLongitudeRate: -0.418_972_16, ascendingNodeRate: -0.288_677_94
            )
        ),
    ]

    /// Earth's own orbit — needed to turn heliocentric positions into what we see.
    static let earth = OrbitalElements(
        semiMajorAxis: 1.000_002_61, eccentricity: 0.016_711_23,
        inclination: -0.000_015_31, meanLongitude: 100.464_571_66,
        perihelionLongitude: 102.937_681_93, ascendingNode: 0.0,
        semiMajorAxisRate: 0.000_005_62, eccentricityRate: -0.000_043_92,
        inclinationRate: -0.012_946_68, meanLongitudeRate: 35_999.372_449_81,
        perihelionLongitudeRate: 0.323_273_64, ascendingNodeRate: 0.0
    )
}

public enum PlanetEphemeris {

    /// Where every naked-eye planet is, brightest first.
    public static func positions(jd: Double) -> [PlanetPosition] {
        let t = AstroTime.julianCenturies(since: jd)
        let earth = heliocentric(Planet.earth.advanced(centuries: t))

        return Planet.catalog
            .map { planet in
                let elements = planet.elements.advanced(centuries: t)
                let helio = heliocentric(elements)

                // Geocentric = heliocentric planet minus heliocentric Earth. This is the
                // whole reason Mars appears to loop backwards: we are on a moving platform.
                let geo = Vector3(
                    x: helio.x - earth.x,
                    y: helio.y - earth.y,
                    z: helio.z - earth.z
                )

                let distance = geo.length
                let sunDistance = helio.length
                let magnitude = planet.absoluteMagnitude
                    + 5 * log10(max(sunDistance * distance, 1e-6))

                let ecliptic = EclipticCoordinates(
                    longitude: atan2(geo.y, geo.x).degrees,
                    latitude: asin((geo.z / max(distance, 1e-9)).clamped(to: -1 ... 1)).degrees
                )

                return PlanetPosition(
                    planet: planet,
                    position: ecliptic.equatorial(jd: jd),
                    magnitude: magnitude,
                    distanceAU: distance
                )
            }
            .sorted { $0.magnitude < $1.magnitude }
    }

    // MARK: - Orbit solving

    struct Vector3 {
        let x: Double
        let y: Double
        let z: Double

        var length: Double { (x * x + y * y + z * z).squareRoot() }
    }

    /// Position in the ecliptic frame, in AU, relative to the Sun.
    static func heliocentric(_ elements: OrbitalElements) -> Vector3 {
        let meanAnomaly = (elements.meanLongitude - elements.perihelionLongitude).signedDegrees
        let eccentricAnomaly = solveKepler(
            meanAnomaly: meanAnomaly.radians,
            eccentricity: elements.eccentricity
        )

        // Position in the orbital plane.
        let a = elements.semiMajorAxis
        let e = elements.eccentricity
        let xOrbital = a * (cos(eccentricAnomaly) - e)
        let yOrbital = a * (1 - e * e).squareRoot() * sin(eccentricAnomaly)

        // Rotate: argument of perihelion, then inclination, then ascending node.
        let argument = (elements.perihelionLongitude - elements.ascendingNode).radians
        let node = elements.ascendingNode.radians
        let inclination = elements.inclination.radians

        let cosArgument = cos(argument), sinArgument = sin(argument)
        let cosNode = cos(node), sinNode = sin(node)
        let cosInclination = cos(inclination), sinInclination = sin(inclination)

        // Written out term by term: as one expression the Swift type checker gives up.
        let xx = cosArgument * cosNode - sinArgument * sinNode * cosInclination
        let xy = -sinArgument * cosNode - cosArgument * sinNode * cosInclination
        let yx = cosArgument * sinNode + sinArgument * cosNode * cosInclination
        let yy = -sinArgument * sinNode + cosArgument * cosNode * cosInclination
        let zx = sinArgument * sinInclination
        let zy = cosArgument * sinInclination

        let xEcliptic = xx * xOrbital + xy * yOrbital
        let yEcliptic = yx * xOrbital + yy * yOrbital
        let zEcliptic = zx * xOrbital + zy * yOrbital

        return Vector3(x: xEcliptic, y: yEcliptic, z: zEcliptic)
    }

    /// Kepler's equation, M = E − e·sin E, by Newton–Raphson.
    ///
    /// No closed form exists; this is the classic iteration and it converges in a handful
    /// of steps for every planetary eccentricity (all well under 0.25).
    static func solveKepler(meanAnomaly: Double, eccentricity: Double, tolerance: Double = 1e-8) -> Double {
        var eccentricAnomaly = meanAnomaly + eccentricity * sin(meanAnomaly)

        for _ in 0..<20 {
            let delta = (eccentricAnomaly - eccentricity * sin(eccentricAnomaly) - meanAnomaly)
                / (1 - eccentricity * cos(eccentricAnomaly))
            eccentricAnomaly -= delta
            if abs(delta) < tolerance { break }
        }

        return eccentricAnomaly
    }
}
