import SkyKit
import SwiftUI

struct CaptureView: View {

    @State private var model = CaptureViewModel()
    @State private var showsControls = false
    /// The sky overlay is genuinely useful and genuinely in the way — it has to come off
    /// in one tap, without hunting through a settings sheet in the dark.
    @State private var showsOverlay = true
    @State private var themeMode = ThemeMode.bright

    var body: some View {
        ZStack {
            NightTheme.background.ignoresSafeArea()

            MetalPreviewView(texture: model.previewTexture)
                .ignoresSafeArea()

            if showsOverlay {
                SkyOverlayView(
                    plan: model.plan,
                    aim: model.attitude.aim,
                    guidance: model.aimGuidance,
                    hasFix: model.attitude.hasFullFix,
                    fieldOfView: Double(model.settings.lens.fieldOfView)
                )
                .ignoresSafeArea()
            }

            VStack {
                topBar
                Spacer()
                if model.state.isCapturing {
                    progressPanel
                } else if showsOverlay {
                    conditionsPanel
                }
                controlBar
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            if case .failed(let message) = model.state {
                failureOverlay(message)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $showsControls) {
            ManualControlsView(model: model)
                .presentationDetents([.medium, .large])
                .presentationBackground(NightTheme.background)
        }
        .task {
            model.startSkyUpdates()
            await model.prepare()
        }
        .onDisappear { model.stopSkyUpdates() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            iconButton(showsOverlay ? "sparkles" : "sparkles.slash", active: showsOverlay) {
                showsOverlay.toggle()
            }

            iconButton("moon.fill", active: themeMode == .nightVision) {
                themeMode = themeMode == .bright ? .nightVision : .bright
                NightTheme.mode = themeMode
            }

            Spacer()

            if let plan = model.plan, showsOverlay {
                // The focus hint: autofocus is useless against a dark sky, so you set
                // infinity by hand and confirm it on the brightest point source available.
                if let focus = plan.focusTarget(), focus.direction.isAboveHorizon {
                    Text("FOCUS ON \(focus.name.uppercased())")
                        .font(NightTheme.mono(10, weight: .semibold))
                        .foregroundStyle(NightTheme.accent)
                        .skyLegible()
                }
            }
        }
        .padding(.top, 4)
    }

    private func iconButton(
        _ systemName: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(active ? NightTheme.primary : NightTheme.dim)
                .frame(width: 38, height: 38)
                .background(NightTheme.background.opacity(0.7))
                .clipShape(Circle())
                .overlay(Circle().stroke(NightTheme.dim.opacity(0.5), lineWidth: 1))
        }
    }

    // MARK: - Panels

    private var conditionsPanel: some View {
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

                let planets = plan.visiblePlanets()
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

            if let message = model.lastSavedMessage {
                Text(message)
                    .font(NightTheme.mono(10, weight: .semibold))
                    .foregroundStyle(NightTheme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightPanel()
    }

    private var progressPanel: some View {
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

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: 14) {
            Button {
                showsControls = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 20))
                    .foregroundStyle(NightTheme.primary)
                    .frame(width: 52, height: 52)
                    .overlay(Circle().stroke(NightTheme.dim, lineWidth: 1))
            }
            .disabled(model.state.isCapturing)

            Spacer()

            shutterButton

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(model.settings.stackMode.title.uppercased())
                    .font(NightTheme.mono(9, weight: .bold))
                Text(model.mode.isTimelapse ? model.timelapse.summary : model.exposureExplanation)
                    .font(NightTheme.mono(8))
                    .multilineTextAlignment(.trailing)
            }
            .foregroundStyle(NightTheme.dim)
            .frame(width: 110)
        }
        .padding(.top, 10)
    }

    private var shutterButton: some View {
        Button {
            Task {
                if model.state.isCapturing {
                    await model.cancel()
                } else {
                    await model.start()
                }
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(NightTheme.primary, lineWidth: 3)
                    .frame(width: 74, height: 74)

                if model.state.isCapturing {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(NightTheme.primary)
                        .frame(width: 28, height: 28)
                } else {
                    Circle()
                        .fill(NightTheme.secondary)
                        .frame(width: 60, height: 60)
                }
            }
        }
        .disabled(model.state == .preparing || model.state == .finishing)
    }

    private func failureOverlay(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text("CAMERA UNAVAILABLE")
                .font(NightTheme.mono(13, weight: .bold))
                .foregroundStyle(NightTheme.primary)
            Text(message)
                .font(NightTheme.mono(11))
                .foregroundStyle(NightTheme.dim)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .nightPanel()
        .padding(40)
    }
}
