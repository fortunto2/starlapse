import SkyKit
import SwiftUI

struct CaptureView: View {

    @State private var model = CaptureViewModel()
    @State private var showsControls = false
    /// The sky overlay is genuinely useful and genuinely in the way — it has to come off
    /// in one tap, without hunting through a settings sheet in the dark.
    @State private var showsOverlay = true
    /// Read, not mirrored: the store owns the mode, so any writer invalidates the view.
    @State private var theme = NightThemeStore.shared

    var body: some View {
        ZStack {
            NightTheme.background.ignoresSafeArea()

            MetalPreviewView(frame: model.previewFrame)
                .ignoresSafeArea()

            if showsOverlay && !model.state.isReviewing {
                SkyOverlayView(
                    plan: model.plan,
                    aim: model.attitude.aim,
                    guidance: model.aimGuidance,
                    hasFix: model.attitude.hasFullFix,
                    fieldOfView: Double(model.settings.lens.fieldOfView)
                )
                .ignoresSafeArea()
            }

            if model.isFocusing {
                focusOverlay
            }

            if model.state.isReviewing {
                // The result fills the screen; the review panel owns the bottom half.
                VStack {
                    Spacer()
                    ReviewView(model: model)
                        .frame(maxHeight: model.reviewVideoURL == nil ? 420 : .infinity)
                }
                .transition(.move(edge: .bottom))
            } else {
                VStack {
                    topBar
                    Spacer()
                    if model.state.isCapturing || showsOverlay {
                        StatusPanels(model: model)
                    }
                    if !model.state.isCapturing {
                        modeSwitcher
                    }
                    controlBar
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }

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
            #if DEBUG
            await applyScreenshotHooks()
            #endif
        }
        .onDisappear { model.stopSkyUpdates() }
    }

    #if DEBUG
    /// Drive the app to a given screen for App Store screenshots. The Simulator cannot be
    /// tapped from the command line, so each shot is reached by launch environment instead.
    private func applyScreenshotHooks() async {
        let environment = ProcessInfo.processInfo.environment
        guard environment["UITEST_SKY"] == "1" else { return }

        if environment["UITEST_MODE"] == "detector" {
            model.mode = .detector(model.detectorSettings)
        }
        if environment["UITEST_PANEL"] == "controls" {
            showsControls = true
        }
        if environment["UITEST_CAPTURE"] == "1" {
            await model.start()
        }
    }
    #endif

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            iconButton(showsOverlay ? "sparkles" : "sparkles.slash", active: showsOverlay) {
                showsOverlay.toggle()
            }

            iconButton("moon.fill", active: theme.mode == .nightVision) {
                theme.toggle()
            }

            // Focus on starlight. Autofocus cannot see a night sky, and the infinity mark is
            // not exactly infinity on any given lens.
            iconButton("scope", active: model.isFocusing) {
                if model.isFocusing {
                    model.cancelAutofocus()
                } else {
                    Task { await model.autofocus() }
                }
            }
            .disabled(model.state.isCapturing)

            Spacer()

            if let plan = model.plan, showsOverlay {
                // The focus hint: autofocus is useless against a dark sky, so you set
                // infinity by hand and confirm it on the brightest point source available.
                if let focus = plan.focusTarget {
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

    private var focusOverlay: some View {
        VStack(spacing: 10) {
            Text("FOCUSING ON STARS")
                .font(NightTheme.mono(13, weight: .bold))
                .foregroundStyle(NightTheme.accent)
            ProgressView(value: model.focusProgress)
                .tint(NightTheme.accent)
                .frame(width: 180)
            Text("Stepping the lens and measuring star size.\nHold still — the tripod must not move.")
                .font(NightTheme.mono(10))
                .foregroundStyle(NightTheme.dim)
                .multilineTextAlignment(.center)
            Button("Cancel") { model.cancelAutofocus() }
                .font(NightTheme.mono(11, weight: .semibold))
                .foregroundStyle(NightTheme.dim)
        }
        .padding(20)
        .nightPanel()
    }

    // MARK: - Mode

    private var modeSwitcher: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                modeButton("Exposure", isOn: !model.mode.isTimelapse && !model.mode.isDetector) {
                    model.mode = .still
                }
                modeButton("Time-lapse", isOn: model.mode.isTimelapse) {
                    model.mode = .timelapse(model.timelapse)
                }
                modeButton("Detector", isOn: model.mode.isDetector) {
                    model.mode = .detector(model.detectorSettings)
                }
            }
            Text(model.mode.explanation)
                .font(NightTheme.mono(9))
                .foregroundStyle(NightTheme.dim)
        }
        .padding(.top, 8)
    }

    private func modeButton(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(NightTheme.mono(11, weight: isOn ? .bold : .regular))
                .foregroundStyle(isOn ? Color.black : NightTheme.dim)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(isOn ? NightTheme.primary : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isOn ? Color.clear : NightTheme.dim.opacity(0.5), lineWidth: 1)
                )
        }
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

            VStack(alignment: .trailing, spacing: 6) {
                Button {
                    model.shutterDelay = model.shutterDelay.next
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: model.shutterDelay.isOn
                              ? "timer" : "timer.slash")
                            .font(.system(size: 13, weight: .medium))
                        Text(model.shutterDelay.label)
                            .font(NightTheme.mono(11, weight: .semibold))
                    }
                    .foregroundStyle(model.shutterDelay.isOn ? NightTheme.accent : NightTheme.dim)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .overlay(
                        Capsule().stroke(
                            model.shutterDelay.isOn ? NightTheme.accent.opacity(0.6)
                                                    : NightTheme.dim.opacity(0.5),
                            lineWidth: 1
                        )
                    )
                }
                .disabled(model.state.isCapturing)

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
            if model.countdown > 0 {
                model.cancelCountdown()
            } else {
                Task { await model.triggerShutter() }
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(NightTheme.primary, lineWidth: 3)
                    .frame(width: 74, height: 74)

                if model.countdown > 0 {
                    // The count itself is the button — tapping again cancels.
                    Text("\(model.countdown)")
                        .font(NightTheme.mono(30, weight: .bold))
                        .foregroundStyle(NightTheme.accent)
                        .monospacedDigit()
                } else if model.state.isCapturing {
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
        .disabled(model.state == .preparing)
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
