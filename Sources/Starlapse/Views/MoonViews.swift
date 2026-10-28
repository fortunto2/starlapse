import SwiftUI

/// In Moon mode the light presets mean nothing: the stack is counted in kept frames and the
/// shutter is set by the meter. This says what the meter is doing instead.
struct MoonCaption: View {

    let model: CaptureViewModel

    var body: some View {
        VStack(spacing: 3) {
            Text(status)
                .font(NightTheme.mono(11, weight: .semibold))
                .foregroundStyle(model.moonDisc == nil ? NightTheme.dim : NightTheme.accent)
            Text(String(
                format: String(localized: "1/%.0f s · ISO %.0f · steadiest %d frames"),
                1 / max(model.settings.frameExposure, 1e-6), model.settings.iso, CaptureSettings.moonFrames
            ))
            .font(NightTheme.mono(9))
            .foregroundStyle(NightTheme.dim)
        }
        .frame(maxWidth: .infinity)
    }

    private var status: String {
        guard let disc = model.moonDisc else { return String(localized: "Point at the Moon") }
        return disc.clippedFraction > 0.02
            ? String(localized: "Moon found, bringing the exposure down")
            : String(localized: "Moon found, exposure set from the disc")
    }
}

/// The compass says the Moon is in the frame: one tap to the mode made for it.
struct MoonInFrameChip: View {

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "moon.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Moon in frame: switch to Moon mode")
                    .font(NightTheme.mono(10, weight: .semibold))
            }
            .foregroundStyle(NightTheme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(NightTheme.background.opacity(0.75), in: Capsule())
            .overlay(Capsule().stroke(NightTheme.accent.opacity(0.6), lineWidth: 1))
        }
        .accessibilityIdentifier("moon-in-frame")
    }
}
