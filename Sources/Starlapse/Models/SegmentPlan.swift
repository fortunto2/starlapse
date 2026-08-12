import Foundation

/// How to turn a stream of sensor frames into output images.
///
/// One shape covers everything the engine does, because everything it does is the same
/// loop: gather N frames, resolve them into a picture, repeat. A still is that loop with
/// one segment; a time-lapse is the same loop with sixty; and framing the shot is the
/// degenerate case — one frame per segment, forever.
///
/// Framing used to be a separate branch inside `consume()`, and it had already drifted from
/// the path it duplicated (hardcoding a stack mode, skipping progress reporting). Modelling
/// it as data instead of a branch means it cannot drift again.
struct SegmentPlan: Sendable, Equatable {
    /// Frames accumulated into one output image.
    var framesPerSegment: Int
    /// Register each frame on the stars before accumulating it.
    var aligns: Bool
    /// How many segments to produce. `nil` runs until stopped — that is framing.
    var segments: Int?
    var stackMode: StackMode
    var tone: FrameAccumulator.ToneSettings

    /// Live view for composing the shot: every frame replaces the last, nothing is kept.
    static let framing = SegmentPlan(
        framesPerSegment: 1,
        aligns: false,
        segments: nil,
        stackMode: .smooth,
        tone: .neutral
    )

    var isFraming: Bool { segments == nil }

    /// Total frames this plan will consume, or nil if it runs indefinitely.
    var totalFrames: Int? {
        segments.map { $0 * framesPerSegment }
    }

    static func still(
        _ settings: CaptureSettings,
        tone: FrameAccumulator.ToneSettings
    ) -> Self {
        SegmentPlan(
            framesPerSegment: settings.frameCount,
            aligns: settings.stackMode.alignsStars,
            segments: 1,
            stackMode: settings.stackMode,
            tone: tone
        )
    }

    static func timelapse(
        _ settings: CaptureSettings,
        timelapse: TimelapseSettings,
        tone: FrameAccumulator.ToneSettings
    ) -> Self {
        SegmentPlan(
            framesPerSegment: max(1, Int(timelapse.lightPerFrame / settings.frameExposure)),
            aligns: settings.stackMode.alignsStars,
            segments: timelapse.frameCount,
            stackMode: settings.stackMode,
            tone: tone
        )
    }
}
