import SwiftUI

// The parts of the capture screen that change many times a second, each in its own view.
//
// SwiftUI re-runs the body of whichever view read a changed property. Read in
// `CaptureView.body`, the preview frame (every camera frame) and the aim (30 Hz) rebuilt the
// panels, the chips and the buttons with them: 83% of the app's CPU while framing went to the
// view graph, measured with Time Profiler on an iPhone 14 Pro Max, 26 Nov 2026.

/// The camera, or the growing stack: the only reader of `previewFrame`.
struct LivePreview: View {

    let model: CaptureViewModel

    var body: some View {
        MetalPreviewView(frame: model.previewFrame)
            .ignoresSafeArea()
    }
}

/// The sky markers: follow the aim, and the preview only through its size.
struct LiveOverlay: View {

    let model: CaptureViewModel
    /// Where the phone pointed when the shutter went: during a capture the phone stands
    /// still, and following the aim there only redrew the same markers (about 40% of the
    /// app's CPU in a time-lapse, measured 26 Nov 2026). `??` keeps the attitude unread.
    @State private var frozen: CaptureViewModel.OverlayPointing?

    var body: some View {
        let pointing = frozen ?? model.overlayPointing
        SkyOverlayView(
            plan: model.plan,
            aim: pointing.aim,
            target: model.aimPoint?.direction,
            hasFix: model.attitude.hasFullFix,
            showsEvents: model.showsEvents,
            showsAim: model.showsAim,
            fieldOfView: Double(model.settings.lens.fieldOfView),
            imageRoll: pointing.roll,
            buffer: model.previewSize,
            fieldScale: pointing.fieldScale,
            isLocked: pointing.isLocked
        )
        .ignoresSafeArea()
        .onChange(of: model.state.isCapturing, initial: true) { _, capturing in
            frozen = capturing ? model.overlayPointing : nil
        }
    }
}

/// "12° to target" with its arrow: the one part of the target row that moves with the phone.
struct TurnInstruction: View {

    let model: CaptureViewModel

    var body: some View {
        if let guidance = model.aimGuidance {
            HStack(spacing: 8) {
                Image(systemName: guidance.isOnTarget ? "checkmark" : "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .rotationEffect(guidance.isOnTarget ? .zero : guidance.arrowAngle)
                    .foregroundStyle(NightTheme.accent)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: String(localized: "%.0f° to target"), guidance.separation))
                        .font(NightTheme.mono(11, weight: .semibold))
                        .foregroundStyle(NightTheme.accent)
                    Text(guidance.instruction)
                        .font(NightTheme.mono(9))
                        .foregroundStyle(NightTheme.dim)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(NightTheme.background.opacity(0.75), in: Capsule())
        }
    }
}

/// The Moon chip appears as the phone swings onto the Moon, so it follows the aim too.
struct MoonInFrameSlot: View {

    let model: CaptureViewModel

    var body: some View {
        if model.moonInFrame {
            MoonInFrameChip { model.enterMoonMode() }
                .padding(.top, 6)
        }
    }
}
