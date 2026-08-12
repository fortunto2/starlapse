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

    /// What the plan is for.
    ///
    /// Stated outright rather than inferred from the other fields. It was inferred once —
    /// `isFraming` meant "no segment count" — and then watching arrived, which also has no
    /// segment count, so the stop button decided a running detector was the viewfinder and
    /// did nothing. Two plans that differ in purpose must differ in a field that says so.
    enum Kind: Sendable, Equatable {
        /// Live view for composing. Runs until told otherwise, keeps nothing.
        case framing
        /// Building a picture: a stack, or a time-lapse of stacks.
        case capturing
        /// Watching for transients and filming them.
        case watching
    }

    var kind: Kind
    /// Frames accumulated into one output image.
    var framesPerSegment: Int
    /// Register each frame on the stars before accumulating it.
    var aligns: Bool
    /// How many segments to produce. `nil` runs until stopped — that is framing.
    var segments: Int?
    var stackMode: StackMode
    var tone: FrameAccumulator.ToneSettings
    /// Watch for transients and save a clip around each one, instead of building a picture.
    var detector: DetectorSettings?

    /// Live view for composing the shot: every frame replaces the last, nothing is kept.
    static let framing = SegmentPlan(
        kind: .framing,
        framesPerSegment: 1,
        aligns: false,
        segments: nil,
        stackMode: .smooth,
        tone: .neutral,
        detector: nil
    )

    /// Sit and watch. Like framing — every frame stands alone — but each one is compared
    /// against the last, and anything that appears gets filmed.
    static func watching(_ settings: DetectorSettings) -> Self {
        SegmentPlan(
            kind: .watching,
            framesPerSegment: 1,
            aligns: false,
            segments: nil,
            stackMode: .smooth,
            tone: .neutral,
            detector: settings
        )
    }

    var isWatching: Bool { kind == .watching }
    var isFraming: Bool { kind == .framing }
    /// Can be stopped by the user — anything that is not the viewfinder.
    var isStoppable: Bool { kind != .framing }

    /// Total frames this plan will consume, or nil if it runs indefinitely.
    var totalFrames: Int? {
        segments.map { $0 * framesPerSegment }
    }

    static func still(
        _ settings: CaptureSettings,
        tone: FrameAccumulator.ToneSettings
    ) -> Self {
        SegmentPlan(
            kind: .capturing,
            framesPerSegment: settings.frameCount,
            aligns: settings.stackMode.alignsStars,
            segments: 1,
            stackMode: settings.stackMode,
            tone: tone,
            detector: nil
        )
    }

    static func timelapse(
        _ settings: CaptureSettings,
        timelapse: TimelapseSettings,
        tone: FrameAccumulator.ToneSettings
    ) -> Self {
        SegmentPlan(
            kind: .capturing,
            framesPerSegment: max(1, Int(timelapse.lightPerFrame / settings.frameExposure)),
            aligns: settings.stackMode.alignsStars,
            segments: timelapse.frameCount,
            stackMode: settings.stackMode,
            tone: tone,
            detector: nil
        )
    }
}
