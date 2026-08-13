import Foundation

/// Seconds between tapping the shutter and the first frame.
///
/// Not a convenience. A finger on the screen rocks the phone on its tripod, and the first
/// frames of a stack are the ones that set the alignment reference — start shaking and
/// every later frame is registered against a smeared one.
enum ShutterDelay: Int, CaseIterable, Sendable {
    case off = 0
    case short = 3
    case long = 10

    /// Cycle through on each tap — one control, no menu to open in the dark.
    var next: ShutterDelay {
        switch self {
        case .off: .short
        case .short: .long
        case .long: .off
        }
    }

    var label: String {
        self == .off ? "OFF" : "\(rawValue)s"
    }

    var isOn: Bool { self != .off }
}
