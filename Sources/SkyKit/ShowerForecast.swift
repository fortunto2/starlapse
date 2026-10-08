import Foundation

/// What a meteor shower will be worth from one place, night by night.
///
/// A shower's calendar is the same for everyone; whether it is worth a cold night is not.
/// The Eta Aquariids peak at 50/h for an observer at the equator and never clear the
/// horizon in darkness from Oslo. The Geminids are superb unless a full Moon sits next to
/// the radiant that year. So the forecast is computed for a latitude and longitude, across
/// every night of the shower's window, and the answer is the night and hour that actually
/// deliver — which is often not the catalogue peak.
public struct ShowerForecast: Sendable, Identifiable {
    public var id: String { shower.code }

    public let shower: MeteorShower
    /// The catalogue peak, as a calendar day in UTC.
    public let peak: Date
    /// The evening whose night gives the highest rate from this location. The date of the
    /// evening, not of the small hours after midnight, because that is how people plan.
    public let bestNight: Date
    /// The instant of that highest rate.
    public let bestTime: Date
    /// Meteors per hour an observer should expect then, under a clear dark sky.
    public let bestRate: Double
    public let radiantAtBest: HorizontalCoordinates
    public let moonIlluminationAtBest: Double
    public let moonUpAtBest: Bool
    /// The rate on the catalogue peak night itself, for the honest comparison.
    public let peakNightRate: Double
    public let verdict: Verdict

    public enum Verdict: Sendable, Hashable {
        /// 20/h and up: a night to plan around.
        case excellent
        /// 8/h and up: a few per frame-hour, worth a stack.
        case good
        /// Something, but do not drive for it.
        case marginal
        /// Under 3/h on the best night, with the radiant up and the Moon down: a weak
        /// shower, or one seen from the wrong side of the planet.
        case faint
        /// The Moon takes most of it on every night of the window.
        case moonWashed
        /// The radiant never rises in darkness at this latitude. Not this shower, not here.
        case belowHorizon
    }

    /// Whether the best night is the one starting on `date`'s UTC day.
    public func isTonight(_ date: Date) -> Bool {
        Calendar.gregorianUTC.isDate(bestNight, inSameDayAs: date)
    }

    /// Something to plan around, as opposed to a shower listed so its absence is explained.
    public var isWorthPlanning: Bool {
        switch verdict {
        case .excellent, .good, .marginal: true
        case .faint, .moonWashed, .belowHorizon: false
        }
    }
}

extension SkyDirector {

    /// Every shower whose window touches the next `days`, forecast for this location and
    /// ordered by best night. The default covers a season.
    public static func forecast(
        at location: GeographicCoordinates,
        from date: Date,
        days: Int = 90
    ) -> [ShowerForecast] {
        let calendar = Calendar.gregorianUTC
        let today = calendar.startOfDay(for: date)
        guard let horizon = calendar.date(byAdding: .day, value: days, to: today) else { return [] }

        return MeteorShower.catalog
            .compactMap { shower -> ShowerForecast? in
                guard let window = shower.nextWindow(from: today, calendar: calendar),
                      window.start <= horizon else { return nil }
                // A window already under way is searched from tonight: the best night of
                // the Delta Aquariids is no use once it has passed.
                let remaining = MeteorShower.ActivityWindow(
                    start: max(window.start, today), peak: window.peak, end: window.end
                )
                return forecast(shower: shower, window: remaining, at: location, calendar: calendar)
            }
            .sorted { $0.bestNight < $1.bestNight }
    }

    /// The darkest night ahead: the day the Moon is least illuminated within `days`.
    public static func nextNewMoon(after date: Date, days: Int = 35) -> Date {
        let calendar = Calendar.gregorianUTC
        let start = calendar.startOfDay(for: date)
        var best = (date: start, fraction: 2.0)
        // Three-hour steps: a daily sample at midnight lands on the wrong day whenever the
        // new Moon falls in the afternoon.
        for step in 0 ... days * 8 {
            let moment = start.addingTimeInterval(Double(step) * 3 * 3600)
            let fraction = SolarSystem.moonState(jd: AstroTime.julianDate(from: moment)).illuminatedFraction
            if fraction < best.fraction { best = (moment, fraction) }
        }
        return calendar.startOfDay(for: best.date)
    }

