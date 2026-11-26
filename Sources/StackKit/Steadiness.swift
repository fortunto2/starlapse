import Foundation

/// One gyroscope reading: when, and how fast the phone was turning (rad/s, magnitude).
public struct MotionSample: Sendable, Equatable {
    public let time: Double
    public let rate: Double

    public init(time: Double, rate: Double) {
        self.time = time
        self.rate = rate
    }
}

/// Was the phone still while a frame was being exposed?
///
/// Stacking averages noise away but cannot undo blur inside a frame: a one-second frame
/// shot from a hand is a smear, and 28% of saved stacks in the first month held three
/// frames or fewer, most of them hand-held. The gyroscope already runs for the sky
/// overlay, so the answer costs nothing.
///
/// Thresholds are in rad/s of the bias-corrected rotation rate. A phone on a tripod reads
/// well under 0.001 (gyro noise); a phone held as still as a person can manages 0.01–0.03.
public enum Steadiness {

    /// Turning the image by more than this during one exposure smears a star across
    /// roughly ten pixels on the main lens (≈3.2e-4 rad per pixel at 4032 px).
    public static let blurBudget = 0.003

    /// The floor under `blurBudget / exposure`: below it nothing is rejected, however long
    /// the frame. Keeps gyro noise and a breath of wind from emptying a tripod session.
    public static let minimumRejectRate = 0.006

    /// Mean rate over the last second below this, and the phone counts as set down.
    public static let steadyRate = 0.006

    /// Above this the phone is in someone's hand, not braced on anything.
    public static let handheldRate = 0.03

    /// Mean turning rate over a time window, or nil when no sample falls inside it (no
    /// gyroscope, the Simulator, a clock that does not match): nil never rejects a frame.
    public static func meanRate(_ samples: [MotionSample], from start: Double, to end: Double) -> Double? {
        let inside = samples.filter { $0.time >= start && $0.time <= end }
        guard !inside.isEmpty else { return nil }
        return inside.reduce(0) { $0 + $1.rate } / Double(inside.count)
    }

    /// The rate above which a frame of this exposure is too blurred to stack.
    public static func rejectRate(exposure: Double) -> Double {
        max(minimumRejectRate, blurBudget / max(exposure, 1e-6))
    }

    /// The longest frame this hand can hold sharp: the blur budget at the measured rate, with
    /// 1.5× headroom so the frame gate below keeps what this shutter shoots. A steady phone
    /// keeps `longest`; nothing goes under `shortest`, where read noise wins over blur.
    public static func handheldExposure(rate: Double?, longest: Double, shortest: Double = 1.0 / 30) -> Double {
        guard let rate, rate >= steadyRate else { return longest }
        return min(longest, max(min(shortest, longest), blurBudget / (rate * 1.5)))
    }

    /// The gain that keeps a frame as bright at `exposure` as it was at `longest`, up to the
    /// sensor's ceiling. Past it the frame is simply darker: the stack makes up the noise.
    public static func compensatedISO(
        _ iso: Float, from longest: Double, to exposure: Double, ceiling: Float
    ) -> Float {
        guard exposure > 0, exposure < longest else { return iso }
        return min(ceiling, iso * Float(longest / exposure))
    }

    /// True when the frame should be dropped for motion. The window is widened by one
    /// exposure on each side because a frame's timestamp is not exactly its start.
    public static func moved(_ samples: [MotionSample], frameTime: Double, exposure: Double) -> Bool {
        guard let rate = meanRate(samples, from: frameTime - exposure, to: frameTime + exposure) else {
            return false
        }
        return rate > rejectRate(exposure: exposure)
    }
}
