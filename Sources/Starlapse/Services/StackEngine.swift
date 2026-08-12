import CoreVideo
import Foundation
import Metal
import os
import simd
import StackKit

/// Progress of a running capture, published to the UI.
struct StackProgress: Sendable, Equatable {
    var framesStacked: Int = 0
    var framesRequested: Int = 0
    var framesRejected: Int = 0
    var starsTracked: Int = 0
    var alignmentResidual: Double = 0
    /// Output frames written, in time-lapse mode.
    var segmentsCompleted: Int = 0
    var segmentsRequested: Int = 0

    var fraction: Double {
        guard framesRequested > 0 else { return 0 }
        return min(1, Double(framesStacked) / Double(framesRequested))
    }

    /// Noise improvement so far, in stops — the number that makes stacking feel worth it.
    var noiseReductionStops: Double {
        guard framesStacked > 1 else { return 0 }
        return log2(Double(framesStacked).squareRoot())
    }

    var isTracking: Bool { starsTracked >= 6 }
}

/// Runs one `SegmentPlan`: gather frames, resolve them into a picture, repeat.
///
/// Framing, a single deep exposure and a time-lapse are the same loop with different
/// numbers — see `SegmentPlan`. Everything here executes on the shared `CaptureQueue`;
/// public methods that can be called from elsewhere hop onto it themselves.
final class StackEngine: @unchecked Sendable {

    private let accumulator: FrameAccumulator
    private let queue: CaptureQueue
    private let detector = StarDetector()
    private let aligner = StarAligner()
    private let logger = Logger(subsystem: "co.superduperai.starlapse", category: "stack")

    private var plan: SegmentPlan?
    /// Frames gathered into the segment currently being built.
    private var framesInSegment = 0

    /// Stars from the frame everything else is registered onto.
    private var referenceStars: [StarPoint] = []
    /// Stars from the previous frame — the aligner steps frame to frame, because between
    /// two consecutive frames the sky has barely moved and matching is trivial.
    private var previousStars: [StarPoint] = []
    /// Transform from the current frame back to the reference frame.
    private var accumulatedTransform = SimilarityTransform.identity

    private var progress = StackProgress()

    /// Called on the capture queue after every frame.
    var onProgress: (@Sendable (StackProgress) -> Void)?
    /// Called on the capture queue when a recorded segment is resolved.
    ///
    /// The handler must consume the texture **synchronously** — it belongs to the display
    /// pool and is handed back as soon as this returns.
    var onSegmentReady: (@Sendable (MTLTexture, Int) -> Void)?
    /// A newly rendered frame is ready to display. Pushed, never pulled: the main actor
    /// asking the engine for a render is what caused the first end-of-session crash.
    var onPreviewReady: (@Sendable (PreviewFrame) -> Void)?
    /// Session complete, with the final image as plain bytes — safe to send anywhere.
    var onFinished: (@Sendable (RenderedImage?) -> Void)?

    init(accumulator: FrameAccumulator, queue: CaptureQueue) {
        self.accumulator = accumulator
        self.queue = queue
    }

    // MARK: - Session control

    /// Switch to a plan. Safe to call from anywhere — the work hops to the pipeline.
    func begin(_ plan: SegmentPlan) {
        queue.run { [weak self] in
            self?.beginOnQueue(plan)
        }
    }

    private func beginOnQueue(_ plan: SegmentPlan) {
        self.plan = plan
        framesInSegment = 0
        resetAlignment()
        progress = StackProgress(
            framesRequested: plan.totalFrames ?? 0,
            segmentsRequested: plan.segments ?? 0
        )

        if !plan.isFraming {
            logger.info("""
                Session start: \(plan.totalFrames ?? 0) frames, \
                \(plan.framesPerSegment) per segment, \(plan.segments ?? 0) segments
                """)
        }
    }

    /// Stop a recording and return to framing.
    ///
    /// Hops to the pipeline rather than resolving inline. Calling `finish()` straight from
    /// a button tap ran Metal work on the main thread while the capture queue was mid-frame
    /// — the app crashed on the stop button.
    func cancel() {
        queue.run { [weak self] in
            guard let self, let plan, !plan.isFraming else { return }
            self.finish(cancelled: true, alreadyResolved: nil)
        }
    }

    /// Forget where the stars were. Every entry and exit from a segment goes through here,
    /// so a new piece of tracking state only has to be cleared in one place.
    private func resetAlignment() {
        referenceStars = []
        previousStars = []
        accumulatedTransform = .identity
    }

    // MARK: - Frame intake

