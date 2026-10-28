import SwiftUI

/// What to build, and the Moon's end of the shutter slider. Its own file to keep the sheet
/// inside the length limit.
extension ManualControlsView {

    // MARK: - Stack mode

    var stackSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("WHAT TO BUILD")

            // The Moon is entered from the main screen, where its meter and lens come with
            // it; picking a night mode here leaves it the same way the main screen does.
            Picker("Mode", selection: Binding(
                get: { model.settings.stackMode },
                set: { mode in
                    model.leaveMoonMode()
                    model.settings.stackMode = mode
                }
            )) {
                ForEach(StackMode.allCases.filter { $0 != .moon }) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(model.settings.stackMode.explanation)
                .font(NightTheme.mono(10))
                .foregroundStyle(NightTheme.dim)

            Toggle(isOn: Binding(
                get: { model.mode.isTimelapse },
                set: {
                    if $0 { model.leaveMoonMode() }
                    model.mode = $0 ? .timelapse(model.timelapse) : .still
                }
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

    /// The Moon's shutter runs far below the night range; the slider follows it there.
    var shortestShutterOnSlider: Double {
        model.isMoonMode ? model.capabilities.minFrameExposure : 0.1
    }
}
