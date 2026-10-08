import SkyKit
import SwiftUI

/// The season's meteor showers, for where the phone is.
///
/// One row per shower, two lines each, nothing to configure. The night and hour are the
/// ones that deliver from this latitude with this year's Moon, which is the question the
/// catalogue cannot answer: a peak date is the same for everyone, a good night is not.
/// Showers that will not work here are listed anyway, with the reason, because "the
/// Eta Aquariids are not for you" is worth knowing before a 2am alarm.
struct EventsView: View {

    let model: CaptureViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("EVENTS")
                        .font(NightTheme.mono(14, weight: .bold))
                        .foregroundStyle(NightTheme.primary)
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(NightTheme.mono(11, weight: .bold))
                        .tint(NightTheme.accent)
                }

                if let newMoon = model.nextNewMoon {
                    ReadoutRow(
                        label: "Darkest night",
                        value: newMoon.formatted(.dateTime.day().month(.abbreviated))
                            + " · " + String(localized: "new Moon"),
                        highlighted: true
                    )
                    .nightPanel()
                }

                Text("Meteor showers in the next 90 days, with the night and hour that work from here.")
                    .font(NightTheme.mono(10))
                    .foregroundStyle(NightTheme.dim)

                if model.forecasts.isEmpty {
                    Text("No shower has a dark night here in the next 90 days.")
                        .font(NightTheme.mono(11))
                        .foregroundStyle(NightTheme.secondary)
                        .nightPanel()
                }

                ForEach(model.forecasts) { forecast in
                    row(forecast)
                }

                Text("Rates assume a clear, dark sky at the hour shown; real counts run lower. Nights are chosen for your latitude and that night's Moon, so they can differ from the catalogue peak.")
                    // swiftlint:disable:previous line_length
                    .font(NightTheme.mono(9))
                    .foregroundStyle(NightTheme.dim)
            }
            .padding(16)
        }
        .background(NightTheme.background)
    }

    // MARK: - Rows

    private func row(_ forecast: ShowerForecast) -> some View {
        let tonight = forecast.isTonight(model.planDate)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(tonight ? String(localized: "TONIGHT") : dayText(forecast.bestNight))
                    .font(NightTheme.mono(11, weight: .bold))
                    .foregroundStyle(tonight ? NightTheme.accent : NightTheme.secondary)
                    .frame(width: 64, alignment: .leading)
                Text(forecast.shower.name.uppercased())
                    .font(NightTheme.mono(12, weight: .bold))
                    .foregroundStyle(forecast.isWorthPlanning ? NightTheme.primary : NightTheme.dim)
                Spacer(minLength: 8)
                Text(verdictText(forecast.verdict))
                    .font(NightTheme.mono(10, weight: .bold))
                    .foregroundStyle(verdictColor(forecast.verdict))
            }
            Text(details(forecast))
                .font(NightTheme.mono(9))
                .foregroundStyle(NightTheme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightPanel()
    }

    private func dayText(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated)).uppercased()
    }

    private func details(_ forecast: ShowerForecast) -> String {
        switch forecast.verdict {
        case .belowHorizon:
            return String(
                format: String(localized: "Radiant stays under %.0f° in darkness at this latitude."),
                max(0, forecast.radiantAtBest.altitude)
            )
        case .moonWashed:
            return String(
                format: String(localized: "Moon %d%% up on every dark night of the window."),
                Int(forecast.moonIlluminationAtBest * 100)
            )
        case .faint:
            return String(
                format: String(localized: "~%.1f/h at best from here. Not worth a night."),
                forecast.bestRate
            )
        case .excellent, .good, .marginal:
            var parts: [String] = []
            if !Calendar.gregorianUTC.isDate(forecast.peak, inSameDayAs: forecast.bestNight) {
                parts.append(String(format: String(localized: "peak %@"), dayText(forecast.peak).lowercased()))
            }
            parts.append(String(
                format: String(localized: "~%.0f/h at %@"),
                forecast.bestRate, forecast.bestTime.formatted(.dateTime.hour().minute())
            ))
            parts.append(String(
                format: String(localized: "radiant %@ %.0f° up"),
                compassPoint(forAzimuth: forecast.radiantAtBest.azimuth), forecast.radiantAtBest.altitude
            ))
            parts.append(String(
                format: String(localized: "Moon %d%% %@"),
                Int(forecast.moonIlluminationAtBest * 100),
                forecast.moonUpAtBest ? String(localized: "up") : String(localized: "down")
            ))
            return parts.joined(separator: " · ")
        }
    }

    private func verdictText(_ verdict: ShowerForecast.Verdict) -> String {
        switch verdict {
        case .excellent: String(localized: "EXCELLENT")
        case .good: String(localized: "GOOD")
        case .marginal: String(localized: "MARGINAL")
        case .faint: String(localized: "FAINT")
        case .moonWashed: String(localized: "MOON-WASHED")
        case .belowHorizon: String(localized: "BELOW HORIZON")
        }
    }

    private func verdictColor(_ verdict: ShowerForecast.Verdict) -> Color {
        switch verdict {
        case .excellent: NightTheme.accent
        case .good: NightTheme.primary
        case .marginal: NightTheme.secondary
        case .faint, .moonWashed, .belowHorizon: NightTheme.dim
        }
    }
}
