import Foundation

/// How often to spend the GPU on a picture nobody needs at the camera's rate.
///
/// Every frame redrew the whole stack for the screen: a full-resolution resolve, waited on,
/// around 500 MB of GPU traffic (measured on the detector, which was thinned first). At 30
/// frames a second in the hand, and for hours in a night time-lapse, that is the heat.
/// The stack itself still takes every frame; only the picture of it is paced.
public struct RenderPace: Sendable, Equatable {

    /// Live view while composing: smooth enough to aim by.
    public static let framing = 1.0 / 15
    /// The growing stack during a session: watching it form needs no more.
    public static let preview = 0.5
    /// Both, when the phone reports it is hot.
    public static let hotFactor = 4.0

    public var gap: Double
    private var last = -Double.infinity

    public init(gap: Double) {
        self.gap = gap
    }

    /// True, and remembered, when at least `gap` seconds passed since the last admitted time.
    /// A clock that went backwards (a new session's timestamps) admits at once.
    public mutating func admit(_ time: Double) -> Bool {
        guard time - last >= gap || time < last else { return false }
        last = time
        return true
    }
}
