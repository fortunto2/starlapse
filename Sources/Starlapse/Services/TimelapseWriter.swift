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
///
/// A night is long enough for the encoder to die under it, and 1.2.1 lost whole nights
/// that way (24 Nov 2026: three hours of Star Trails on an iPhone 11 Pro, nothing kept).
/// One failed `AVAssetWriter` dropped every later frame, and the frames before it sat in
/// a file with no index, which the next launch then deleted. So, two defences:
///
/// - **Fragments.** The file is indexed every couple of output frames, so whatever was
///   written before a crash, a dead battery or a failed encoder plays.
/// - **Parts.** When a writer fails, the next frame starts a new file instead of being
///   dropped. `finish()` joins the parts back into one clip.
final class TimelapseWriter: @unchecked Sendable {

    /// File-name prefix the launch-time recovery looks for. Clips use `starlapse-event-`.
    static let prefix = "starlapse-timelapse-"

    private struct Part {
        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
        let url: URL
        /// Session frame index that sits at time zero in this file.
        let firstIndex: Int
        var started = false
    }

    private let width: Int
    private let height: Int
    private let frameRate: Int
    private let stamp: Int
    private let logger = Logger(subsystem: "co.superduperai.starlapse", category: "timelapse")
    /// Decided when the session starts: a purchase mid-shoot does not split one clip in two.
    private let watermark: Bool

    private var part: Part?
    /// Files whose writer stopped, finished or failed. Fragmented, so each plays up to its
    /// last fragment even when it failed.
    private var closedParts: [URL] = []
    private(set) var framesWritten = 0
    /// How many times the encoder died under this session. Reported with the save.
    private(set) var failures = 0

    init(width: Int, height: Int, frameRate: Int, watermark: Bool = false) throws {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.watermark = watermark
        self.stamp = Int(Date().timeIntervalSince1970)
        // Fail here, at the start of the night, rather than three hours in.
        part = try makePart(firstIndex: 0)
    }

    private func makePart(firstIndex: Int) throws -> Part {
        let name = "\(Self.prefix)\(stamp)-\(closedParts.count + 1).mov"
        let url = ScratchStore.directory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        let stack = try VideoWriterFactory.make(
            width: width, height: height, to: url,
            fragmentEvery: CMTime(value: 2, timescale: CMTimeScale(frameRate))
        )
        return Part(writer: stack.writer, input: stack.input, adaptor: stack.adaptor, url: url, firstIndex: firstIndex)
    }

    /// Append one rendered stack as the next frame of the clip.
    func append(_ texture: MTLTexture, frameIndex: Int) {
        if write(texture, frameIndex: frameIndex) { return }
        // The writer just failed. The frame cost minutes of sky: give it a fresh file.
        rollOver(at: frameIndex)
        if !write(texture, frameIndex: frameIndex) { rollOver(at: frameIndex + 1) }
    }

    private func rollOver(at frameIndex: Int) {
        if let dead = part {
            failures += 1
            logger.error("Time-lapse part failed, starting a new one: \(String(describing: dead.writer.error))")
            dead.writer.cancelWriting()
            closedParts.append(dead.url)
        }
        part = try? makePart(firstIndex: frameIndex)
    }

    /// Returns false only when the writer has failed; a frame it could not even start on
    /// (no pixel buffer) is not worth a new file.
    private func write(_ texture: MTLTexture, frameIndex: Int) -> Bool {
        guard var current = part else { return false }
        if !current.started {
            guard current.writer.startWriting() else { return false }
            current.writer.startSession(atSourceTime: .zero)
            current.started = true
            part = current
        }
        guard current.writer.status == .writing else { return false }
        guard let pool = current.adaptor.pixelBufferPool else { return true }

        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer else { return true }

        fill(pixelBuffer, from: texture)

        // Wait rather than drop: an output frame here cost minutes of sky.
        guard VideoWriterFactory.waitForReady(current.input, writer: current.writer) else {
            return current.writer.status == .writing
        }

        let time = CMTime(value: CMTimeValue(frameIndex - current.firstIndex), timescale: CMTimeScale(frameRate))
        guard current.adaptor.append(pixelBuffer, withPresentationTime: time) else { return false }
        framesWritten += 1
        return true
    }

    private func fill(_ pixelBuffer: CVPixelBuffer, from texture: MTLTexture) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bufferWidth = CVPixelBufferGetWidth(pixelBuffer)
        let bufferHeight = CVPixelBufferGetHeight(pixelBuffer)
        texture.getBytes(
            base,
            bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, min(texture.width, bufferWidth), min(texture.height, bufferHeight)),
            mipmapLevel: 0
        )
        if watermark, let context = Watermark.context(
            over: base, width: bufferWidth, height: bufferHeight, bytesPerRow: bytesPerRow
        ) {
            Watermark.stamp(context, width: bufferWidth, height: bufferHeight)
        }
    }

    /// Close the clip. Every part that holds a frame is kept and joined; nil only when not
    /// one frame was written.
    func finish() async -> URL? {
        if let current = part {
            part = nil
            if current.started {
                current.input.markAsFinished()
                await current.writer.finishWriting()
                if current.writer.status != .completed {
                    failures += 1
                    logger.error("Time-lapse failed to close: \(String(describing: current.writer.error))")
                }
                closedParts.append(current.url)
            } else {
                current.writer.cancelWriting()
                ScratchStore.remove(current.url)
            }
        }

        var playable: [URL] = []
        for url in closedParts {
            if await RecoveredClips.isPlayable(url) { playable.append(url) } else { ScratchStore.remove(url) }
        }
        guard let first = playable.first else { return nil }
        guard playable.count > 1 else { return first }

        let joined = ScratchStore.directory.appendingPathComponent("\(Self.prefix)\(stamp).mov")
        if await RecoveredClips.join(playable, into: joined) {
            ScratchStore.remove(playable)
            return joined
        }
        // Joining failed: the first part is still a time-lapse, and the rest stay on disk
        // for the next launch to offer.
        logger.error("Could not join \(playable.count) time-lapse parts; keeping the first")
        return first
    }
}
