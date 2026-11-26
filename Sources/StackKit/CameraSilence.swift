import Foundation

/// Telling a camera that sends nothing from a dark scene.
///
/// 26 Nov 2026, two iPhones on iOS 27.2.1: the system camera went black in every app, and
/// Starlapse kept receiving frames in which every byte was 0, or 16 (video-range black). A
/// sensor cannot make that: at any real gain read noise moves the pixels. The app looked
/// broken while the fault was the phone's, and only a restart brought the camera back.
public enum CameraSilence {

    /// How many flat frames in a row before saying so: a few seconds at framing rates, long
    /// enough to step over a frame dropped during a reconfiguration.
    public static let framesBeforeWarning = 30

    /// Below this gain an 8-bit frame of a truly dark scene can quantise to one level, so a
    /// flat frame there proves nothing.
    public static let minimumISO: Float = 400

    /// Every pixel at the same level, to within float rounding.
    public static func isFlat(_ pixels: [Float]) -> Bool {
        guard let first = pixels.first else { return false }
        var low = first, high = first
        for value in pixels {
            low = min(low, value)
            high = max(high, value)
        }
        return high - low < 1e-5
    }
}
