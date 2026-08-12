import AVFoundation
import CoreVideo
import Foundation

/// Writes one short event clip from buffered frames.
///
/// Separate from `TimelapseWriter` because the job is the opposite shape: a time-lapse
/// receives one frame every so often over an hour, while this receives a burst of frames
/// that already exist and must be flushed before the next event arrives.
enum ClipWriter {

    /// Encode a sequence of frames into a file. Runs on the capture queue.
    static func write(
        frames: [FrameRingBuffer.Entry],
        frameRate: Int,
        to url: URL
    ) -> URL? {
        guard let first = frames.first else { return nil }

        guard let stack = try? VideoWriterFactory.make(
            width: CVPixelBufferGetWidth(first.pixelBuffer),
            height: CVPixelBufferGetHeight(first.pixelBuffer),
            to: url
        ) else { return nil }
        let writer = stack.writer
        let input = stack.input
        let adaptor = stack.adaptor

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for (index, entry) in frames.enumerated() {
            VideoWriterFactory.waitForReady(input)
            let time = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(frameRate))
            adaptor.append(entry.pixelBuffer, withPresentationTime: time)
        }

        input.markAsFinished()

        // Finish synchronously: this runs on the capture queue, and the next event must not
        // start writing until this file is closed.
        let group = DispatchGroup()
        group.enter()
        writer.finishWriting { group.leave() }
        group.wait()

        guard writer.status == .completed else { return nil }
        return url
    }

    /// Where clips live before the user decides to keep them.
    static func clipURL(index: Int, timestamp: TimeInterval) -> URL {
        let name = String(format: "starlapse-event-%04d-%.0f.mov", index, timestamp)
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }
}
