import Foundation

/// A night time-lapse where every output frame is itself a stack.
///
/// The arithmetic here is the part people get wrong, so the app shows it before the shoot
/// rather than after: collecting ten seconds of light once a minute for an hour yields
/// sixty frames, and sixty frames at 24 fps is two and a half seconds of video. Beautiful
/// seconds, but the tripod stands out there for an hour to get them.
struct TimelapseSettings: Sendable, Equatable {
    /// Seconds of light gathered into each output frame. This is what keeps the stars
    /// bright instead of a grainy smear.
    var lightPerFrame: Double
    /// Wall-clock seconds between the start of one frame and the next. Must be at least
    /// `lightPerFrame`; the difference is dead time that speeds the result up.
    var interval: Double
    /// How long to keep shooting, in wall-clock seconds.
    var totalDuration: Double
    var outputFrameRate: Int

    static let `default` = TimelapseSettings(
        lightPerFrame: 10,
        interval: 20,
        totalDuration: 3600,
        outputFrameRate: 24
    )

    var frameCount: Int {
        max(1, Int(totalDuration / max(interval, 1)))
    }

    /// Length of the finished clip in seconds.
    var videoDuration: Double {
        Double(frameCount) / Double(max(outputFrameRate, 1))
    }

    /// How much time is compressed — a 1440× clip turns a minute of sky into a frame.
    var speedFactor: Double {
        interval * Double(outputFrameRate)
    }

    /// Idle seconds between frames. Zero means the sensor never rests, which gives the
    /// smoothest motion but the least time compression.
    var deadTime: Double {
        max(0, interval - lightPerFrame)
    }

    /// How far a star moves between consecutive output frames, in degrees. Past roughly a
    /// degree the sky visibly jumps rather than glides, which reads as stutter.
    var skyMotionPerFrame: Double {
        interval * 15.0 / 3600.0
    }

    var isSmooth: Bool { skyMotionPerFrame < 0.5 }

    /// A plain-language summary. Shown on the setup screen, because "2.5 seconds" is
    /// something you want to learn before driving somewhere dark, not after.
    var summary: String {
        let hours = totalDuration / 3600
        let shootingTime = hours >= 1
            ? String(format: "%.1f h", hours)
            : String(format: "%.0f min", totalDuration / 60)
        return "\(frameCount) frames over \(shootingTime) → "
            + String(format: "%.1f s", videoDuration)
            + " of video at \(outputFrameRate) fps"
    }

    var warning: String? {
        if videoDuration < 2 {
            return "Under 2 seconds of video. Shorten the interval or shoot longer."
        }
        if !isSmooth {
            return String(format: "Sky moves %.1f° between frames — motion will look steppy.", skyMotionPerFrame)
        }
        if lightPerFrame > interval {
            return "Light per frame exceeds the interval — frames would overlap."
        }
        return nil
    }
}

/// What a capture session is trying to produce.
enum CaptureMode: Sendable, Equatable {
    /// One deep stack.
    case still
    /// A sequence of stacks, assembled into video.
    case timelapse(TimelapseSettings)

    var isTimelapse: Bool {
        if case .timelapse = self { return true }
        return false
    }

    var title: String {
        switch self {
        case .still: "Single exposure"
        case .timelapse: "Time-lapse"
        }
    }
}
