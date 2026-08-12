import SwiftUI

/// Red on black, everywhere.
///
/// Not a style choice. Rod cells in the eye are nearly blind to deep red, so a red-only
/// interface leaves dark adaptation intact — which takes 20–30 minutes to build and about
/// two seconds of white screen to destroy. Every other astronomy tool does this, and anyone
/// who has ruined their night vision checking a phone understands why immediately.
enum NightTheme {
    static let background = Color.black
    static let primary = Color(red: 1.0, green: 0.22, blue: 0.18)
    static let secondary = Color(red: 0.70, green: 0.15, blue: 0.12)
    static let dim = Color(red: 0.42, green: 0.09, blue: 0.07)
    static let accent = Color(red: 1.0, green: 0.45, blue: 0.30)

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension View {
    func nightPanel() -> some View {
        padding(12)
            .background(NightTheme.background.opacity(0.75))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(NightTheme.dim, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// A label/value row, the shape most of this UI takes.
struct ReadoutRow: View {
    let label: String
    let value: String
    var highlighted = false

    var body: some View {
        HStack {
            Text(label)
                .font(NightTheme.mono(12))
                .foregroundStyle(NightTheme.dim)
            Spacer(minLength: 12)
            Text(value)
                .font(NightTheme.mono(13, weight: .semibold))
                .foregroundStyle(highlighted ? NightTheme.accent : NightTheme.primary)
        }
    }
}

/// A slider that shows its value and never animates — motion draws the eye at night.
struct NightSlider: View {
    let label: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let format: (Double) -> String
    var step: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(NightTheme.mono(11))
                    .foregroundStyle(NightTheme.dim)
                Spacer()
                Text(format(value.wrappedValue))
                    .font(NightTheme.mono(13, weight: .semibold))
                    .foregroundStyle(NightTheme.primary)
            }
            if let step {
                Slider(value: value, in: range, step: step)
                    .tint(NightTheme.secondary)
            } else {
                Slider(value: value, in: range)
                    .tint(NightTheme.secondary)
            }
        }
    }
}
