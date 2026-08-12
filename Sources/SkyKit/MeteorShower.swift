import Foundation

/// A meteor shower and the point it appears to stream from.
///
/// Meteors do not fall where the radiant is — they streak *away* from it, and the longest,
/// most photogenic trails appear 20–40° off to the side. What the radiant altitude actually
/// governs is *how many* you see: rates scale roughly with its sine, which is why a shower
/// with the radiant near the horizon is worth almost nothing no matter its headline ZHR.
public struct MeteorShower: Sendable, Hashable, Identifiable {
    public var id: String { code }

    /// IAU three-letter code, e.g. `PER`.
    public let code: String
    public let name: String
    /// Where the meteors appear to come from, epoch J2000.
    public let radiant: EquatorialCoordinates
    /// Zenithal Hourly Rate at the peak — an idealised count under a perfect dark sky
    /// with the radiant overhead. Real-world counts are always lower.
    public let zenithalHourlyRate: Int
    /// Atmospheric entry speed, km/s. Fast showers give brief, sharp trails; slow ones
    /// give long, lingering ones that suit long exposures better.
    public let velocityKmPerSecond: Int
    /// Day-of-year window and peak, in the Gregorian calendar. Showers drift by under a
    /// day per decade, so fixed dates are fine for a camera app.
    public let activeFrom: MonthDay
    public let activeTo: MonthDay
    public let peak: MonthDay

    public struct MonthDay: Sendable, Hashable {
        public let month: Int
        public let day: Int

        public init(_ month: Int, _ day: Int) {
            self.month = month
            self.day = day
        }
    }
}

extension MeteorShower {

    /// The major annual showers, from the IMO working list.
    public static let catalog: [MeteorShower] = [
        MeteorShower(
            code: "QUA", name: "Quadrantids",
            radiant: EquatorialCoordinates(raHours: 15, raMinutes: 20, dec: 49.5),
            zenithalHourlyRate: 110, velocityKmPerSecond: 41,
            activeFrom: MonthDay(12, 28), activeTo: MonthDay(1, 12), peak: MonthDay(1, 3)
        ),
        MeteorShower(
            code: "LYR", name: "Lyrids",
            radiant: EquatorialCoordinates(raHours: 18, raMinutes: 4, dec: 33.3),
            zenithalHourlyRate: 18, velocityKmPerSecond: 49,
            activeFrom: MonthDay(4, 16), activeTo: MonthDay(4, 25), peak: MonthDay(4, 22)
        ),
        MeteorShower(
            code: "ETA", name: "Eta Aquariids",
            radiant: EquatorialCoordinates(raHours: 22, raMinutes: 30, dec: -1.0),
            zenithalHourlyRate: 50, velocityKmPerSecond: 66,
            activeFrom: MonthDay(4, 19), activeTo: MonthDay(5, 28), peak: MonthDay(5, 6)
        ),
        MeteorShower(
            code: "CAP", name: "Alpha Capricornids",
            radiant: EquatorialCoordinates(raHours: 20, raMinutes: 28, dec: -10.2),
            zenithalHourlyRate: 5, velocityKmPerSecond: 23,
            activeFrom: MonthDay(7, 3), activeTo: MonthDay(8, 15), peak: MonthDay(7, 30)
        ),
        MeteorShower(
            code: "SDA", name: "Southern Delta Aquariids",
            radiant: EquatorialCoordinates(raHours: 22, raMinutes: 40, dec: -16.4),
            zenithalHourlyRate: 25, velocityKmPerSecond: 41,
            activeFrom: MonthDay(7, 12), activeTo: MonthDay(8, 23), peak: MonthDay(7, 30)
        ),
        MeteorShower(
            code: "PER", name: "Perseids",
            radiant: EquatorialCoordinates(raHours: 3, raMinutes: 13, dec: 58.1),
            zenithalHourlyRate: 100, velocityKmPerSecond: 59,
            activeFrom: MonthDay(7, 17), activeTo: MonthDay(8, 24), peak: MonthDay(8, 12)
        ),
        MeteorShower(
            code: "DRA", name: "Draconids",
            radiant: EquatorialCoordinates(raHours: 17, raMinutes: 28, dec: 54.0),
            zenithalHourlyRate: 10, velocityKmPerSecond: 20,
            activeFrom: MonthDay(10, 6), activeTo: MonthDay(10, 10), peak: MonthDay(10, 8)
        ),
        MeteorShower(
            code: "ORI", name: "Orionids",
            radiant: EquatorialCoordinates(raHours: 6, raMinutes: 21, dec: 15.6),
            zenithalHourlyRate: 20, velocityKmPerSecond: 66,
            activeFrom: MonthDay(10, 2), activeTo: MonthDay(11, 7), peak: MonthDay(10, 21)
        ),
        MeteorShower(
            code: "STA", name: "Southern Taurids",
            radiant: EquatorialCoordinates(raHours: 3, raMinutes: 32, dec: 15.0),
            zenithalHourlyRate: 5, velocityKmPerSecond: 27,
            activeFrom: MonthDay(9, 10), activeTo: MonthDay(11, 20), peak: MonthDay(11, 5)
        ),
        MeteorShower(
            code: "LEO", name: "Leonids",
            radiant: EquatorialCoordinates(raHours: 10, raMinutes: 8, dec: 21.6),
            zenithalHourlyRate: 15, velocityKmPerSecond: 71,
            activeFrom: MonthDay(11, 6), activeTo: MonthDay(11, 30), peak: MonthDay(11, 17)
        ),
        MeteorShower(
            code: "GEM", name: "Geminids",
            radiant: EquatorialCoordinates(raHours: 7, raMinutes: 28, dec: 32.2),
            zenithalHourlyRate: 150, velocityKmPerSecond: 35,
            activeFrom: MonthDay(12, 4), activeTo: MonthDay(12, 17), peak: MonthDay(12, 14)
        ),
        MeteorShower(
            code: "URS", name: "Ursids",
            radiant: EquatorialCoordinates(raHours: 14, raMinutes: 28, dec: 75.3),
            zenithalHourlyRate: 10, velocityKmPerSecond: 33,
            activeFrom: MonthDay(12, 17), activeTo: MonthDay(12, 26), peak: MonthDay(12, 22)
        ),
    ]

