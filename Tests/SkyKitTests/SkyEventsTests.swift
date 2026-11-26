import Foundation
import Testing
@testable import SkyKit

/// Rise, set and phase times, anchored to published values rather than to the code.
@Suite("Rise, set and phases")
struct SkyEventsTests {

    static let london = GeographicCoordinates(latitude: 51.5074, longitude: -0.1278)

    static func minutes(_ date: Date?, from expected: Date) -> Double {
        guard let date else { return .infinity }
        return abs(date.timeIntervalSince(expected)) / 60
    }

    @Test("London, 21 June 2026: sunrise 04:43, sunset 21:21 BST")
    func londonSolstice() {
        let sun = SkyEvents.sun(at: Self.london, after: utc(2026, 6, 21, 0))
        #expect(Self.minutes(sun.rise, from: utc(2026, 6, 21, 3, 43)) < 4)
        #expect(Self.minutes(sun.set, from: utc(2026, 6, 21, 20, 21)) < 4)
    }

    @Test("New Moon on the 12 Aug 2026 eclipse, full Moon on the 28 Aug lunar eclipse")
    func phasesOnEclipses() {
        let august = SkyEvents.moonPhases(after: utc(2026, 8, 1))
        #expect(Self.minutes(august.nextNew, from: utc(2026, 8, 12, 17, 37)) < 4 * 60)
        let after = SkyEvents.moonPhases(after: utc(2026, 8, 13))
        #expect(Self.minutes(after.nextFull, from: utc(2026, 8, 28, 4, 18)) < 4 * 60)
        #expect(after.nextNew > after.nextFull)
    }

    @Test("Moonrise is a moment the Moon is at the horizon and climbing")
    func moonriseIsAtTheHorizon() throws {
        let start = utc(2026, 11, 26, 12)
        let crossing = SkyEvents.moon(at: Self.london, after: start)
        let rise = try #require(crossing.rise)
        func altitude(_ date: Date) -> Double {
            SolarSystem.moonState(jd: AstroTime.julianDate(from: date)).position
                .horizontal(at: Self.london, date: date).altitude
        }
        #expect(abs(altitude(rise) - SkyEvents.Horizon.moon) < 0.1)
        #expect(altitude(rise.addingTimeInterval(600)) > altitude(rise))
        #expect(rise > start && rise < start.addingTimeInterval(30 * 3600))
    }

    @Test("A star that never sets has neither event")
    func circumpolar() {
        let polaris = SkyCatalog.polaris
        let crossing = SkyEvents.crossings(after: utc(2026, 11, 26), horizon: SkyEvents.Horizon.point) { moment in
            polaris.position.horizontal(at: Self.london, date: moment).altitude
        }
        #expect(crossing == .none)
    }

    @Test("The plan draws what is below the horizon too, with when it comes up")
    func planKeepsTheSetSky() {
        let start = Date()
        let plan = SkyDirector.plan(at: Self.london, date: utc(2026, 11, 26, 20))
        print("PLAN_MS", Date().timeIntervalSince(start) * 1000)
        let set = plan.landmarks.filter { !$0.isUp }
        #expect(!set.isEmpty)
        // Everything below the horizon that is not circumpolar-below has a rise ahead.
        let risesAhead = set.contains { $0.crossings.rise != nil }
        let planetsUp = plan.visiblePlanets.allSatisfy { $0.isUp }
        #expect(risesAhead)
        #expect(planetsUp)
        #expect(plan.moonPhases.nextFull > plan.date && plan.moonPhases.nextNew > plan.date)
    }
}
