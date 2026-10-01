import AVFoundation
import CoreMedia

// MARK: - Frame delivery

/// Bridges the Objective-C delegate callback into a closure.
///
/// Separate from `CaptureEngine` so the delegate conformance stays `nonisolated` without
/// dragging the engine's queue discipline into the type system.
final class FrameReceiver: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    private let onFrame: @Sendable (SensorFrame) -> Void
    private var index = 0

    init(onFrame: @escaping @Sendable (SensorFrame) -> Void) {
        self.onFrame = onFrame
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        onFrame(SensorFrame(pixelBuffer: pixelBuffer, timestamp: timestamp, index: index))
        index += 1
    }
}

// MARK: - Clamping

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
