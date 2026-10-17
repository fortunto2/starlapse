import Foundation
import SkyKit
import UserNotifications

/// Local reminders for the nights that deliver from here.
///
/// Nothing is sent anywhere: the schedule is built on the phone from the same forecast the
/// Events sheet shows, and handed to the system as calendar notifications. It is rebuilt
/// whenever the forecast is, so moving a hundred kilometres or a new Moon estimate replaces
/// the old reminders instead of adding to them.
///
/// The clock rule: a peak in the small hours is announced the evening before, at 20:00, so
/// the reminder is a plan for the night and never an alarm at 02:20. An evening peak gets at
/// least an hour's notice.
enum ShowerAlerts {

    struct Alert: Equatable, Identifiable {
        let id: String
        let showerCode: String
        let fireDate: Date
        let title: String
        let body: String
    }

    static let prefix = "shower-alert-"
    static let enabledKey = "showerAlerts"
    /// iOS keeps 64 pending; eight is a season, and leaves room for anything else later.
    static let limit = 8

    static let askedKey = "showerAlertsAsked"
    /// Shower code → when its last reminder was set to fire. A shower that has already rung
    /// is not announced again in the same window: after the true best night the forecast
    /// returns the best *remaining* one, and five "best night" reminders in a row is spam.
    static let firedKey = "showerAlertsFired"
    static let windowLength: TimeInterval = 45 * 86_400

    /// On unless switched off. Nothing shows until iOS permission is granted, and that is
    /// asked only after the first saved shot: someone who has made a picture knows why a
    /// "tonight" reminder would be worth having, someone on first launch does not.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Called after each save; asks iOS once, the first time, if reminders are on. Not on a
    /// save that just raised the rating prompt: two system alerts at once and one loses.
    static func askAfterSaveIfNeeded(ratingPromptShown: Bool = false) async {
        guard isEnabled, !ratingPromptShown, !UserDefaults.standard.bool(forKey: askedKey) else { return }
        UserDefaults.standard.set(true, forKey: askedKey)
        _ = await requestPermission()
    }

    // MARK: - The schedule, pure

    static func schedule(
        _ forecasts: [ShowerForecast], now: Date, calendar: Calendar, isPro: Bool,
        fired: [String: Date] = [:]
    ) -> [Alert] {
        forecasts
            .filter { $0.verdict == .excellent || $0.verdict == .good }
            .filter { forecast in
                guard let rang = fired[forecast.shower.code] else { return true }
                return rang > now || now.timeIntervalSince(rang) > windowLength
            }
            .compactMap { forecast -> Alert? in
                let fire = fireDate(for: forecast.bestTime, calendar: calendar)
                guard fire > now else { return nil }
                return alert(for: forecast, firing: fire, calendar: calendar, isPro: isPro)
            }
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(limit)
            .map { $0 }
    }

    /// 20:00 on the evening that leads into `best`, but never less than an hour before it:
    /// an evening peak at 20:30 rings at 19:30.
    /// Wall-clock 20:00, not twenty hours after midnight: those differ by an hour on the
    /// evenings the clocks change, and the Orionids sit on one in Europe.
    static func fireDate(for best: Date, calendar: Calendar) -> Date {
        let evening = calendar.startOfDay(for: best.addingTimeInterval(-12 * 3600))
        let eight = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: evening) ?? best
        let hourBefore = best.addingTimeInterval(-3600)
        return min(eight, hourBefore)
    }

    private static func alert(
        for forecast: ShowerForecast, firing fire: Date, calendar: Calendar, isPro: Bool
    ) -> Alert {
        let name = forecast.shower.name
        let night = calendar.startOfDay(for: forecast.bestTime.addingTimeInterval(-12 * 3600))
        let id = prefix + forecast.shower.code + "-" + String(Int(night.timeIntervalSince1970 / 86_400))
        let title = String(format: String(localized: "%@ tonight"), name)

        let body: String
        if isPro {
            var time = Date.FormatStyle(date: .omitted, time: .shortened)
            time.timeZone = calendar.timeZone
            body = String(
                format: String(localized: "Best at %@, ~%.0f/h. Radiant %@ %.0f° up. %@."),
                forecast.bestTime.formatted(time),
                forecast.bestRate,
                compassPoint(forAzimuth: forecast.radiantAtBest.azimuth),
                forecast.radiantAtBest.altitude,
                forecast.moonUpAtBest
                    ? String(localized: "Moon above the horizon")
                    : String(localized: "Moon below the horizon")
            )
        } else {
            body = String(localized: "A good night for it from where you are.")
        }
        return Alert(id: id, showerCode: forecast.shower.code, fireDate: fire, title: title, body: body)
    }

    // MARK: - The system, thin

    /// Ask once, from the toggle. Returns whether reminders may be shown.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Whether iOS has said no. Not asked yet is not a no: the first save asks.
    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    /// Remember when each scheduled shower will have rung. Entries that have not fired yet
    /// are replaced by this schedule; ones that have stay until their window is over.
    static func recordFired(_ alerts: [Alert], now: Date, defaults: UserDefaults = .standard) {
        let stored = defaults.dictionary(forKey: firedKey) as? [String: Double] ?? [:]
        var fired = stored.filter { _, time in
            let date = Date(timeIntervalSince1970: time)
            return date <= now && now.timeIntervalSince(date) <= windowLength
        }
        for alert in alerts { fired[alert.showerCode] = alert.fireDate.timeIntervalSince1970 }
        defaults.set(fired, forKey: firedKey)
    }

    static func fired(defaults: UserDefaults = .standard) -> [String: Date] {
        (defaults.dictionary(forKey: firedKey) as? [String: Double] ?? [:])
            .mapValues { Date(timeIntervalSince1970: $0) }
    }

    /// Replace every pending shower reminder with `alerts`. Empty clears them.
    static func apply(_ alerts: [Alert]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        )
        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            // To the second and pinned to this zone: a minute-truncated trigger built inside
            // its own minute has no next date and never fires, and a floating one rings an
            // hour off after crossing a border. The scene going active reschedules anyway.
            let components = Calendar.current.dateComponents(
                [.timeZone, .year, .month, .day, .hour, .minute, .second], from: alert.fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: alert.id, content: content, trigger: trigger))
        }
    }
}

/// Shows a reminder that fires while Starlapse is open. Without a delegate iOS drops it
/// silently, and a night session keeps the app in the foreground for hours.
final class ShowerAlertPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {

    static let shared = ShowerAlertPresenter()

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
