import Foundation

/// How long to collect light: the one number a person brings to a night shot.
///
/// The slider in the settings sheet goes from ten seconds to an hour and asks the user to
/// know what each point on it buys. Presets on the main screen answer the question people
/// actually have ("how long should I leave it?") and Auto answers it for them.
///
/// Auto is a rule, not a model. What the stack *is* decides how long is worth waiting:
///   pinpoint stars — 5 min. 300 aligned frames are already ≈ 4 stops below one frame's
///     noise, and noise falls as √N: ten minutes buys half a stop more for twice the wait.
///   star trails — 30 min. The sky turns 15° an hour, so arcs reach about 7°: long enough
///     to read as trails at a phone's field of view.
///   clean landscape — 2 min. Unaligned, so the sky smears as it goes; the ground is clean
///     well before the stars turn into dashes.
enum LightPreset: String, CaseIterable, Identifiable, Sendable {
    case auto
    case oneMinute
    case fiveMinutes
    case fifteenMinutes
    case oneHour

    var id: String { rawValue }

    static func autoSeconds(for mode: StackMode) -> Double {
        switch mode {
        case .stars: 300
        case .trails: 1800
        case .smooth: 120
        }
    }

    func seconds(for mode: StackMode) -> Double {
        switch self {
        case .auto: Self.autoSeconds(for: mode)
        case .oneMinute: 60
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        case .oneHour: 3600
        }
    }

    var label: String {
        switch self {
        case .auto: String(localized: "Auto")
        case .oneMinute: String(localized: "1 min")
        case .fiveMinutes: String(localized: "5 min")
        case .fifteenMinutes: String(localized: "15 min")
        case .oneHour: String(localized: "1 h")
        }
    }

    /// "5 min", "30 min", "1 h": how a total-light value is said on the main screen.
    static func spoken(_ seconds: Double) -> String {
        if seconds >= 3600, seconds.truncatingRemainder(dividingBy: 3600) == 0 {
            return String(format: String(localized: "%.0f h"), seconds / 3600)
        }
        if seconds >= 60 {
            return String(format: String(localized: "%.0f min"), seconds / 60)
        }
        return String(format: String(localized: "%.0f s"), seconds)
    }
}
