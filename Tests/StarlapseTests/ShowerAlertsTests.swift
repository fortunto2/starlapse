import Foundation
import SkyKit
import Testing
@testable import Starlapse

/// When a shower reminder fires and what it says. The rule that matters most is the one
/// about the clock: a peak at 04:20 must not become a notification at 02:20.
@Suite("Shower alerts")
struct ShowerAlertsTests {

    static let madrid: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid") ?? .gmt
        return calendar
    }()

    static func local(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let parts = DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)
        return madrid.date(from: parts) ?? .distantPast
    }

    static func forecast(
        _ code: String, best: Date, rate: Double = 40,
        verdict: ShowerForecast.Verdict = .excellent
    ) -> ShowerForecast {
        let shower = MeteorShower.catalog.first { $0.code == code } ?? MeteorShower.catalog[0]
        return ShowerForecast(
            shower: shower, peak: best, bestNight: best, bestTime: best, bestRate: rate,
            radiantAtBest: HorizontalCoordinates(azimuth: 45, altitude: 60),
            moonIlluminationAtBest: 0.1, moonUpAtBest: false, peakNightRate: rate, verdict: verdict
        )
    }

    @Test("A small-hours peak is announced the evening before, at 20:00 local")
    func smallHoursPeakRingsTheEveningBefore() throws {
        let best = Self.local(10, 21, 4, 20)
        let alerts = ShowerAlerts.schedule(
            [Self.forecast("ORI", best: best)], now: Self.local(10, 12, 12), calendar: Self.madrid, isPro: true
        )
        let alert = try #require(alerts.first)
        #expect(alert.fireDate == Self.local(10, 20, 20))
    }

    @Test("An evening peak rings an hour before it, not after")
    func eveningPeakRingsAnHourBefore() throws {
        let best = Self.local(10, 8, 20, 30)
        let alerts = ShowerAlerts.schedule(
            [Self.forecast("DRA", best: best)], now: Self.local(10, 1, 12), calendar: Self.madrid, isPro: true
        )
        #expect(try #require(alerts.first).fireDate == Self.local(10, 8, 19, 30))
    }

    @Test("Only nights worth planning, nothing in the past, at most eight")
    func filters() {
        let now = Self.local(10, 12, 12)
        let forecasts = [
            Self.forecast("ORI", best: Self.local(10, 1, 4)),                         // past
            Self.forecast("STA", best: Self.local(11, 5, 1), verdict: .marginal),     // too weak
            Self.forecast("LEO", best: Self.local(11, 17, 5), verdict: .good),
            Self.forecast("URS", best: Self.local(12, 22, 6), verdict: .moonWashed),
        ] + (0..<10).map { Self.forecast("GEM", best: Self.local(12, 1, 2).addingTimeInterval(Double($0) * 86_400)) }
        let alerts = ShowerAlerts.schedule(forecasts, now: now, calendar: Self.madrid, isPro: true)
        #expect(alerts.count == 8)
        #expect(alerts.allSatisfy { $0.fireDate > now })
        #expect(alerts.first?.showerCode == "LEO")
        #expect(!alerts.contains { $0.showerCode == "STA" || $0.showerCode == "URS" || $0.showerCode == "ORI" })
    }

    @Test("Pro gets the hour and the direction; free gets the night and the name")
    func contentFollowsTheGate() throws {
        let best = Self.local(10, 21, 4, 20)
        let now = Self.local(10, 12, 12)
        let pro = try #require(ShowerAlerts.schedule(
            [Self.forecast("ORI", best: best)], now: now, calendar: Self.madrid, isPro: true
        ).first)
        let free = try #require(ShowerAlerts.schedule(
            [Self.forecast("ORI", best: best)], now: now, calendar: Self.madrid, isPro: false
        ).first)
        #expect(pro.title.contains("Orionids"))
        #expect(free.title.contains("Orionids"))
        #expect(pro.body.contains("~40/h"))
        #expect(pro.body.contains("NE"))
        #expect(!free.body.contains("~40/h"))
        #expect(!free.body.contains("NE"))
    }

    @Test("Identifiers are stable per shower and night, so rescheduling replaces, never doubles")
    func stableIdentifiers() {
        let best = Self.local(10, 21, 4, 20)
        let now = Self.local(10, 12, 12)
        let first = ShowerAlerts.schedule(
            [Self.forecast("ORI", best: best)], now: now, calendar: Self.madrid, isPro: true
        )
        let second = ShowerAlerts.schedule(
            [Self.forecast("ORI", best: best, rate: 41)], now: now, calendar: Self.madrid, isPro: true
        )
        #expect(first.map(\.id) == second.map(\.id))
        #expect(first.first?.id.hasPrefix(ShowerAlerts.prefix) == true)
    }
}
