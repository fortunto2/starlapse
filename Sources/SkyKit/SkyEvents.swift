import Foundation

/// When something comes up or goes down, and when the Moon is next full or new.
///
/// The overlay used to draw only what was above the horizon, so the Moon an hour from rising
/// and the Sun about to set were simply absent. These are the answers to "is it coming soon?",
/// worked out once per plan rather than per frame.
public enum SkyEvents {

    /// The next rise and set after a moment, either of which may not happen in the window
    /// (circumpolar, or never up).
    public struct Crossings: Sendable, Hashable {
        public let rise: Date?
        public let set: Date?

        public init(rise: Date?, set: Date?) {
            self.rise = rise
            self.set = set
        }

        public static let none = Crossings(rise: nil, set: nil)
    }

    /// What the Sun and Moon do next, from one place and moment.
    public struct Ahead: Sendable, Hashable {
        public let sunPosition: HorizontalCoordinates
        public let sun: Crossings
        public let moon: Crossings
        public let moonPhases: MoonPhases
    }

    public static func ahead(at location: GeographicCoordinates, from date: Date) -> Ahead {
        let jd = AstroTime.julianDate(from: date)
        return Ahead(
            sunPosition: SolarSystem.sunPosition(jd: jd).horizontal(at: location, date: date),
            sun: sun(at: location, after: date),
            moon: moon(at: location, after: date),
            moonPhases: moonPhases(after: date)
        )
    }

    public struct MoonPhases: Sendable, Hashable {
        public let nextFull: Date
        public let nextNew: Date
    }

    /// Altitude of the horizon crossing, degrees, per body (USNO standard values): the Sun
    /// and Moon are timed by their upper limb with refraction; the Moon's parallax lifts it.
    public enum Horizon {
        public static let sun = -0.833
        public static let moon = 0.125
        public static let point = -0.567
    }

    /// Search for the next upward and downward crossing of `horizon` within `hours`.
    /// Twenty-minute steps, then bisection to under a minute: nothing in the sky rises and
    /// sets within twenty minutes at the latitudes people stand at.
    public static func crossings(
        after date: Date,
        hours: Double = 30,
        horizon: Double,
        altitude: (Date) -> Double
    ) -> Crossings {
        let step: TimeInterval = 20 * 60
        var rise: Date?
        var set: Date?
        var previous = (time: date, altitude: altitude(date) - horizon)
        var elapsed: TimeInterval = 0
        while elapsed < hours * 3600, rise == nil || set == nil {
            elapsed += step
            let time = date.addingTimeInterval(elapsed)
            let current = (time: time, altitude: altitude(time) - horizon)
            if previous.altitude < 0, current.altitude >= 0, rise == nil {
                rise = refine(from: previous.time, to: time, rising: true, horizon: horizon, altitude: altitude)
            } else if previous.altitude >= 0, current.altitude < 0, set == nil {
                set = refine(from: previous.time, to: time, rising: false, horizon: horizon, altitude: altitude)
            }
            previous = current
        }
        return Crossings(rise: rise, set: set)
    }

    private static func refine(
        from start: Date, to end: Date, rising: Bool, horizon: Double, altitude: (Date) -> Double
    ) -> Date {
        var low = start
        var high = end
        for _ in 0..<11 {   // 20 min / 2^11 ≈ 0.6 s
            let middle = Date(timeIntervalSince1970: (low.timeIntervalSince1970 + high.timeIntervalSince1970) / 2)
            let above = altitude(middle) >= horizon
            if above == rising { high = middle } else { low = middle }
        }
        return high
    }

    public static func sun(at location: GeographicCoordinates, after date: Date) -> Crossings {
        crossings(after: date, horizon: Horizon.sun) { moment in
            SolarSystem.sunPosition(jd: AstroTime.julianDate(from: moment))
                .horizontal(at: location, date: moment).altitude
        }
    }

    public static func moon(at location: GeographicCoordinates, after date: Date) -> Crossings {
        crossings(after: date, horizon: Horizon.moon) { moment in
            SolarSystem.moonState(jd: AstroTime.julianDate(from: moment)).position
                .horizontal(at: location, date: moment).altitude
        }
    }

    /// The next full and new Moon: the first maximum and minimum of the lit fraction ahead,
    /// sampled hourly. Within an hour or two of the published times is the claim; the
    /// caption shows days.
    public static func moonPhases(after date: Date) -> MoonPhases {
        func lit(_ hour: Int) -> Double {
            let moment = date.addingTimeInterval(Double(hour) * 3600)
            return SolarSystem.moonState(jd: AstroTime.julianDate(from: moment)).illuminatedFraction
        }
        var full: Date?
        var new: Date?
        var before = lit(0)
        var here = lit(1)
        // A lunation is 29.5 days; 31 holds the first of each extreme.
        for hour in 1 ..< 31 * 24 where full == nil || new == nil {
            let after = lit(hour + 1)
            let moment = date.addingTimeInterval(Double(hour) * 3600)
            if full == nil, here >= before, here > after { full = moment }
            if new == nil, here <= before, here < after { new = moment }
            before = here
            here = after
        }
        return MoonPhases(
            nextFull: full ?? date.addingTimeInterval(29.53 * 86400),
            nextNew: new ?? date.addingTimeInterval(29.53 * 86400)
        )
    }
}
