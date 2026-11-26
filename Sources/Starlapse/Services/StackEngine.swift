import CoreVideo
import Foundation
import Metal
import os
import simd
import SkyMeter
import StackKit

/// Runs one `SegmentPlan`: gather frames, resolve them into a picture, repeat.
///
/// Framing, a single deep exposure and a time-lapse are the same loop with different
/// numbers — see `SegmentPlan`. Everything here executes on the shared `CaptureQueue`;
/// public methods that can be called from elsewhere hop onto it themselves.
final class StackEngine: @unchecked Sendable {

    let accumulator: FrameAccumulator
    private let queue: CaptureQueue
    private let detector = StarDetector()
    private let aligner = StarAligner()
    private let transientDetector = TransientDetector()
    private let logger = Logger(subsystem: "co.superduperai.starlapse", category: "stack")
    /// Gyroscope readings to judge each frame by; nil (or empty, in the Simulator) keeps all.
    var shakeLog: ShakeLog?

    private var plan: SegmentPlan?
    /// How framing frames are developed: linear at night, a day curve in daylight.
    private var framingTone = FrameAccumulator.ToneSettings.neutral
    /// The plan of a finished capture, kept so the result can be re-rendered.
    ///
    /// While this is set the engine ignores incoming frames and the accumulator is left
    /// untouched — which is what makes review possible at all. The float32 buffer still
    /// holds the summed light, so changing the curve re-renders from the original data
    /// rather than pushing pixels around in an already-developed image.
    private var completed: SegmentPlan?
    var latestLuminance: LumaImage?
    /// Frames gathered into the segment currently being built.
    private var framesInSegment = 0

    /// Stars from the frame everything else is registered onto.
    private var referenceStars: [StarPoint] = []
    /// Transform from the last aligned frame back to the reference frame: the next frame's
    /// starting guess.
    private var accumulatedTransform = SimilarityTransform.identity
    /// When the reference frame was shot and how the phone was held then (`CameraTurn`).
    private var referencePose: (time: Double, attitude: simd_quatd?) = (0, nil)
    /// Moon mode's registration: the reference disc and the judge of steady frames.
    private var moonTracker = MoonTracker()

    var progress = StackProgress()

    /// Show one live frame in this many, while watching. Four frames a second is for the
    /// detector's benefit, not the viewer's.
    static let watchPreviewInterval = 4
    /// A Moon session that drops this many times its frame count ends with what it kept.
    static let moonAttempts = 10
    var previewCountdown = 0
    /// Redraws for the screen, paced apart from the frames themselves (`RenderPace`).
    private var framingPace = RenderPace(gap: RenderPace.framing)
    private var previewPace = RenderPace(gap: RenderPace.preview)
    private var watcher: SkyWatcher?

    /// Star sharpness of the next frame, once requested.
    private var focusContinuation: CheckedContinuation<FocusMetric, Never>?
    /// The pending focus reading is of the Moon's disc, not of stars.
    private var focusOnMoon = false
    private let focusEvaluator = FocusEvaluator()