    /// Consume one sensor frame. Called on the capture queue; the pixel buffer must not
    /// escape this call.
    func consume(_ frame: SensorFrame) {
        guard let plan else { return }

        accumulator.prepare(
            width: CVPixelBufferGetWidth(frame.pixelBuffer),
            height: CVPixelBufferGetHeight(frame.pixelBuffer)
        )

        var transform: simd_float3x3?
        if plan.aligns {
            guard let alignment = track(frame) else {
                // Tracking lost: clouds, a bumped tripod, or a frame with too few stars.
                // Stacking it anyway would smear the whole result, so it is dropped —
                // losing one frame of light costs far less than corrupting the stack.
                progress.framesRejected += 1
                report()
                return
            }
            transform = alignment
        }

        // The first frame of a segment *replaces* the buffer instead of adding to it. That
        // one rule removes every explicit clear: framing gets a fresh frame each time, a
        // session starts from black rather than from the last framing frame, and each
        // time-lapse segment starts clean — without a full-resolution write of zeros.
        accumulator.add(
            frame.pixelBuffer,
            transform: transform,
            mode: plan.stackMode,
            replacingContents: framesInSegment == 0
        )
        framesInSegment += 1

        if !plan.isFraming {
            progress.framesStacked += 1
        }

        if framesInSegment >= plan.framesPerSegment {
            completeSegment(plan)
        } else if let rendered = accumulator.resolve(tone: plan.tone, mode: plan.stackMode) {
            // Push the growing stack to the screen. Watching stars precipitate out of the
            // noise is how you know focus and framing are right, minutes before the end.
            publish(rendered)
        }

        report()
    }

    /// Detect stars and solve this frame's transform back to the reference frame.
    private func track(_ frame: SensorFrame) -> simd_float3x3? {
        guard let luminance = accumulator.readLuminance(from: frame.pixelBuffer) else { return nil }

        let stars = detector.detect(
            in: luminance,
            width: accumulator.lumaWidth,
            height: accumulator.lumaHeight
        )
        progress.starsTracked = stars.count

        guard stars.count >= 6 else { return nil }

        // First frame defines the reference frame; nothing to solve.
        if referenceStars.isEmpty {
            referenceStars = stars
            previousStars = stars
            accumulatedTransform = .identity
            progress.alignmentResidual = 0
            return matrix_identity_float3x3
        }

        guard let step = aligner.align(
            moving: stars,
            reference: previousStars,
            initialGuess: .identity
        ), step.isTrustworthy else {
            return nil
        }

        accumulatedTransform = step.transform.concatenated(with: accumulatedTransform)
        previousStars = stars
        progress.alignmentResidual = step.residual

        // Star coordinates come from the downsampled luma buffer; the shader samples the
        // full-resolution frame, so the translation scales up by the same factor. Rotation
        // is scale-invariant and passes through untouched.
        let scale = Double(accumulator.width) / Double(max(accumulator.lumaWidth, 1))
        let scaled = SimilarityTransform(
            rotation: accumulatedTransform.rotation,
            translationX: accumulatedTransform.translationX * scale,
            translationY: accumulatedTransform.translationY * scale
        )

        // The shader walks accumulator coordinates back to frame coordinates, which is the
        // inverse of the frame-to-reference transform solved above.
        return scaled.inverted.matrix
    }

    private func completeSegment(_ plan: SegmentPlan) {
        let resolved = accumulator.resolve(tone: plan.tone, mode: plan.stackMode)
        framesInSegment = 0

        // Framing has no segment count and never completes — the next frame just replaces
        // this one.
        guard let total = plan.segments else {
            resolved.map(publish)
            return
        }

        progress.segmentsCompleted += 1

        if let resolved, total > 1 {
            // Time-lapse: encode inline, synchronously, while we still own the texture.
            onSegmentReady?(resolved, progress.segmentsCompleted - 1)
        }

        if progress.segmentsCompleted >= total {
            finish(cancelled: false, alreadyResolved: resolved)
        } else {
            resolved.map(publish)
            // Each output frame is its own picture: over a long time-lapse the sky rotates
            // far past what frame-to-frame tracking should be asked to carry.
            resetAlignment()
        }
    }

    /// End the recording and hand back the final image as bytes.
    ///
    /// The snapshot is taken here, on the capture queue, while nothing else is writing.
    /// This is the difference between saving a photo and crashing on one.
    ///
    /// `alreadyResolved` is the texture `completeSegment` just produced from an unchanged
    /// accumulator — resolving again would repeat a full-resolution pass to get identical
    /// pixels.
    private func finish(cancelled: Bool, alreadyResolved: MTLTexture?) {
        guard let plan else { return }

        let rendered = alreadyResolved
            ?? accumulator.resolve(tone: plan.tone, mode: plan.stackMode)
        let final = rendered.map { accumulator.snapshot(of: $0) }
        // The bytes are copied out, so the texture goes straight back to the pool rather
        // than to the screen — the view is about to be fed framing frames anyway.
        rendered.map(accumulator.displayPool.release)

        if cancelled {
            logger.info("Session cancelled after \(self.progress.framesStacked) frames")
        }

        // Straight back to framing, with the framing curve. Leaving the capture curve in
        // place tone-mapped the next frames at stretch 12 — a bright flash at exactly the
        // moment the user looks up at the result.
        beginOnQueue(.framing)
        onFinished?(final)
    }

    /// Hand a rendered texture to the screen. Ownership goes with it: whoever displays
    /// the frame calls `release()` when the GPU has finished reading it.
    private func publish(_ texture: MTLTexture) {
        guard let onPreviewReady else {
            accumulator.displayPool.release(texture)
            return
        }
        onPreviewReady(PreviewFrame(texture: texture, pool: accumulator.displayPool))
    }

    private func report() {
        onProgress?(progress)
    }
}
