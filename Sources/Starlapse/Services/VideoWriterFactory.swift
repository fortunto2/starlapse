import AVFoundation
import CoreVideo
import Foundation
import VideoToolbox

/// Builds the AVFoundation writing stack shared by the time-lapse and the event clips.
///
/// The two writers have genuinely different lifecycles — one receives a frame every few
/// minutes for an hour, the other flushes a burst that already exists — so they stay
/// separate. What they had no business duplicating is the *construction*, and the copies
/// had already drifted: one asked for 12 bits per pixel and the other 14, and only one
/// requested Metal compatibility. Those are the settings that decide whether a meteor
/// survives compression, so they belong in one place.
enum VideoWriterFactory {

    struct Stack {
        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
    }

    /// Bits per pixel per frame. Night skies are smooth gradients over near-black, where
    /// low bitrates band badly and thin bright streaks vanish entirely.
    static let bitsPerPixel = 14

    static func make(width: Int, height: Int, to url: URL) throws -> Stack {
        // HEVC refuses odd dimensions.
        let evenWidth = width - (width % 2)
        let evenHeight = height - (height % 2)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: evenWidth,
                AVVideoHeightKey: evenHeight,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: evenWidth * evenHeight * bitsPerPixel,
                    AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel,
                ],
            ]
        )
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: pixelBufferAttributes(width: evenWidth, height: evenHeight)
        )

        guard writer.canAdd(input) else {
            throw StackError.metalUnavailable
        }
        writer.add(input)

        return Stack(writer: writer, input: input, adaptor: adaptor)
    }

    /// BGRA, Metal-compatible — the format every stage of this pipeline speaks.
    static func pixelBufferAttributes(width: Int, height: Int) -> [String: Any] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
    }

    /// Block until the input will take another frame.
    ///
    /// Both writers are fed from the capture queue and must not drop anything: a time-lapse
    /// frame cost minutes of sky, and an event frame cannot be re-shot at all.
    static func waitForReady(_ input: AVAssetWriterInput) {
        while !input.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.005)
        }
    }
}
