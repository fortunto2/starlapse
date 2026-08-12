import AVFoundation
import CoreVideo
import Foundation
import Metal
import os

/// Encodes finished stacks into an HEVC time-lapse, one output frame per stack.
///
/// Writing incrementally rather than holding frames in memory matters here: an hour-long
/// session at full sensor resolution would be gigabytes of float textures, and the app
/// would be killed long before the sky was done moving.
final class TimelapseWriter: @unchecked Sendable {

    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let frameRate: Int
    private let logger = Logger(subsystem: "co.superduperai.starlapse", category: "timelapse")
    private var started = false

    let outputURL: URL

    init(width: Int, height: Int, frameRate: Int) throws {
        let filename = "starlapse-\(Int(Date().timeIntervalSince1970)).mov"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        self.outputURL = url
        self.frameRate = frameRate

        let stack = try VideoWriterFactory.make(width: width, height: height, to: url)
        writer = stack.writer
        input = stack.input
        adaptor = stack.adaptor
    }

    /// Append one rendered stack as the next frame of the clip.
    func append(_ texture: MTLTexture, frameIndex: Int) {
        if !started {
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)
            started = true
        }

        guard writer.status == .writing else {
            logger.error("Writer not writing: \(String(describing: self.writer.error))")
            return
        }
        guard let pool = adaptor.pixelBufferPool else { return }

        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let width = min(texture.width, CVPixelBufferGetWidth(pixelBuffer))
            let height = min(texture.height, CVPixelBufferGetHeight(pixelBuffer))
            texture.getBytes(
                base,
                bytesPerRow: bytesPerRow,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0
            )
        }

        // Wait rather than drop: an output frame here cost minutes of sky time.
        VideoWriterFactory.waitForReady(input)

        let time = CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(frameRate))
        adaptor.append(pixelBuffer, withPresentationTime: time)
    }

    func finish() async -> URL? {
        guard started else { return nil }
        input.markAsFinished()
        await writer.finishWriting()

        guard writer.status == .completed else {
            logger.error("Time-lapse failed: \(String(describing: self.writer.error))")
            return nil
        }
        return outputURL
    }
}