    /// Showers active on a given date, strongest first.
    ///
    /// Windows that straddle New Year (the Quadrantids) are handled by comparing against
    /// both ends rather than by day-of-year arithmetic.
    public static func active(on date: Date, calendar: Calendar = .gregorianUTC) -> [MeteorShower] {
        let components = calendar.dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day else { return [] }
        let today = MonthDay(month, day)

        return catalog
            .filter { $0.isActive(on: today) }
            .sorted { $0.zenithalHourlyRate > $1.zenithalHourlyRate }
    }

    func isActive(on today: MonthDay) -> Bool {
        let start = activeFrom.ordinal
        let end = activeTo.ordinal
        let now = today.ordinal
        // A window that wraps past December has start > end.
        return start <= end ? (now >= start && now <= end) : (now >= start || now <= end)
    }

    /// How close to peak, 0…1, falling off over the shower's own window. Most showers have
    /// a broad shoulder and a sharp peak, so we taper over ±5 days and floor it at the
    /// background rate rather than modelling each shower's true profile.
    public func peakProximity(on date: Date, calendar: Calendar = .gregorianUTC) -> Double {
        let components = calendar.dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day else { return 0 }
        let distance = abs(MonthDay(month, day).ordinal - peak.ordinal)
        // Wrap around the year boundary.
        let days = Double(min(distance, 365 - distance))
        return max(0.15, 1.0 - days / 5.0)
    }
}

extension MeteorShower.MonthDay {
    /// Day of a non-leap year. Only ever used for comparisons, so the leap day drift
    /// (one day, in one direction, in some years) is immaterial.
    var ordinal: Int {
        let cumulative = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
        guard month >= 1, month <= 12 else { return 0 }
        return cumulative[month - 1] + day
    }
}

extension Calendar {
    /// Sky math is all in UTC; a local calendar would shift shower windows by a day
    /// near midnight.
    public static let gregorianUTC: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()
}
