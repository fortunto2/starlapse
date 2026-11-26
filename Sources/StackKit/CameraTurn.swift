import Foundation
import simd

/// How far the phone turned about the camera's axis, as the gyroscope saw it, and how far a
/// solved frame may therefore turn.
///
/// 26 Nov 2026, a lit bathroom, the hand moving a little: a frame landed on the stack turned
/// 20–30°. Sixty "stars" on the edges of a washing machine matched as well rotated as not,
/// with a 1.95 px residual. The scene cannot settle the rotation; the gyroscope can, and
/// only the sky's own slow turn is added on top of it.
public enum CameraTurn {

    /// What the fused attitude and the image disagree by, plus a little hand left over.
    public static let slack = 0.75 * Double.pi / 180
    /// Field rotation for a fixed camera, generously: twice the sidereal 15° an hour.
    public static let skyRate = 30.0 * Double.pi / 180 / 3600
    /// Without readings, a hand cannot roll more than this in a session.
    public static let blindLimit = 3.0 * Double.pi / 180

    /// The turn about the device's z axis (the camera's axis) from `start` to `end`, in
    /// radians, unsigned: the twist part of the relative rotation.
    public static func twist(from start: simd_quatd, to end: simd_quatd) -> Double {
        let relative = start.inverse * end
        var angle = 2 * atan2(relative.imag.z, relative.real)
        if angle > .pi { angle -= 2 * .pi }
        if angle < -.pi { angle += 2 * .pi }
        return abs(angle)
    }

    /// The largest rotation a frame solved `elapsed` seconds after the reference may carry.
    public static func allowance(gyroTwist: Double?, elapsed: Double) -> Double {
        (gyroTwist.map { $0 + slack } ?? blindLimit) + skyRate * max(0, elapsed)
    }
}
