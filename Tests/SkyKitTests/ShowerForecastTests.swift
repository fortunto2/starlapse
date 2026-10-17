import Foundation
import Testing
@testable import SkyKit

/// The forecast is judged on nights people know: the 2026 Perseids fall on a new Moon
/// (the 12 August solar eclipse), a northern radiant barely rises from Sydney, and
/// Tromsø has no astronomical night in May at all.
@Suite("Shower forecast")
struct ShowerForecastTests {

    static let laPalma = GeographicCoordinates(latitude: 28.754, longitude: -17.885)
    /// Far enough south for the Quadrantid radiant (dec +49.5°) to peak at 7°, and far enough
    /// from the pole to have an astronomical night in January.
    static let sydney = GeographicCoordinates(latitude: -33.87, longitude: 151.21)
    static let tromso = GeographicCoordinates(latitude: 69.65, longitude: 18.96)
    static let mumbai = GeographicCoordinates(latitude: 19.076, longitude: 72.877)

    @Test("Perseids 2026 from La Palma: an excellent, moonless night around the 12th")
    func perseids2026() throws {
        let forecasts = SkyDirector.forecast(at: Self.laPalma, from: utc(2026, 7, 1), days: 60)
        let perseids = try #require(forecasts.first { $0.shower.code == "PER" })
        #expect(perseids.verdict == .excellent)
        #expect(perseids.bestRate > 20)
        #expect(perseids.moonIlluminationAtBest < 0.15)
        #expect(perseids.bestNight >= utc(2026, 8, 10) && perseids.bestNight <= utc(2026, 8, 14))
        #expect(perseids.peak == utc(2026, 8, 12))
        // Best moment is in the small hours, when the radiant is high.
        #expect(perseids.radiantAtBest.altitude > 40)
    }

    @Test("A northern radiant from Sydney is below the horizon, not merely weak")
    func quadrantidsFromTheSouth() throws {
        let forecasts = SkyDirector.forecast(at: Self.sydney, from: utc(2025, 12, 20), days: 30)
        let quadrantids = try #require(forecasts.first { $0.shower.code == "QUA" })
        #expect(quadrantids.verdict == .belowHorizon)
        #expect(quadrantids.bestRate < 1)
    }

    @Test("No astronomical night, no forecast: Tromsø in May lists nothing")
    func midnightSun() {
        let forecasts = SkyDirector.forecast(at: Self.tromso, from: utc(2026, 5, 1), days: 20)
        #expect(forecasts.isEmpty)
    }

    @Test("Forecasts come in calendar order and the window already under way counts")
    func orderingAndCurrentWindow() throws {
        let forecasts = SkyDirector.forecast(at: Self.mumbai, from: utc(2026, 10, 8), days: 90)
        let nights = forecasts.map(\.bestNight)
        #expect(nights == nights.sorted())
        // Orionids (2 Oct – 7 Nov) are active on the 8th, Geminids peak inside 90 days.
        #expect(forecasts.contains { $0.shower.code == "ORI" })
        #expect(forecasts.contains { $0.shower.code == "GEM" })
        #expect(!forecasts.contains { $0.shower.code == "PER" })
    }

    @Test("A window under way is searched from tonight, never from a night that has passed")
    func noNightsInThePast() throws {
        // 15:00 UTC on the 12th is past local solar noon on La Palma: the 11th's night is over.
        let now = utc(2026, 8, 12, 15)
        let longitude = Self.laPalma.longitude
        let forecasts = SkyDirector.forecast(at: Self.laPalma, from: now, days: 30)
        for forecast in forecasts {
            #expect(forecast.bestNight >= utc(2026, 8, 12), "\(forecast.shower.code) \(forecast.bestNight)")
        }
        let perseids = try #require(forecasts.first { $0.shower.code == "PER" })
        #expect(perseids.isTonight(now, longitude: longitude))
        // 01:00 UTC is 23:48 local solar time on the 11th: the peak night is under way and counts.
        let duringPeak = SkyDirector.forecast(at: Self.laPalma, from: utc(2026, 8, 12, 1), days: 30)
        let tonight = try #require(duringPeak.first { $0.shower.code == "PER" })
        #expect(tonight.bestNight >= utc(2026, 8, 11))
    }

    @Test("A weak shower past its peak on a moonless night is faint, not moon-washed")
    func faintNotMoonWashed() throws {
        // Alpha Capricornids (ZHR 5, peak 30 July) on 12 August 2026, new Moon.
        let forecasts = SkyDirector.forecast(at: Self.laPalma, from: utc(2026, 8, 12, 1), days: 10)
        let capricornids = try #require(forecasts.first { $0.shower.code == "CAP" })
        #expect(capricornids.verdict == .faint)
        #expect(capricornids.moonIlluminationAtBest < 0.1)
    }

    @Test("A window across New Year resolves to the coming January")
    func windowAcrossNewYear() throws {
        let shower = try #require(MeteorShower.catalog.first { $0.code == "QUA" })
        let window = try #require(shower.nextWindow(from: utc(2026, 12, 30), calendar: .gregorianUTC))
        #expect(window.start == utc(2026, 12, 28))
        #expect(window.peak == utc(2027, 1, 3))
        #expect(window.end == utc(2027, 1, 12))
    }

    @Test("A night runs noon to noon in local solar time, not by the UTC calendar")
    func nightIsLocal() {
        // 17:30 PDT on 20 October is 00:30 UTC on the 21st; the night is still the 20th's.
        #expect(SkyDirector.night(containing: utc(2026, 10, 21, 0, 30), longitude: -118.25) == utc(2026, 10, 20))
        // 03:00 in Madrid belongs to the night that began the evening before.
        #expect(SkyDirector.night(containing: utc(2026, 10, 21, 1), longitude: -3.7) == utc(2026, 10, 20))
        // 08:00 in Tokyo on the 21st is still the night of the 20th; by 13:00 it is the 21st's.
        #expect(SkyDirector.night(containing: utc(2026, 10, 20, 23), longitude: 139.7) == utc(2026, 10, 20))
        #expect(SkyDirector.night(containing: utc(2026, 10, 21, 4), longitude: 139.7) == utc(2026, 10, 21))
    }

    @Test("West of Greenwich, tonight survives UTC midnight: 13:00 and 17:30 in LA agree")
    func tonightSurvivesUTCMidnight() throws {
        let losAngeles = GeographicCoordinates(latitude: 34.05, longitude: -118.25)
        let afternoon = SkyDirector.forecast(at: losAngeles, from: utc(2026, 10, 20, 20), days: 30)
        let evening = SkyDirector.forecast(at: losAngeles, from: utc(2026, 10, 21, 0, 30), days: 30)
        let before = try #require(afternoon.first { $0.shower.code == "ORI" })
        let after = try #require(evening.first { $0.shower.code == "ORI" })
        #expect(after.bestNight == before.bestNight)
        #expect(after.isTonight(utc(2026, 10, 21, 0, 30), longitude: -118.25) == before.isTonight(
            utc(2026, 10, 20, 20), longitude: -118.25
        ))
    }

    @Test("The next new Moon after 1 August 2026 is the eclipse day")
    func newMoon() {
        #expect(SkyDirector.nextNewMoon(after: utc(2026, 8, 1)) == utc(2026, 8, 12))
    }
}
