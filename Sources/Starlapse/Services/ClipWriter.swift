import AVFoundation
import CoreVideo
import Foundation
import os
import VideoToolbox

/// Writes one short event clip from buffered frames.
///
/// Separate from `TimelapseWriter` because the job is the opposite shape: a time-lapse
/// receives one frame every so often over an hour, while this receives a burst of frames
/// that already exist and must be flushed before the next event arrives.
final class ClipWriter: @unchecked Sendable {

    private let logger = Logger(subsystem: "co.superduperai.starlapse", category: "clip")

    /// Encode a sequence of frames into a file. Runs on the capture queue.
    static func write(
        frames: [FrameRingBuffer.Entry],
        frameRate: Int,
        to url: URL
    ) -> URL? {
        guard let first = frames.first else { return nil }

        let width = CVPixelBufferGetWidth(first.pixelBuffer)
        let height = CVPixelBufferGetHeight(first.pixelBuffer)
        let evenWidth = width - (width % 2)
        let evenHeight = height - (height % 2)

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else {
            return nil
        }

        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: evenWidth,
                AVVideoHeightKey: evenHeight,
                AVVideoCompressionPropertiesKey: [
                    // A meteor is a thin bright line over near-black. Low bitrates smear
                    // exactly that away, and the clip is only a couple of seconds long.
                    AVVideoAverageBitRateKey: evenWidth * evenHeight * 14,
                    AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel,
                ],
            ]
        )
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: evenWidth,
                kCVPixelBufferHeightKey as String: evenHeight,
            ]
        )

        guard writer.canAdd(input) else { return nil }
        writer.add(input)

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for (index, entry) in frames.enumerated() {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.005)
            }
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
