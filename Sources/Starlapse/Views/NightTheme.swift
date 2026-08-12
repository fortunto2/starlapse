import SwiftUI

/// Two palettes, and a real choice between them.
///
/// The red-on-black one protects dark adaptation: rod cells are nearly blind to deep red,
/// so it leaves the 20–30 minutes your eyes spent adjusting intact. That is genuinely
/// valuable — and it was also unreadable in the field at low screen brightness, which
/// makes it worthless as a default. Text you cannot read protects nothing.
///
/// So: white by default, red one tap away for when your eyes have adjusted and you want to
/// keep them that way.
enum ThemeMode: String, CaseIterable, Sendable, Identifiable {
    case bright
    case nightVision

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bright: "Bright"
        case .nightVision: "Night vision"
        }
    }
}

/// One theme's four colours, defined in one place.
struct Palette: Sendable, Hashable {
    let primary: Color
    let secondary: Color
    let dim: Color
    let accent: Color

    static let bright = Palette(
        primary: .white,
        secondary: Color(white: 0.78),
        // Labels were 0.42/0.09/0.07 here, which vanished completely outdoors.
        dim: Color(white: 0.62),
        accent: Color(red: 1.0, green: 0.78, blue: 0.25)
    )

    static let nightVision = Palette(
        primary: Color(red: 1.0, green: 0.25, blue: 0.20),
        secondary: Color(red: 0.80, green: 0.20, blue: 0.16),
        dim: Color(red: 0.62, green: 0.16, blue: 0.13),
        accent: Color(red: 1.0, green: 0.45, blue: 0.30)
    )
}

extension ThemeMode {
    var palette: Palette {
        switch self {
        case .bright: .bright
        case .nightVision: .nightVision
        }
    }
}

/// The current theme.
///
/// `@Observable`, not a static var. The first version stored the mode on a plain static and
/// the toggle appeared to work — but only because the button also wrote an unrelated
/// `@State` in the same view, which is what actually invalidated the body. A second writer
/// anywhere (a picker in the settings sheet, an automatic switch at astronomical twilight)
/// would have changed nothing on screen, and a half-applied night theme is worse than none:
/// the whole point is that no white light reaches the eye.
@MainActor
@Observable
final class NightThemeStore {
    static let shared = NightThemeStore()

    var mode: ThemeMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.storageKey) }
    }

    private static let storageKey = "themeMode"

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey)
        // Persisted, because relaunching at 2am into a white screen destroys the 20–30
        // minutes of dark adaptation this type exists to protect.
        mode = stored.flatMap(ThemeMode.init(rawValue:)) ?? .bright
    }

    func toggle() {
        mode = mode == .bright ? .nightVision : .bright
    }
}

@MainActor
enum NightTheme {
    static var mode: ThemeMode { NightThemeStore.shared.mode }
    private static var palette: Palette { mode.palette }

    static let background = Color.black

    static var primary: Color { palette.primary }
    static var secondary: Color { palette.secondary }
    static var dim: Color { palette.dim }
    static var accent: Color { palette.accent }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension View {
    /// Panels sit over a live camera feed, so they need a solid backing — text over a
    /// bright horizon is as unreadable as text that is too dark.
    func nightPanel() -> some View {
        padding(12)
            .background(NightTheme.background.opacity(0.88))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(NightTheme.dim.opacity(0.5), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// For text drawn straight onto the sky, with no panel behind it.
    func skyLegible() -> some View {
        shadow(color: .black, radius: 2, x: 0, y: 0)
            .shadow(color: .black.opacity(0.8), radius: 4, x: 0, y: 0)
    }
}

/// A label/value row, the shape most of this UI takes.
struct ReadoutRow: View {
    let label: String
    let value: String
    var highlighted = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(NightTheme.mono(12))
                .foregroundStyle(NightTheme.dim)
            Spacer(minLength: 12)
            Text(value)
                .font(NightTheme.mono(13, weight: .semibold))
                .foregroundStyle(highlighted ? NightTheme.accent : NightTheme.primary)
                .multilineTextAlignment(.trailing)
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
