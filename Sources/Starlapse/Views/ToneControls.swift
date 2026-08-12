import SwiftUI

/// The develop curve, wherever it is edited.
///
/// Used before a capture (setting what the session will render with) and after one
/// (re-developing the finished stack). Those were two hand-written copies of the same four
/// sliders, and they had already drifted: exposure existed only in the review copy, so a
/// control the shader supports was unreachable before a shot and available after it, for
/// no reason anyone chose.
struct ToneControls: View {

    @Binding var tone: FrameAccumulator.ToneSettings
    /// Called after every change — review re-renders live, setup does not need to.
    var onChange: (() -> Void)?

    /// One row per adjustable field, so adding a curve parameter is one line rather than a
    /// twelve-line block copied twice.
    private struct Control {
        let label: String
        let path: WritableKeyPath<FrameAccumulator.ToneSettings, Float>
        let range: ClosedRange<Double>
        let format: String
    }

    private static let controls: [Control] = [
        Control(label: "Stretch (asinh)", path: \.stretch, range: 1...200, format: "%.0f"),
        Control(label: "Black point", path: \.blackPoint, range: 0...0.3, format: "%.3f"),
        Control(label: "Exposure", path: \.exposure, range: 0.1...8, format: "%.2f×"),
        Control(label: "Saturation", path: \.saturation, range: 0...2.5, format: "%.2f"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Self.controls, id: \.label) { control in
                NightSlider(
                    label: control.label,
                    value: Binding(
                        get: { Double(tone[keyPath: control.path]) },
                        set: {
                            tone[keyPath: control.path] = Float($0)
                            onChange?()
                        }
                    ),
                    range: control.range,
                    format: { String(format: control.format, $0) }
                )
            }
        }
    }
}
