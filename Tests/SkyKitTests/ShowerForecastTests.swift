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
        let forecasts = SkyDirector.forecast(at: Self.laPalma, from: utc(2026, 8, 12, 1), days: 30)
        for forecast in forecasts {
            #expect(forecast.bestNight >= utc(2026, 8, 12), "\(forecast.shower.code) \(forecast.bestNight)")
        }
        let perseids = try #require(forecasts.first { $0.shower.code == "PER" })
        #expect(perseids.isTonight(utc(2026, 8, 12, 1)))
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

    @Test("The next new Moon after 1 August 2026 is the eclipse day")
    func newMoon() {
        #expect(SkyDirector.nextNewMoon(after: utc(2026, 8, 1)) == utc(2026, 8, 12))
    }
}
