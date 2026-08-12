import Foundation
import Testing
@testable import SkyKit

/// Planet positions are checked against orbital mechanics rather than against an almanac
/// I half-remember. Each of these would fail loudly if the Kepler solver or the frame
/// rotations were wrong, and none of them require trusting a number I typed from memory.
@Suite("Planets")
struct PlanetTests {

    static func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        guard let date = Calendar.gregorianUTC.date(from: components) else {
            fatalError("Bad test date")
        }
        return date
    }

    @Test("Kepler's equation inverts correctly")
    func keplerSolverInverts() {
        for eccentricity in [0.0, 0.02, 0.09, 0.21, 0.5] {
            for degrees in stride(from: 0.0, to: 360.0, by: 15.0) {
                let meanAnomaly = degrees.radians
                let eccentric = PlanetEphemeris.solveKepler(
                    meanAnomaly: meanAnomaly, eccentricity: eccentricity
                )
                // The solution must satisfy the equation it solves.
                let reconstructed = eccentric - eccentricity * sin(eccentric)
                #expect(abs((reconstructed - meanAnomaly).signedDegrees) < 1e-5)
            }
        }
    }

    @Test("Inner planets never stray far from the Sun")
    func innerPlanetsStayNearTheSun() {
        // Mercury and Venus orbit inside Earth's, so their greatest elongation is fixed by
        // geometry: about 28° and 47°. If the heliocentric-to-geocentric step were wrong,
        // this is the first thing that would break.
        let limits = ["Mercury": 29.0, "Venus": 48.0]

        for month in 1...12 {
            let jd = AstroTime.julianDate(from: Self.utc(2026, month, 1))
            let sun = SolarSystem.sunPosition(jd: jd)
            let equator = GeographicCoordinates(latitude: 0, longitude: 0)
            let date = Self.utc(2026, month, 1)

            for planet in PlanetEphemeris.positions(jd: jd) {
                guard let limit = limits[planet.name] else { continue }
                let separation = planet.position
                    .horizontal(at: equator, date: date)
                    .separation(from: sun.horizontal(at: equator, date: date))
                #expect(separation < limit, "\(planet.name) \(separation)° from Sun in month \(month)")
            }
        }
    }

    @Test("Planets stay close to the ecliptic")
    func planetsHugTheEcliptic() {
        // Every major planet orbits within a few degrees of Earth's orbital plane. Measured
        // as distance from the Sun's own path, none should stray past about 10°.
        for year in [2026, 2028, 2031] {
            let jd = AstroTime.julianDate(from: Self.utc(year, 3, 15))
            let obliquity = AstroTime.obliquityOfEcliptic(jd: jd).radians

            for planet in PlanetEphemeris.positions(jd: jd) {
                let ra = planet.position.rightAscension.radians
                let dec = planet.position.declination.radians
                // Convert back to ecliptic latitude.
                let beta = asin(
                    (sin(dec) * cos(obliquity) - cos(dec) * sin(obliquity) * sin(ra))
                        .clamped(to: -1 ... 1)
                ).degrees
                #expect(abs(beta) < 10, "\(planet.name) at ecliptic latitude \(beta)°")
            }
        }
    }

    @Test("Orbital periods emerge from the elements")
    func periodsMatchKeplersThirdLaw() {
        // Return each planet to the same heliocentric longitude after one sidereal period.
        // The periods below are Kepler's third law, T = a^1.5 years, not memorised values.
        for planet in Planet.catalog {
            let period = pow(planet.elements.semiMajorAxis, 1.5) * 365.256
            let start = AstroTime.julianDate(from: Self.utc(2026, 1, 1))

            let first = PlanetEphemeris.heliocentric(
                planet.elements.advanced(centuries: AstroTime.julianCenturies(since: start))
            )
            let later = PlanetEphemeris.heliocentric(
                planet.elements.advanced(
                    centuries: AstroTime.julianCenturies(since: start + period)
                )
            )

            let firstLongitude = atan2(first.y, first.x).degrees
            let laterLongitude = atan2(later.y, later.x).degrees
            let drift = abs((laterLongitude - firstLongitude).signedDegrees)
            #expect(drift < 1.5, "\(planet.name) drifted \(drift)° over one period")
        }
    }

    @Test("Distances stay within each orbit's real bounds")
    func distancesArePhysical() {
        // Geocentric distance can never exceed the planet's aphelion plus Earth's, nor drop
        // below the difference of their perihelia.
        for month in 1...12 {
            let jd = AstroTime.julianDate(from: Self.utc(2027, month, 1))
            for planet in PlanetEphemeris.positions(jd: jd) {
                let a = planet.planet.elements.semiMajorAxis
                let e = planet.planet.elements.eccentricity
                let maximum = a * (1 + e) + 1.02
                let minimum = max(0.0, a * (1 - e) - 1.02)
                #expect(planet.distanceAU <= maximum)
                #expect(planet.distanceAU >= minimum)
            }
        }
    }

    @Test("Venus is the brightest planet, and brighter than any star")
    func venusOutshinesEverything() {
        // Venus reaches about −4, brighter than Sirius at −1.46. Any ordering bug in the
        // magnitude calculation shows up here.
        let jd = AstroTime.julianDate(from: Self.utc(2026, 8, 13))
        let planets = PlanetEphemeris.positions(jd: jd)

        guard let venus = planets.first(where: { $0.name == "Venus" }) else {
            Issue.record("Venus missing")
            return
        }
        #expect(venus.magnitude < -3.0)
        #expect(venus.magnitude < -1.46)
        #expect(venus.isNakedEyeBright)

        // Jupiter and Saturn are far away but huge; all five should be naked-eye objects.
        for planet in planets {
            #expect(planet.magnitude < 3.0, "\(planet.name) too faint at \(planet.magnitude)")
        }
    }

    @Test("Mars varies in brightness far more than the outer planets")
    func marsVariesWithDistance() {
        // Mars swings between roughly 0.4 and 2.6 AU from Earth — a factor of six — while
        // Jupiter and Saturn are so far away that Earth's own orbit barely changes the
        // distance. So the comparison is the real physics; an absolute magnitude range
        // would just be testing how well this model approximates the phase angle, which it
        // deliberately does not model at all.
        // Sampled every five days, not monthly: Mars reaches opposition once every 26
        // months and its distance changes fastest right there, so a coarse grid steps
        // straight over the peak and understates the range.
        func magnitudeRange(of name: String) -> Double {
            let start = AstroTime.julianDate(from: Self.utc(2026, 1, 1))
            var brightest = Double.infinity
            var faintest = -Double.infinity

            for step in 0..<220 {
                let jd = start + Double(step) * 5
                guard let planet = PlanetEphemeris.positions(jd: jd)
                    .first(where: { $0.name == name }) else { continue }
                brightest = min(brightest, planet.magnitude)
                faintest = max(faintest, planet.magnitude)
            }
            return faintest - brightest
        }

        // Roughly 2.5 magnitudes across this window. The textbook figure is nearer 4.5, but
        // that belongs to a *close* opposition, and those fall 15–17 years apart — none
        // lands in 2026–2029. Asserting the headline number would be asserting a fact about
        // a different decade.
        let mars = magnitudeRange(of: "Mars")
        #expect(mars > 2.0)
        #expect(mars > magnitudeRange(of: "Jupiter") * 2)
        #expect(mars > magnitudeRange(of: "Saturn") * 2)
    }
}
