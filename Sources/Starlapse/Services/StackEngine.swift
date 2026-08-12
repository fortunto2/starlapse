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
    /// Detector mode: transients seen, and clips actually written.
    var eventsDetected: Int = 0
    var eventsRecorded: Int = 0

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
    private let transientDetector = TransientDetector()
    private let logger = Logger(subsystem: "co.superduperai.starlapse", category: "stack")

    private var plan: SegmentPlan?
    /// The plan of a finished capture, kept so the result can be re-rendered.
    ///
    /// While this is set the engine ignores incoming frames and the accumulator is left
    /// untouched — which is what makes review possible at all. The float32 buffer still
    /// holds the summed light, so changing the curve re-renders from the original data
    /// rather than pushing pixels around in an already-developed image.
    private var completed: SegmentPlan?
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

    /// Show one live frame in this many, while watching. Four frames a second is for the
    /// detector's benefit, not the viewer's.
    static let watchPreviewInterval = 4
    private var previewCountdown = 0
    private var watcher: SkyWatcher?

    /// A clip was written. Called on the capture queue.
    var onEventRecorded: (@Sendable (URL, Transient) -> Void)?

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
    /// Capture complete. The result stays in the accumulator for review; nothing is
    /// saved until asked.
    var onFinished: (@Sendable () -> Void)?

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
        completed = nil

        previewCountdown = 0
        watcher = plan.detector.map(SkyWatcher.init(settings:))
        framesInSegment = 0
        resetAlignment()
        progress = StackProgress(
            framesRequested: plan.totalFrames ?? 0,
            segmentsRequested: plan.segments ?? 0
        )

        if plan.isStoppable {
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
            guard let self, let plan, plan.isStoppable else { return }
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

        if let watcher {
            watch(frame, watcher: watcher, plan: plan)
            return
        }

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

    // MARK: - Detector

    /// Hand the frame to the watcher, and keep the live view alive at a modest rate.
    private func watch(_ frame: SensorFrame, watcher: SkyWatcher, plan: SegmentPlan) {
        accumulator.prepare(
            width: CVPixelBufferGetWidth(frame.pixelBuffer),
            height: CVPixelBufferGetHeight(frame.pixelBuffer)
        )

        // The live view, but not every frame. Watching runs for hours at four frames a
        // second with the screen dimmed and nobody looking; refreshing it each time wrote
        // and read back the full float32 accumulator — around 500 MB of GPU traffic per
        // frame — to redraw a picture of an empty sky.
        previewCountdown -= 1
        if previewCountdown <= 0 {
            previewCountdown = Self.watchPreviewInterval
            accumulator.add(frame.pixelBuffer, transform: nil, mode: plan.stackMode, replacingContents: true)
            if let rendered = accumulator.resolve(tone: plan.tone, mode: plan.stackMode) {
                publish(rendered)
            }
        }

        guard let luminance = accumulator.readLuminance(from: frame.pixelBuffer) else { return }

        switch watcher.consume(
            frame,
            luminance: luminance,
            width: accumulator.lumaWidth,
            height: accumulator.lumaHeight
        ) {
        case .waiting:
            break
        case .discarded:
            progress.eventsDetected += 1
        case .recorded(let url, let event):
            progress.eventsDetected += 1
            progress.eventsRecorded = watcher.eventsRecorded
            onEventRecorded?(url, event)
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

        if cancelled {
            logger.info("Session cancelled after \(self.progress.framesStacked) frames")
        }

        // Stop consuming frames but leave the accumulator alone: the summed light is the
        // negative, and review develops it. Framing resumes only when the user is done.
        completed = plan
        self.plan = nil

        if let rendered = alreadyResolved {
            publish(rendered)
        } else if let rendered = accumulator.resolve(tone: plan.tone, mode: plan.stackMode) {
            publish(rendered)
        }

        onFinished?()
    }

    // MARK: - Review

    /// Re-develop the finished capture with a different curve.
    ///
    /// Non-destructive by construction: the accumulator holds the summed frames in float32,
    /// so this is the same render the session would have produced with these settings — not
    /// an adjustment layered onto an already-clipped image.
    func rerender(tone: FrameAccumulator.ToneSettings) {
        queue.run { [weak self] in
            guard let self, var completed else { return }
            completed.tone = tone
            self.completed = completed
            if let rendered = accumulator.resolve(tone: tone, mode: completed.stackMode) {
                publish(rendered)
            }
        }
    }

    /// Render the reviewed result to bytes for saving.
    func exportResult() async -> RenderedImage? {
        await queue.perform { [weak self] in
            guard let self, let completed else { return nil }
            guard let rendered = accumulator.resolve(
                tone: completed.tone, mode: completed.stackMode
            ) else { return nil }
            let image = accumulator.snapshot(of: rendered)
            accumulator.displayPool.release(rendered)
            return image
        }
    }

    /// Leave review and go back to composing the next shot.
    func resumeFraming() {
        begin(.framing)
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
