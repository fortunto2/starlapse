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
        let day = Calendar.gregorianUTC.startOfDay(for: date)
        let key = "\(day.timeIntervalSinceReferenceDate)/\(location.latitude.rounded())/\(location.longitude.rounded())"
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
    }

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
