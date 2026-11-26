import Foundation
import SkyKit

/// Rise, set and phase lines for the overlay and the conditions panel: the clock time to
/// plan by, and how far off it is, which is what "is it coming soon?" actually asks.
enum SkyEventText {

    /// Within this many degrees of the horizon a body's setting time is worth a label.
    static let nearHorizon = 10.0

    /// "↑ 21:40 · in 2 hr." for a body below the horizon, "↓ …" for one about to set.
    static func horizon(
        _ crossings: SkyEvents.Crossings, altitude: Double, now: Date, always: Bool = false
    ) -> String? {
        if altitude < 0, let rise = crossings.rise {
            return line("↑", rise, now: now)
        }
        if altitude >= 0, always || altitude < nearHorizon, let set = crossings.set {
            return line("↓", set, now: now)
        }
        return nil
    }

    static func line(_ arrow: String, _ date: Date, now: Date) -> String {
        "\(arrow) \(date.formatted(date: .omitted, time: .shortened)) · \(relative(date, now: now))"
    }

    /// The nearer of the next full and new Moon.
    static func phase(_ phases: SkyEvents.MoonPhases, now: Date) -> String {
        phases.nextFull < phases.nextNew
            ? String(format: String(localized: "FULL %@"), relative(phases.nextFull, now: now))
            : String(format: String(localized: "NEW %@"), relative(phases.nextNew, now: now))
    }

    /// One line for the conditions panel: Sun, Moon and the next phase.
    static func summary(_ plan: SkyDirector.Plan) -> String {
        var parts: [String] = []
        if let sun = horizon(plan.sun, altitude: plan.sunPosition.altitude, now: plan.date, always: true) {
            parts.append(String(format: String(localized: "SUN %@"), sun))
        }
        let moonAltitude = plan.conditions.moonPosition.altitude
        if let moon = horizon(plan.moon, altitude: moonAltitude, now: plan.date, always: true) {
            parts.append(String(format: String(localized: "MOON %@"), moon))
        }
        parts.append(phase(plan.moonPhases, now: plan.date))
        return parts.joined(separator: "  ·  ")
    }

    static func relative(_ date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

import SwiftUI

/// The Sun or the Moon on the overlay: a symbol, a name, and when it next crosses the horizon.
struct BodyMarker: View {
    let title: String
    let lines: [String]
    let symbol: String

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(NightTheme.accent)
            Text(title)
                .font(NightTheme.mono(9, weight: .bold))
                .foregroundStyle(NightTheme.accent)
                .skyLegible()
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(NightTheme.mono(8, weight: .semibold))
                    .foregroundStyle(NightTheme.accent)
                    .skyLegible()
            }
        }
    }
}
