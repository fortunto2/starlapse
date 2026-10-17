import Foundation
import SkyKit

/// The season's showers for this place, kept beside the plan.
///
/// Split from the main view model to keep it inside the size limit. The forecast walks
/// every night of every shower window in twenty-minute steps, so it runs off the main
/// actor and only when the day or the degree of latitude changes.
extension CaptureViewModel {

    func refreshForecast(at location: GeographicCoordinates) {
        let date = planDate
        // The local night, not the UTC day: west of Greenwich the UTC day turns over before
        // dark and would drop tonight, and tonight's reminder with it.
        let night = SkyDirector.night(containing: date, longitude: location.longitude)
        let place = "\(location.latitude.rounded())/\(location.longitude.rounded())"
        let key = "\(night.timeIntervalSinceReferenceDate)/\(place)"
        guard key != forecastKey else { return }
        forecastKey = key
        Task.detached(priority: .utility) { [weak self] in
            let forecasts = SkyDirector.forecast(at: location, from: date)
            let newMoon = SkyDirector.nextNewMoon(after: date)
            await self?.apply(forecasts: forecasts, newMoon: newMoon, key: key)
        }
    }

    func apply(forecasts: [ShowerForecast], newMoon: Date, key: String) {
        guard key == forecastKey else { return }
        self.forecasts = forecasts
        nextNewMoon = newMoon
        rescheduleAlerts()
    }

    /// Rebuild the pending shower reminders from the current forecast, or clear them when
    /// switched off. Cheap: at most eight requests, replaced by identifier.
    ///
    /// Runs on a forecast, a save, the switch, a purchase and the app coming forward (a
    /// time-zone change, permission granted in Settings). Before this session has a forecast
    /// it does nothing: no location yet is not "no good nights", and must not erase the
    /// reminders an earlier session set. Each run waits for the one before it, so a
    /// half-finished replace cannot land on top of a newer one.
    func rescheduleAlerts() {
        let enabled = ShowerAlerts.isEnabled
        guard !enabled || nextNewMoon != nil else { return }
        let now = Date()
        let alerts = enabled
            ? ShowerAlerts.schedule(
                forecasts, now: now, calendar: .current, isPro: entitlements.isPro, fired: ShowerAlerts.fired()
            )
            : []
        if enabled { ShowerAlerts.recordFired(alerts, now: now) }
        let previous = alertsTask
        alertsTask = Task {
            await previous?.value
            await ShowerAlerts.apply(alerts)
        }
    }

    /// For the "tonight" checks, which count nights in local solar time.
    var longitude: Double { attitude.location?.longitude ?? 0 }

    /// The first shower worth a night, for the one-line row above the shutter.
    var nextEvent: ShowerForecast? { forecasts.first(where: \.isWorthPlanning) }

    // MARK: - The gate the events sit behind

    /// Showers, radiants, rates: the events.
    var showsEvents: Bool { entitlements.isPro }

    /// The aim target follows the headline shower when one is active, so it is an event
    /// then; on a night with no shower it points at the Milky Way, which everyone gets.
    var showsAim: Bool {
        let eventDriven = chosenCandidate?.isEvent ?? false
        return ProAccess.showsAim(isPro: entitlements.isPro, eventActive: eventDriven)
    }

    // MARK: - Where the arrow points

    /// The plan's pick, unless the person chose otherwise and that choice is still up.
    var aimPoint: SkyDirector.AimPoint? { chosenCandidate?.aim ?? plan?.aim }

    var chosenCandidate: AimCandidate? {
        guard let plan else { return nil }
        if let aimChoice, let chosen = plan.aimCandidates.first(where: { $0.kind == aimChoice }) {
            return chosen
        }
        return plan.aimCandidates.first { $0.aim == plan.aim }
    }

    /// Point the arrow somewhere else; nil hands the choice back to the plan. A shower is
    /// an event, so for a free account it opens the Pro page instead.
    func choose(_ candidate: AimCandidate?) {
        if let candidate, candidate.isEvent, !entitlements.isPro {
            showsPaywall = true
            return
        }
        aimChoice = candidate?.kind
    }
}
