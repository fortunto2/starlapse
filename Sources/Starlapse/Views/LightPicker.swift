import SwiftUI

/// How long to shoot, on the main screen: Auto plus four presets.
///
/// The fine slider still lives in the settings sheet. Moving it there turns Auto off, and no
/// chip lights up for a value that is not one of them, so the row never claims a choice the
/// user did not make.
struct LightPicker: View {

    @Bindable var model: CaptureViewModel
    @AppStorage("lightPreset") private var stored = LightPreset.auto.rawValue

    private var preset: LightPreset? { LightPreset(rawValue: stored) }
    private var mode: StackMode { model.settings.stackMode }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                ForEach(LightPreset.allCases) { option in
                    chip(option)
                }
            }
            Text(caption)
                .font(NightTheme.mono(9))
                .foregroundStyle(NightTheme.dim)
        }
        .onAppear(perform: apply)
        .onChange(of: model.settings.stackMode) { apply() }
        .onChange(of: model.settings.totalLightSeconds) { _, seconds in
            // Moved by the slider in the sheet: whatever the row said no longer holds.
            if let preset, preset.seconds(for: mode) != seconds { stored = "" }
        }
    }

    private var caption: String {
        let total = LightPreset.spoken(model.settings.totalLightSeconds)
        return preset == .auto
            ? String(format: String(localized: "Auto: %@ for %@"), total, mode.title.lowercased())
            : String(format: String(localized: "Collecting light for %@"), total)
    }

    private func apply() {
        guard let preset else { return }
        model.settings.totalLightSeconds = preset.seconds(for: mode)
    }

    private func chip(_ option: LightPreset) -> some View {
        let isOn = preset == option
        return Button {
            stored = option.rawValue
            apply()
        } label: {
            Text(option.label)
                .font(NightTheme.mono(11, weight: isOn ? .bold : .regular))
                .foregroundStyle(isOn ? Color.black : NightTheme.dim)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(isOn ? NightTheme.primary : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isOn ? Color.clear : NightTheme.dim.opacity(0.5), lineWidth: 1)
                )
        }
        .accessibilityIdentifier("light-\(option.rawValue)")
    }
}
