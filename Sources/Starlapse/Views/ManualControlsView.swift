import SwiftUI

/// The manual controls, and the honesty about what they can and cannot do.
///
/// Every control here is locked to the value shown — nothing drifts back to automatic once
/// the session starts. The aperture row is read-only on purpose, because on iPhone it is a
/// property of the glass, not a setting, and pretending otherwise is what other camera apps
/// do when they show an f-number you cannot change.
struct ManualControlsView: View {

    @Bindable var model: CaptureViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                lensSection
                exposureSection
                stackSection
                if model.mode.isTimelapse {
                    timelapseSection
                }
                toneSection
            }
            .padding(16)
        }
        .background(NightTheme.background)
    }

    // MARK: - Lens

    private var lensSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("LENS")

            Picker("Lens", selection: $model.settings.lens) {
                ForEach(model.capabilities.lenses) { lens in
                    Text(lens.displayName).tag(lens)
                }
            }
            .pickerStyle(.segmented)

            ReadoutRow(
                label: "Aperture (fixed by hardware)",
                value: String(format: "f/%.2f", model.settings.lens.aperture)
            )
            ReadoutRow(
                label: "Field of view",
                value: String(format: "%.0f°", model.settings.lens.fieldOfView)
            )

            if let fastest = model.capabilities.fastestLens, fastest != model.settings.lens {
                let stops = model.settings.lens.stopsDarker(than: fastest)
                Text(String(
                    format: "%.1f stops darker than %@ — you cannot open this up, only pick a faster lens.",
                    stops, fastest.displayName
                ))
                .font(NightTheme.mono(10))
                .foregroundStyle(NightTheme.dim)
            }
        }
        .nightPanel()
    }

    // MARK: - Exposure

    private var exposureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("EXPOSURE — LOCKED")

            NightSlider(
                label: "ISO",
                value: Binding(
                    get: { Double(model.settings.iso) },
                    set: { model.settings.iso = Float($0) }
                ),
                range: Double(model.capabilities.isoRange.lowerBound)...Double(model.capabilities.isoRange.upperBound),
                format: { String(format: "%.0f", $0) }
            )

            NightSlider(
                label: "Frame exposure",
                value: $model.settings.frameExposure,
                range: 0.1...max(0.2, model.capabilities.maxFrameExposure),
                format: { String(format: "%.2f s", $0) }
            )

            NightSlider(
                label: "Total light",
                value: $model.settings.totalLightSeconds,
                range: CaptureSettings.minimumTotalLight...CaptureSettings.maximumTotalLight,
                format: { $0 >= 60 ? String(format: "%.0f min", $0 / 60) : String(format: "%.0f s", $0) }
            )

            VStack(alignment: .leading, spacing: 4) {
                ReadoutRow(label: "Stacking", value: model.exposureExplanation, highlighted: true)
                ReadoutRow(
                    label: "Noise reduction",
                    value: String(format: "−%.1f stops", model.settings.noiseReductionStops)
                )
                ReadoutRow(
                    label: "Star drift per frame",
                    value: String(format: "%.0f\"", model.settings.starDriftArcseconds)
                )
                Text(model.hardwareCeilingNote)
                    .font(NightTheme.mono(10))
                    .foregroundStyle(NightTheme.dim)
            }

            Divider().overlay(NightTheme.dim)

            NightSlider(
                label: "Focus (1.0 = infinity)",
                value: Binding(
                    get: { Double(model.settings.focusPosition) },
                    set: { model.settings.focusPosition = Float($0) }
                ),
                range: 0...1,
                format: { String(format: "%.3f", $0) }
            )

            NightSlider(
                label: "White balance",
                value: Binding(
                    get: { Double(model.settings.whiteBalanceKelvin) },
                    set: { model.settings.whiteBalanceKelvin = Float($0) }
                ),
                range: 2500...8000,
                format: { String(format: "%.0f K", $0) },
                step: 50
            )
        }
        .nightPanel()
    }

    // MARK: - Stack mode

    private var stackSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("WHAT TO BUILD")

            Picker("Mode", selection: $model.settings.stackMode) {
                ForEach(StackMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(model.settings.stackMode.explanation)
                .font(NightTheme.mono(10))
                .foregroundStyle(NightTheme.dim)

            Toggle(isOn: Binding(
                get: { model.mode.isTimelapse },
                set: { model.mode = $0 ? .timelapse(model.timelapse) : .still }
            )) {
                Text("Time-lapse")
                    .font(NightTheme.mono(12))
                    .foregroundStyle(NightTheme.primary)
            }
            .tint(NightTheme.secondary)

            Toggle(isOn: $model.dimsScreenDuringCapture) {
                Text("Dim screen while capturing")
                    .font(NightTheme.mono(12))
                    .foregroundStyle(NightTheme.primary)
            }
            .tint(NightTheme.secondary)
        }
        .nightPanel()
    }

    // MARK: - Time-lapse

    private var timelapseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("TIME-LAPSE")

            NightSlider(
                label: "Light per frame",
                value: Binding(
                    get: { model.timelapse.lightPerFrame },
                    set: { model.timelapse.lightPerFrame = $0; model.mode = .timelapse(model.timelapse) }
                ),
                range: 1...60,
                format: { String(format: "%.0f s", $0) },
                step: 1
            )

            NightSlider(
                label: "Interval",
                value: Binding(
                    get: { model.timelapse.interval },
                    set: { model.timelapse.interval = $0; model.mode = .timelapse(model.timelapse) }
                ),
                range: 2...300,
                format: { $0 >= 60 ? String(format: "%.1f min", $0 / 60) : String(format: "%.0f s", $0) },
                step: 1
            )

            NightSlider(
                label: "Shoot for",
                value: Binding(
                    get: { model.timelapse.totalDuration },
                    set: { model.timelapse.totalDuration = $0; model.mode = .timelapse(model.timelapse) }
                ),
                range: 300...(6 * 3600),
                format: { String(format: "%.1f h", $0 / 3600) },
                step: 300
            )

            // The reality check. Shown before the shoot, not after: "one hour of sky"
            // sounds like a long video and is in fact 2.5 seconds.
            ReadoutRow(label: "Result", value: model.timelapse.summary, highlighted: true)
            ReadoutRow(label: "Speed", value: String(format: "%.0f×", model.timelapse.speedFactor))

            if let warning = model.timelapse.warning {
                Text(warning)
                    .font(NightTheme.mono(10, weight: .semibold))
                    .foregroundStyle(NightTheme.accent)
            }
        }
        .nightPanel()
    }

    // MARK: - Tone

    private var toneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("CURVE")

            NightSlider(
                label: "Stretch (asinh)",
                value: Binding(
                    get: { Double(model.tone.stretch) },
                    set: { model.tone.stretch = Float($0) }
                ),
                range: 1...200,
                format: { String(format: "%.0f", $0) }
            )

            NightSlider(
                label: "Black point",
                value: Binding(
                    get: { Double(model.tone.blackPoint) },
                    set: { model.tone.blackPoint = Float($0) }
                ),
                range: 0...0.3,
                format: { String(format: "%.3f", $0) }
            )

            NightSlider(
                label: "Saturation",
                value: Binding(
                    get: { Double(model.tone.saturation) },
                    set: { model.tone.saturation = Float($0) }
                ),
                range: 0...2.5,
                format: { String(format: "%.2f", $0) }
            )

            Text("""
                asinh, not gamma. Nearly linear in the shadows and logarithmic higher up, \
                so faint nebulosity lifts out of the noise while bright stars keep their \
                cores and colour instead of clipping to white discs.
                """)
                .font(NightTheme.mono(10))
                .foregroundStyle(NightTheme.dim)
        }
        .nightPanel()
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(NightTheme.mono(11, weight: .bold))
            .foregroundStyle(NightTheme.secondary)
    }
}
