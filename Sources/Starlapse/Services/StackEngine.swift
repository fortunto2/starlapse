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

/// Drives one capture: detect, align, accumulate, and in time-lapse mode, segment.
///
/// Lives on the capture queue like the rest of the pipeline. The only thing crossing back
/// to the main actor is the progress struct and the finished textures.
final class StackEngine: @unchecked Sendable {

    private let accumulator: FrameAccumulator
    private let detector = StarDetector()
    private let aligner = StarAligner()
    private let logger = Logger(subsystem: "co.superduperai.starlapse", category: "stack")

    private var settings: CaptureSettings?
    private var mode: CaptureMode = .still
    private var tone = FrameAccumulator.ToneSettings()

    /// Stars from the frame everything else is registered onto.
    private var referenceStars: [StarPoint] = []
    /// Stars from the previous frame — the aligner steps frame to frame, because between
    /// two consecutive frames the sky has barely moved and matching is trivial.
    private var previousStars: [StarPoint] = []
    /// Transform from the current frame back to the reference frame.
    private var accumulatedTransform = SimilarityTransform.identity

    private var progress = StackProgress()
    private var segmentFrameTarget = 0
    private var segmentStartTime: TimeInterval = 0
    private var isRunning = false

    /// Called on the capture queue after every frame.
    var onProgress: (@Sendable (StackProgress) -> Void)?
    /// Called on the capture queue when a time-lapse segment is resolved.
    ///
    /// The handler must consume the texture **synchronously**: the accumulator is cleared
    /// for the next segment as soon as this returns, and the texture is reused. Handing it
    /// to another thread would encode whatever the next segment has written into it.
    var onSegmentReady: (@Sendable (MTLTexture, Int) -> Void)?
    /// Called when the whole session is done. Carries no texture — the receiver asks for
    /// the final render itself, so no GPU object crosses an isolation boundary.
    var onFinished: (@Sendable () -> Void)?

    init(accumulator: FrameAccumulator) {
        self.accumulator = accumulator
    }

    // MARK: - Session control

    func begin(settings: CaptureSettings, mode: CaptureMode, tone: FrameAccumulator.ToneSettings) {
        self.settings = settings
        self.mode = mode
        self.tone = tone

        referenceStars = []
        previousStars = []
        accumulatedTransform = .identity

        switch mode {
        case .still:
            segmentFrameTarget = settings.frameCount
            progress = StackProgress(
                framesRequested: settings.frameCount,
                segmentsRequested: 1
            )
        case .timelapse(let timelapse):
            segmentFrameTarget = max(1, Int(timelapse.lightPerFrame / settings.frameExposure))
            progress = StackProgress(
                framesRequested: segmentFrameTarget * timelapse.frameCount,
                segmentsRequested: timelapse.frameCount
            )
        }

        isRunning = true
        logger.info("""
            Session start: \(self.progress.framesRequested) frames, \
            \(self.segmentFrameTarget) per segment, mode \(String(describing: mode))
            """)
    }

    func cancel() {
        isRunning = false
    }

    // MARK: - Frame intake

    /// Consume one sensor frame. Called on the capture queue; the pixel buffer must not
    /// escape this call.
    func consume(_ frame: SensorFrame) {
        guard isRunning, let settings else { return }

        if accumulator.frameCount == 0 && progress.framesStacked == 0 {
            let width = CVPixelBufferGetWidth(frame.pixelBuffer)
            let height = CVPixelBufferGetHeight(frame.pixelBuffer)
            accumulator.reset(width: width, height: height)
            segmentStartTime = frame.timestamp
        }

        var transform: simd_float3x3?

        if settings.stackMode.alignsStars {
            if let alignment = track(frame) {
                transform = alignment
            } else {
                // Tracking lost: clouds, a bumped tripod, or a frame with too few stars.
                // Stacking it anyway would smear the whole result, so it is dropped —
                // losing one frame of light costs far less than corrupting the stack.
                progress.framesRejected += 1
                report()
                return
            }
        }

        accumulator.add(frame.pixelBuffer, transform: transform, mode: settings.stackMode)
        progress.framesStacked += 1

        if accumulator.frameCount >= segmentFrameTarget {
            completeSegment()
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

    private func completeSegment() {
        guard let settings else { return }

        let resolved = accumulator.resolve(tone: tone, mode: settings.stackMode)
        progress.segmentsCompleted += 1

        switch mode {
        case .still:
            isRunning = false
            onFinished?()

        case .timelapse(let timelapse):
            if let resolved {
                // Synchronous by contract — see `onSegmentReady`.
                onSegmentReady?(resolved, progress.segmentsCompleted - 1)
            }

            if progress.segmentsCompleted >= timelapse.frameCount {
                isRunning = false
                onFinished?()
            } else {
                // Start the next segment clean. Alignment restarts too: over a long
                // time-lapse the sky rotates far past what frame-to-frame tracking should
                // be asked to carry, and each output frame is its own picture anyway.
                accumulator.clear()
                referenceStars = []
                previousStars = []
                accumulatedTransform = .identity
            }
        }
    }

    private func report() {
        onProgress?(progress)
    }

    // MARK: - Live preview

    /// Render the stack as it stands, for the live preview.
    func currentPreview(tone: FrameAccumulator.ToneSettings) -> MTLTexture? {
        guard let settings else { return nil }
        return accumulator.resolve(tone: tone, mode: settings.stackMode)
    }
}