    static func forecast(
        shower: MeteorShower,
        window: MeteorShower.ActivityWindow,
        at location: GeographicCoordinates,
        calendar: Calendar
    ) -> ShowerForecast? {
        var best: NightResult?
        var peakNight: NightResult?
        var everAboveHorizon = false
        var anyNight = false

        var evening = window.start
        while evening <= window.end {
            if let result = bestMoment(ofNightStarting: evening, shower: shower, at: location) {
                anyNight = true
                everAboveHorizon = everAboveHorizon || result.radiantEverUp
                if result.rate > (best?.rate ?? -1) { best = result }
                if calendar.isDate(evening, inSameDayAs: window.peak) { peakNight = result }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: evening) else { break }
            evening = next
        }
        guard anyNight, let best else { return nil }

        let verdict: ShowerForecast.Verdict
        switch best.rate {
        case 20...: verdict = .excellent
        case 8...: verdict = .good
        case 3...: verdict = .marginal
        default:
            // Nothing worth the night. Say why: no radiant in darkness, a Moon on it, or
            // simply a weak shower.
            if !everAboveHorizon {
                verdict = .belowHorizon
            } else if best.moonUp && best.moonIllumination > 0.4 {
                verdict = .moonWashed
            } else {
                verdict = .faint
            }
        }

        return ShowerForecast(
            shower: shower,
            peak: window.peak,
            bestNight: best.evening,
            bestTime: best.moment,
            bestRate: best.rate,
            radiantAtBest: best.radiant,
            moonIlluminationAtBest: best.moonIllumination,
            moonUpAtBest: best.moonUp,
            peakNightRate: peakNight?.rate ?? 0,
            verdict: verdict
        )
    }

    struct NightResult {
        let evening: Date
        let moment: Date
        let rate: Double
        let radiant: HorizontalCoordinates
        let moonIllumination: Double
        let moonUp: Bool
        let radiantEverUp: Bool
    }

    /// Walk one night in 20-minute steps and keep the moment with the highest rate.
    ///
    /// "Night" is local solar noon to local solar noon — longitude stands in for a time
    /// zone, so the search needs no clock other than UTC — and only moments in
    /// astronomical night count. A result with rate 0 is still a result: it says the
    /// radiant was below the horizon, or the Moon on it, which the verdict needs.
    static func bestMoment(
        ofNightStarting evening: Date,
        shower: MeteorShower,
        at location: GeographicCoordinates
    ) -> NightResult? {
        let solarNoon = evening.addingTimeInterval((12 - location.longitude / 15) * 3600)
        var best: NightResult?
        var everUp = false
        var sawNight = false

        for step in 0 ..< 72 {
            let moment = solarNoon.addingTimeInterval(Double(step) * 1200)
            let twilight = SolarSystem.twilightPhase(at: location, date: moment)
            guard twilight.isDarkEnoughForAstrophotography else { continue }
            sawNight = true

            let jd = AstroTime.julianDate(from: moment)
            let moon = SolarSystem.moonState(jd: jd)
            let moonPosition = moon.position.horizontal(at: location, date: moment)
            let conditions = Conditions(
                twilight: twilight, moon: moon, moonPosition: moonPosition, darkness: 1
            )
            let radiant = shower.radiant.horizontal(at: location, date: moment)
            everUp = everUp || radiant.altitude > 10
            let rate = expectedRate(shower: shower, radiant: radiant, date: moment, conditions: conditions)

            if rate > (best?.rate ?? -1) {
                best = NightResult(
                    evening: evening, moment: moment, rate: rate, radiant: radiant,
                    moonIllumination: moon.illuminatedFraction, moonUp: moonPosition.isAboveHorizon,
                    radiantEverUp: everUp
                )
            }
        }
        guard sawNight, let found = best else { return nil }
        return NightResult(
            evening: found.evening, moment: found.moment, rate: found.rate, radiant: found.radiant,
            moonIllumination: found.moonIllumination, moonUp: found.moonUp, radiantEverUp: everUp
        )
    }
}

extension MeteorShower {

    /// The next activity window on or after `date`: start, peak and end as UTC days.
    /// A window already under way counts, so the Perseids on 20 August are "now", not
    /// "next July".
    /// One occurrence of a shower's activity, as UTC days.
    public struct ActivityWindow: Sendable, Hashable {
        public let start: Date
        public let peak: Date
        public let end: Date
    }

    func nextWindow(from date: Date, calendar: Calendar) -> ActivityWindow? {
        let year = calendar.component(.year, from: date)
        for candidateYear in [year - 1, year, year + 1] {
            guard let start = activeFrom.date(in: candidateYear, calendar: calendar) else { continue }
            // A window that straddles New Year ends in the following year.
            let endYear = activeTo.ordinal < activeFrom.ordinal ? candidateYear + 1 : candidateYear
            let peakYear = peak.ordinal < activeFrom.ordinal ? candidateYear + 1 : candidateYear
            guard let end = activeTo.date(in: endYear, calendar: calendar),
                  let peakDate = peak.date(in: peakYear, calendar: calendar) else { continue }
            if end >= date { return ActivityWindow(start: start, peak: peakDate, end: end) }
        }
        return nil
    }
}

extension MeteorShower.MonthDay {
    func date(in year: Int, calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}