    /// A clip was written. Called on the capture queue.
    var onEventRecorded: (@Sendable (URL, Transient, LumaImage.Size) -> Void)?

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
        if plan.isFraming { self.plan?.tone = framingTone }
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
            guard let self else { return }
            guard let plan = self.plan, plan.isStoppable else {
                // Nothing to stop here, yet the screen is capturing: end it anyway. A Stop
                // that does nothing leaves the person with no way out but killing the app.
                self.onFinished?()
                return
            }
            self.finish(cancelled: true, alreadyResolved: nil)
        }
    }

    /// Measure how sharp the stars are in the next frame to arrive.
    ///
    /// Used by the autofocus sweep: set a lens position, wait for a frame taken at it, read
    /// the star size back. The wait is unavoidable — the sensor has to actually expose one.
    func measureFocus(onMoon: Bool = false) async -> FocusMetric {
        await withCheckedContinuation { continuation in
            queue.run { [weak self] in
                guard let self else {
                    continuation.resume(returning: .none)
                    return
                }
                // A second request replaces the first rather than stacking up.
                focusContinuation?.resume(returning: .none)
                focusContinuation = continuation
                focusOnMoon = onMoon
            }
        }
    }

    /// Forget where the stars were. Every entry and exit from a segment goes through here,
    /// so a new piece of tracking state only has to be cleared in one place.
    private func resetAlignment() {
        referenceStars = []
        accumulatedTransform = .identity
        moonTracker = MoonTracker()
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

        // Composing needs a live view, not every frame the sensor makes.
        if plan.isFraming, !framingPace.admit(frame.timestamp) { return }

        accumulator.prepare(
            width: CVPixelBufferGetWidth(frame.pixelBuffer),
            height: CVPixelBufferGetHeight(frame.pixelBuffer)
        )

        // Framing frames feed the focus sweep: a session is never interrupted to answer one.
        if plan.isFraming, let luminance = accumulator.readLuminance(from: frame.pixelBuffer) {
            progress.framesFlat = CameraSilence.isFlat(luminance) ? progress.framesFlat + 1 : 0
            reportFocusIfRequested(luminance)
            // And for the overlay's sky lock, which solves a framing frame every few seconds.
            latestLuminance = LumaImage(pixels: luminance, width: accumulator.lumaWidth, height: accumulator.lumaHeight)
        }

        // Blur inside a frame is the one thing alignment cannot undo: a frame the phone
        // turned through is dropped before it costs a star detection.
        if plan.aligns, plan.framesPerSegment > 1, plan.exposure > 0,
           shakeLog?.moved(frameTime: frame.timestamp, exposure: plan.exposure) == true {
            progress.framesRejected += 1
            progress.framesMoved += 1
            report()
            return
        }

        var transform: simd_float3x3?
        if plan.stackMode == .moon {
            guard let alignment = trackMoon(frame) else {
                // No disc, or softer than the median. Without the cap, no disc ran forever.
                progress.framesRejected += 1
                if progress.framesRejected >= plan.framesPerSegment * Self.moonAttempts {
                    finish(cancelled: false, alreadyResolved: nil)
                }
                report()
                return
            }
            transform = alignment
        } else if plan.aligns {
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
        } else if previewPace.admit(frame.timestamp),
                  let rendered = accumulator.resolve(tone: plan.tone, mode: plan.stackMode) {
            // Push the growing stack to the screen. Watching stars precipitate out of the
            // noise is how you know focus and framing are right, minutes before the end.
            publish(rendered)
        }

        report()
    }

    /// Star and disc positions are in the quarter-size luma buffer; the shader samples the frame.
    private var lumaToFrame: Double {
        Double(accumulator.width) / Double(max(accumulator.lumaWidth, 1))
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

        switch StarTracking.decide(starCount: stars.count, hasReference: !referenceStars.isEmpty) {
        case .drop:
            return nil
        case .stackInPlace:
            return matrix_identity_float3x3
        case .reference:
            // First frame with stars defines the reference frame; nothing to solve.
            referenceStars = stars
            referencePose = (frame.timestamp, shakeLog?.attitude(at: frame.timestamp))
            accumulatedTransform = .identity
            progress.alignmentResidual = 0
            return matrix_identity_float3x3
        case .align:
            break
        }

        // Straight onto the reference, from where the last frame landed: chained steps compound.
        // And never turned further than the gyroscope saw the phone turn, plus the sky's turn.
        let twist = referencePose.attitude.flatMap { start in
            shakeLog?.attitude(at: frame.timestamp).map { CameraTurn.twist(from: start, to: $0) }
        }
        let allowed = CameraTurn.allowance(gyroTwist: twist, elapsed: frame.timestamp - referencePose.time)
        guard let step = aligner.align(moving: stars, reference: referenceStars, initialGuess: accumulatedTransform),
              step.isTrustworthy, abs(step.transform.rotation) <= allowed else { return nil }

        accumulatedTransform = step.transform
        progress.alignmentResidual = step.residual

        // Luma-buffer coordinates up to the full frame; rotation does not depend on scale.
        let scaled = accumulatedTransform.translationScaled(by: lumaToFrame)

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
            // Stopped before the first frame landed: the accumulator still holds the last
            // framing frame, and saving that under the session's name is a lie.
            guard let self, let completed, progress.framesStacked > 0 else { return nil }
            guard let rendered = accumulator.resolve(
                tone: completed.tone, mode: completed.stackMode
            ) else { return nil }
            let image = accumulator.snapshot(of: rendered)
            accumulator.displayPool.release(rendered)
            return image
        }
    }

    /// The latest watched frame's luminance, quarter size: a single frame's stars, enough
    /// to solve which way the camera points.
    func watchedLuminance() async -> LumaImage? {
        await queue.perform { [weak self] in self?.latestLuminance }
    }

    /// The finished stack as linear luminance, for measuring the sky. Not for star
    /// trails: a maximum is not a mean, and the sky in it reads brighter than it was.
    func skyLuminance() async -> LumaImage? {
        await queue.perform { [weak self] in
            guard let self, let completed, completed.stackMode.measuresSky else { return nil }
            return accumulator.stackLuminance()
        }
    }

    /// Develop framing frames with this curve from now on, including the framing running now.
    func setFramingTone(_ tone: FrameAccumulator.ToneSettings) {
        queue.run { [weak self] in
            self?.framingTone = tone
            if self?.plan?.isFraming == true { self?.plan?.tone = tone }
        }
    }

    /// A hot phone redraws a quarter as often; the stack keeps every frame.
    func setHot(_ hot: Bool) {
        let factor = hot ? RenderPace.hotFactor : 1
        queue.run { [weak self] in
            self?.framingPace.gap = RenderPace.framing * factor
            self?.previewPace.gap = RenderPace.preview * factor
        }
    }

    /// Leave review and go back to composing the next shot.
    func resumeFraming() { begin(.framing) }

    /// Hand a rendered texture to the screen. Ownership goes with it: whoever displays
    /// the frame calls `release()` when the GPU has finished reading it.
    func publish(_ texture: MTLTexture) {
        guard let onPreviewReady else {
            accumulator.displayPool.release(texture)
            return
        }
        onPreviewReady(PreviewFrame(texture: texture, pool: accumulator.displayPool))
    }

    func reportFocusIfRequested(_ luminance: [Float]) {
        guard let continuation = focusContinuation else { return }
        focusContinuation = nil
        let (width, height) = (accumulator.lumaWidth, accumulator.lumaHeight)
        continuation.resume(returning: focusOnMoon
            ? focusEvaluator.measureMoon(luminance, width: width, height: height)
            : focusEvaluator.measure(luminance, width: width, height: height))
    }

    func report() {
        onProgress?(progress)
    }
}

extension StackEngine {
    /// Register a Moon frame onto the reference disc, or nil to drop it — see `MoonTracker`.
    private func trackMoon(_ frame: SensorFrame) -> simd_float3x3? {
        guard let luminance = accumulator.readLuminance(from: frame.pixelBuffer),
              let shift = moonTracker.register(luminance, width: accumulator.lumaWidth, height: accumulator.lumaHeight)
        else {
            progress.framesWithoutMoon = moonTracker.sawDisc ? 0 : progress.framesWithoutMoon + 1
            return nil
        }
        progress.framesWithoutMoon = 0  // shader wants accumulator → frame: the inverse
        return shift.translationScaled(by: lumaToFrame).inverted.matrix
    }
}
