import SkyKit
import SwiftUI

/// The readouts that sit above the shutter: what the sky is doing before a capture, and
/// what the capture is doing during one.
///
/// Split out of `CaptureView` when that file crossed the size limit — the panels are pure
/// presentation of `plan` and `progress`, with no bearing on the camera controls around them.
struct StatusPanels: View {

    let model: CaptureViewModel

    var body: some View {
        if model.state.isCapturing {
            if model.mode.isDetector {
                detectorPanel
            } else {
                stackProgressPanel
            }
        } else {
            conditionsPanel
        }
    }

    // MARK: - Panels

    var conditionsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let plan = model.plan {
                Text(plan.conditions.summary.uppercased())
                    .font(NightTheme.mono(11, weight: .bold))
                    .foregroundStyle(NightTheme.primary)

                if let shower = plan.headlineShower, shower.isWorthShooting {
                    ReadoutRow(
                        label: shower.shower.name,
                        value: String(format: "~%.0f meteors/h", shower.expectedHourlyRate),
                        highlighted: true
                    )
                }

                ReadoutRow(label: "Aim", value: "\(plan.aim.compass) · \(plan.aim.subject)")
                Text(plan.aim.reason)
                    .font(NightTheme.mono(9))
                    .foregroundStyle(NightTheme.dim)

                let planets = plan.visiblePlanets
                if !planets.isEmpty {
                    ReadoutRow(
                        label: "Planets up",
                        value: planets.map(\.name).joined(separator: " · ")
                    )
                }
            } else {
                Text(model.attitude.authorizationDenied
                     ? "LOCATION DENIED — SKY GUIDANCE OFF"
                     : "ACQUIRING LOCATION…")
                    .font(NightTheme.mono(11))
                    .foregroundStyle(NightTheme.dim)
            }

            if let focus = model.focusResult {
                Text(focus.message)
                    .font(NightTheme.mono(10, weight: .semibold))
                    .foregroundStyle(NightTheme.accent)
            }

            if let message = model.lastSavedMessage {
                Text(message)
                    .font(NightTheme.mono(10, weight: .semibold))
                    .foregroundStyle(NightTheme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightPanel()
    }

    var detectorPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(NightTheme.accent)
                    .frame(width: 8, height: 8)
                Text("WATCHING")
                    .font(NightTheme.mono(12, weight: .bold))
                    .foregroundStyle(NightTheme.primary)
                Spacer()
                Text(model.detectorSettings.summary)
                    .font(NightTheme.mono(9))
                    .foregroundStyle(NightTheme.dim)
            }

            ReadoutRow(
                label: "Clips recorded",
                value: "\(model.progress.eventsRecorded)",
                highlighted: model.progress.eventsRecorded > 0
            )
            if model.progress.eventsDetected != model.progress.eventsRecorded {
                ReadoutRow(
                    label: "Detected",
                    value: "\(model.progress.eventsDetected)"
                )
            }

            Text("KEEP THE APP OPEN — iOS STOPS THE CAMERA IN THE BACKGROUND")
                .font(NightTheme.mono(9))
                .foregroundStyle(NightTheme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightPanel()
    }

    var stackProgressPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: model.progress.fraction)
                .tint(NightTheme.secondary)

            ReadoutRow(
                label: "Frames stacked",
                value: "\(model.progress.framesStacked) / \(model.progress.framesRequested)",
                highlighted: true
            )
            ReadoutRow(
                label: "Noise reduction",
                value: String(format: "−%.1f stops", model.progress.noiseReductionStops)
            )

            if model.settings.stackMode.alignsStars {
                let tracking = String(
                    format: "%d stars · %.2f px",
                    model.progress.starsTracked, model.progress.alignmentResidual
                )
                ReadoutRow(
                    label: model.progress.isTracking ? "Tracking" : "Searching for stars",
                    value: model.progress.isTracking ? tracking : "\(model.progress.starsTracked) stars",
                    highlighted: !model.progress.isTracking
                )
            }

            if model.progress.framesRejected > 0 {
                ReadoutRow(label: "Dropped", value: "\(model.progress.framesRejected)")
            }

            if model.mode.isTimelapse {
                ReadoutRow(
                    label: "Video frames",
                    value: "\(model.progress.segmentsCompleted) / \(model.progress.segmentsRequested)"
                )
            }

            Text("KEEP THE APP OPEN — iOS STOPS THE CAMERA IN THE BACKGROUND")
                .font(NightTheme.mono(9))
                .foregroundStyle(NightTheme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightPanel()
    }

}
