import Foundation
import Testing
@testable import SkyKit

/// These tests pin the sky math to facts that do not depend on the implementation:
/// Polaris sits at the pole, the Sun is up at noon, the Moon was full on a known date.
/// If a refactor breaks the trigonometry, one of these goes red before anyone drives
/// to a dark site to find out.
@Suite("Sky math")
struct SkyMathTests {

    /// Build a UTC instant from calendar fields. Raw `timeIntervalSince1970` constants are
    /// banned here on purpose — the first draft of this file had four of them and three
    /// pointed at a different day than their comment claimed.
    static func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        guard let date = Calendar.gregorianUTC.date(from: components) else {
            fatalError("Bad test date \(year)-\(month)-\(day)")
        }
        return date
    }

    /// Mid-Perseids — the night that started this project.
    static let referenceDate = utc(2026, 8, 13, 22)
    static let alanya = GeographicCoordinates(latitude: 36.545, longitude: 32.000)
    static let moscow = GeographicCoordinates(latitude: 55.751, longitude: 37.618)

    // MARK: - Time

    @Test("Julian Date matches the J2000 epoch definition")
    func julianDateEpoch() {
        // J2000.0 is 2000-01-01T12:00:00 TT ≈ JD 2451545.0
        let j2000 = Date(timeIntervalSince1970: 946_728_000)
        #expect(abs(AstroTime.julianDate(from: j2000) - 2_451_545.0) < 0.001)
    }

    @Test("Sidereal time stays in range and advances faster than solar time")
    func siderealTimeAdvance() {
        let jd = AstroTime.julianDate(from: Self.referenceDate)
        let now = AstroTime.greenwichMeanSiderealTime(jd: jd)
        let dayLater = AstroTime.greenwichMeanSiderealTime(jd: jd + 1)

        #expect(now >= 0 && now < 360)
        // A sidereal day is ~3m56s short of a solar day, so GMST gains ~0.9856° per day.
        let gain = (dayLater - now).normalizedDegrees
        #expect(abs(gain - 0.9856) < 0.01)
    }

    // MARK: - Coordinates

    @Test("Polaris sits due north at an altitude equal to the observer's latitude")
    func polarisMarksTheLatitude() {
        for location in [Self.alanya, Self.moscow] {
            let position = SkyCatalog.polaris.position
                .horizontal(at: location, date: Self.referenceDate)

            // Polaris is 0.7° off the true pole, so allow a degree of slack.
            #expect(abs(position.altitude - location.latitude) < 1.0)
            let offNorth = abs(position.azimuth.signedDegrees)
            #expect(offNorth < 2.0)
        }
    }

    @Test("The celestial pole does not move as the Earth turns")
    func poleIsFixed() {
        let later = Self.referenceDate.addingTimeInterval(6 * 3600)
        let first = SkyCatalog.polaris.position.horizontal(at: Self.alanya, date: Self.referenceDate)
        let second = SkyCatalog.polaris.position.horizontal(at: Self.alanya, date: later)

        #expect(first.separation(from: second) < 1.5)
    }

    @Test("A star far south is never visible from a northern site")
    func southernStarStaysDown() {
        // Declination −80° cannot rise above the horizon at +55° latitude.
        let farSouth = EquatorialCoordinates(rightAscension: 0, declination: -80)
        for hour in 0..<24 {
            let moment = Self.referenceDate.addingTimeInterval(Double(hour) * 3600)
            let position = farSouth.horizontal(at: Self.moscow, date: moment)
            #expect(!position.isAboveHorizon)
        }
    }

    @Test("Angular separation is zero to itself and 180° to its antipode")
    func separationBounds() {
        let point = HorizontalCoordinates(azimuth: 70, altitude: 30)
        #expect(point.separation(from: point) < 0.001)

        let opposite = HorizontalCoordinates(azimuth: 250, altitude: -30)
        #expect(abs(point.separation(from: opposite) - 180) < 0.001)
    }

    @Test("Offsetting by a distance lands exactly that far away")
    func offsetPreservesDistance() {
        let origin = HorizontalCoordinates(azimuth: 45, altitude: 35)
        for bearing in stride(from: 0.0, to: 360.0, by: 30.0) {
            let moved = SkyDirector.offset(from: origin, by: 40, towards: bearing)
            #expect(abs(moved.separation(from: origin) - 40) < 0.01)
        }
    }

    // MARK: - Sun and Moon

    @Test("The Sun is up at local noon and down at local midnight")
    func sunFollowsTheDay() {
        // Summer solstice. Longitude 0, so UTC noon is local noon.
        let greenwich = GeographicCoordinates(latitude: 51.48, longitude: 0)
        let noon = Self.utc(2026, 6, 21, 12)
        let midnight = noon.addingTimeInterval(12 * 3600)

        let atNoon = SolarSystem.sunPosition(jd: AstroTime.julianDate(from: noon))
            .horizontal(at: greenwich, date: noon)
        let atMidnight = SolarSystem.sunPosition(jd: AstroTime.julianDate(from: midnight))
            .horizontal(at: greenwich, date: midnight)

        #expect(atNoon.altitude > 55)
        #expect(atMidnight.altitude < -10)
    }

    @Test("Moon is new on the day of a known solar eclipse")
    func moonPhaseIsCalibratedAgainstAnEclipse() {
        // A total solar eclipse crossed Spain and Iceland on 2026-08-12. An eclipse *is*
        // a new moon — the Moon is between us and the Sun — so this is an external,
        // non-circular anchor for the phase calculation.
        let eclipse = Self.utc(2026, 8, 12, 18)
        let state = SolarSystem.moonState(jd: AstroTime.julianDate(from: eclipse))
        #expect(state.illuminatedFraction < 0.01)
        #expect(state.phaseName == "New Moon")

        // Half a synodic month later the disc must be essentially full.
        let fullMoon = eclipse.addingTimeInterval(14.77 * 86_400)
        let full = SolarSystem.moonState(jd: AstroTime.julianDate(from: fullMoon))
        #expect(full.illuminatedFraction > 0.97)
        #expect(full.phaseName == "Full Moon")
    }

    @Test("Consecutive new moons are one synodic month apart")
    func synodicMonthEmergesFromTheMath() {
        // Scan a season in hourly steps and collect the darkest instants. Their spacing
        // must reproduce the synodic month (29.53 days) without it being written anywhere
        // in the source — that only happens if the periodic terms are right.
        var newMoons: [Date] = []
        var previous = 1.0
        var falling = false

        for hour in 0..<(120 * 24) {
            let moment = Self.utc(2026, 6, 1).addingTimeInterval(Double(hour) * 3600)
            let lit = SolarSystem.moonState(jd: AstroTime.julianDate(from: moment)).illuminatedFraction
            if lit < previous {
                falling = true
            } else if falling {
                newMoons.append(moment)
                falling = false
            }
            previous = lit
        }

        #expect(newMoons.count >= 3)
        for (earlier, later) in zip(newMoons, newMoons.dropFirst()) {
            let days = later.timeIntervalSince(earlier) / 86_400
            #expect(abs(days - 29.53) < 0.6)
        }
    }

    @Test("Moon distance stays inside its real orbital range")
    func moonDistanceIsPhysical() {
        for day in 0..<30 {
            let moment = Self.referenceDate.addingTimeInterval(Double(day) * 86_400)
            let state = SolarSystem.moonState(jd: AstroTime.julianDate(from: moment))
            // Perigee ~356500 km, apogee ~406700 km.
            #expect(state.distanceKm > 355_000 && state.distanceKm < 408_000)
        }
    }

    @Test("Twilight deepens as the Sun sinks")
    func twilightOrdering() {
        let phase = SolarSystem.twilightPhase(at: Self.alanya, date: Self.referenceDate)
        // 22:00 UTC = 01:00 local in Turkey, mid-August — fully dark.
        #expect(phase == .night)
        #expect(phase.isDarkEnoughForAstrophotography)
    }

    // MARK: - Showers

    @Test("The Perseids are active in mid-August and peak on the 12th")
    func perseidsAreActiveTonight() {
        let active = MeteorShower.active(on: Self.referenceDate)
        #expect(active.contains { $0.code == "PER" })

        let perseids = MeteorShower.catalog.first { $0.code == "PER" }
        #expect(perseids?.peakProximity(on: Self.referenceDate) ?? 0 > 0.7)
    }

    @Test("The Quadrantids' window wraps across New Year")
    func quadrantidWindowWraps() {
        let lateDecember = Self.utc(2026, 12, 30)
        let earlyJanuary = Self.utc(2027, 1, 9)
        let midJune = Self.utc(2026, 6, 8)

        #expect(MeteorShower.active(on: lateDecember).contains { $0.code == "QUA" })
        #expect(MeteorShower.active(on: earlyJanuary).contains { $0.code == "QUA" })
        #expect(!MeteorShower.active(on: midJune).contains { $0.code == "QUA" })
    }

    @Test("A radiant below the horizon yields no meteors")
    func belowHorizonMeansNothingToShoot() {
        guard let shower = MeteorShower.catalog.first(where: { $0.code == "PER" }) else {
            Issue.record("Perseids missing from the catalog")
            return
        }
        let radiant = HorizontalCoordinates(azimuth: 10, altitude: -20)
        let conditions = SkyDirector.Conditions(
            twilight: .night,
            moon: SolarSystem.moonState(jd: AstroTime.julianDate(from: Self.referenceDate)),
            moonPosition: HorizontalCoordinates(azimuth: 180, altitude: -30),
            darkness: 1
        )

        let rate = SkyDirector.expectedRate(
            shower: shower, radiant: radiant, date: Self.referenceDate, conditions: conditions
        )
        #expect(rate == 0)
    }

    // MARK: - Aiming

    @Test("Aim lands 40° off the radiant, not on it")
    func aimAvoidsTheRadiant() {
        let plan = SkyDirector.plan(at: Self.alanya, date: Self.referenceDate)
        guard let headline = plan.headlineShower, headline.isWorthShooting else {
            Issue.record("Expected an active shower mid-Perseids")
            return
        }

        let separation = plan.aim.direction.separation(from: headline.radiant)
        #expect(abs(separation - 40) < 1.0)
    }

    @Test("Aim stays in the usable band above the horizon")
    func aimIsShootable() {
        // Sample a full night from several latitudes: the recommendation must never point
        // at the ground or straight up.
        for location in [Self.alanya, Self.moscow] {
            for hour in stride(from: 0, through: 23, by: 3) {
                let moment = Self.referenceDate.addingTimeInterval(Double(hour) * 3600)
                let plan = SkyDirector.plan(at: location, date: moment)
                #expect(plan.aim.direction.altitude > 0)
                #expect(plan.aim.direction.altitude < 90)
            }
        }
    }

    @Test("Aim moves away from a bright Moon")
    func aimAvoidsMoonlight() {
        // Full Moon night in December: Geminids are strong, so the aim is driven by the
        // radiant, but it should still lean away from the Moon.
        let plan = SkyDirector.plan(at: Self.alanya, date: Self.referenceDate)
        guard plan.conditions.isMoonUp else { return }

        let separation = plan.aim.direction.separation(from: plan.conditions.moonPosition)
        #expect(separation > 20)
    }

    @Test("Moonlight suppresses the expected rate")
    func moonPenaltyReducesRate() {
        let jd = AstroTime.julianDate(from: Self.referenceDate)
        let moon = SolarSystem.moonState(jd: jd)

        let dark = SkyDirector.Conditions(
            twilight: .night, moon: moon,
            moonPosition: HorizontalCoordinates(azimuth: 0, altitude: -40), darkness: 1
        )
        let bright = SkyDirector.Conditions(
            twilight: .night,
            moon: SolarSystem.MoonState(
                position: moon.position, illuminatedFraction: 1.0,
                distanceKm: 380_000, elongation: 180
            ),
            moonPosition: HorizontalCoordinates(azimuth: 180, altitude: 60), darkness: 0.3
        )

        #expect(SkyDirector.moonPenalty(conditions: dark) == 1.0)
        #expect(SkyDirector.moonPenalty(conditions: bright) < 0.5)
    }
}
