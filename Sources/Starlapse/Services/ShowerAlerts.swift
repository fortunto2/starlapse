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

    /// On unless switched off. Nothing shows until iOS permission is granted, and that is
    /// asked only after the first saved shot: someone who has made a picture knows why a
    /// "tonight" reminder would be worth having, someone on first launch does not.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Called after each save; asks iOS once, the first time, if reminders are on.
    static func askAfterSaveIfNeeded() async {
        guard isEnabled, !UserDefaults.standard.bool(forKey: askedKey) else { return }
        UserDefaults.standard.set(true, forKey: askedKey)
        _ = await requestPermission()
    }

    // MARK: - The schedule, pure

    static func schedule(
        _ forecasts: [ShowerForecast], now: Date, calendar: Calendar, isPro: Bool
    ) -> [Alert] {
        forecasts
            .filter { $0.verdict == .excellent || $0.verdict == .good }
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
    static func fireDate(for best: Date, calendar: Calendar) -> Date {
        let evening = calendar.startOfDay(for: best.addingTimeInterval(-12 * 3600))
        let eight = calendar.date(byAdding: .hour, value: 20, to: evening) ?? best
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
                format: String(localized: "Best at %@, ~%.0f/h. Radiant %@ %.0f° up, Moon %@."),
                forecast.bestTime.formatted(time),
                forecast.bestRate,
                compassPoint(forAzimuth: forecast.radiantAtBest.azimuth),
                forecast.radiantAtBest.altitude,
                forecast.moonUpAtBest ? String(localized: "up") : String(localized: "down")
            )
        } else {
            body = String(localized: "The best night for it from where you are. Open Starlapse to see when and where to aim.") // swiftlint:disable:this line_length
        }
        return Alert(id: id, showerCode: forecast.shower.code, fireDate: fire, title: title, body: body)
    }

    // MARK: - The system, thin

    /// Ask once, from the toggle. Returns whether reminders may be shown.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
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
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: alert.fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: alert.id, content: content, trigger: trigger))
        }
    }
}
