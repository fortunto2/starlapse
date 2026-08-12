import Foundation
import SkyKit

/// Build a UTC instant from calendar fields.
///
/// Raw `timeIntervalSince1970` constants are banned in these tests on purpose: the first
/// draft of the sky suite had four of them and three pointed at a different day than their
/// comment claimed. The tests failed, and the maths was fine.
func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
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
