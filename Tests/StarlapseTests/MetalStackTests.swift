import CoreVideo
import simd
import StackKit
import Testing
@testable import Starlapse

/// The GPU pipeline against the CPU reference it was written from. No camera: the
/// frames are built by hand, so the simulator's Metal is enough to run every kernel.
@Suite("Metal stacking matches the CPU reference", .serialized)
struct MetalStackTests {

    static let width = 64
    static let height = 32

    // MARK: - Frames built by hand

    static func buffer(_ type: OSType) throws -> CVPixelBuffer {
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [CFString: Any],
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(nil, width, height, type, attributes as CFDictionary, &buffer)
        #expect(status == kCVReturnSuccess)
        return try #require(buffer)
    }

    /// A flat grey frame at `linear` brightness, encoded the way the camera would.
    static func flat(_ linear: Float, type: OSType) throws -> CVPixelBuffer {
        let buffer = try buffer(type)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let layout = FramePixels(type)
        switch layout {
        case .bgra:
            let code = UInt8((TransferFunction.sRGB.encode(linear) * 255).rounded())
            fill(buffer, plane: 0, bytesPerPixel: 4) { [code, code, code, 255] }
        case .biplanar(let tenBit, let fullRange):
            let decoder = YCbCrDecoder(bitDepth: tenBit ? 10 : 8, fullRange: fullRange)
            let y = decoder.lumaCode(TransferFunction.bt709.encode(linear))
            let c = decoder.neutralChroma
            if tenBit {
                // x420: ten bits in the top of each 16-bit word.
                fill(buffer, plane: 0, bytesPerPixel: 2) { bytes(UInt16(y) << 6) }
                fill(buffer, plane: 1, bytesPerPixel: 4) { bytes(UInt16(c) << 6) + bytes(UInt16(c) << 6) }
            } else {
                fill(buffer, plane: 0, bytesPerPixel: 1) { [UInt8(y)] }
                fill(buffer, plane: 1, bytesPerPixel: 2) { [UInt8(c), UInt8(c)] }
            }
        case .unsupported:
            Issue.record("unsupported pixel format in test")
        }
        return buffer
    }

    private static func bytes(_ word: UInt16) -> [UInt8] { [UInt8(word & 0xFF), UInt8(word >> 8)] }

    private static func fill(_ buffer: CVPixelBuffer, plane: Int, bytesPerPixel: Int, pixel: () -> [UInt8]) {
        let planar = CVPixelBufferIsPlanar(buffer)
        guard let base = planar ? CVPixelBufferGetBaseAddressOfPlane(buffer, plane) : CVPixelBufferGetBaseAddress(buffer)
        else { return }
        let stride = planar ? CVPixelBufferGetBytesPerRowOfPlane(buffer, plane) : CVPixelBufferGetBytesPerRow(buffer)
        let rows = planar ? CVPixelBufferGetHeightOfPlane(buffer, plane) : CVPixelBufferGetHeight(buffer)
        let columns = planar ? CVPixelBufferGetWidthOfPlane(buffer, plane) : CVPixelBufferGetWidth(buffer)
        let value = pixel()
        for row in 0..<rows {
            let line = base.advanced(by: row * stride).assumingMemoryBound(to: UInt8.self)
            for column in 0..<columns {
                for (offset, byte) in value.enumerated() { line[column * bytesPerPixel + offset] = byte }
            }
        }
    }

    static func accumulator() throws -> FrameAccumulator {
        let accumulator = try FrameAccumulator()
        accumulator.reset(width: width, height: height)
        return accumulator
    }

    static func shift(_ pixels: Float) -> simd_float3x3 {
        simd_float3x3(columns: (SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(pixels, 0, 1)))
    }

    /// Mean blue channel of a resolved BGRA image over a column range.
    static func mean(of image: RenderedImage, columns: Range<Int>) -> Float {
        var sum: Float = 0
        var count: Float = 0
        image.pixels.withUnsafeBytes { raw in
            for row in 0..<image.height {
                for column in columns {
                    sum += Float(raw[row * image.bytesPerRow + column * 4]) / 255
                    count += 1
                }
            }
        }
        return sum / count
    }

    // MARK: - Decode

    @Test("Every input format decodes to the same linear light", arguments: [
        kCVPixelFormatType_32BGRA,
        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
        kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
    ])
    func decodesToLinear(type: OSType) throws {
        let accumulator = try Self.accumulator()
        for linear: Float in [0.02, 0.1, 0.4] {
            let pixels = try #require(accumulator.linearPixels(from: try Self.flat(linear, type: type)))
            let centre = pixels[Self.width * Self.height / 2 + Self.width / 2]
            // 8-bit encoding steps are ~0.004 in linear terms around 0.02; everything else is finer.
            #expect(abs(centre.x - linear) < 0.006, "\(FormatFacts.fourCC(type)) at \(linear): \(centre)")
            #expect(abs(centre.y - linear) < 0.006)
            #expect(abs(centre.z - linear) < 0.006)
        }
    }

    // MARK: - Accumulate and resolve

    @Test("A pixel divides by the frames that reached it")
    func coverageIsPerPixel() throws {
        let accumulator = try Self.accumulator()
        let frame = try Self.flat(0.4, type: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        accumulator.add(frame, transform: nil, mode: .stars, replacingContents: true)
        // Second frame shifted half a width: the right half gets no sample from it.
        accumulator.add(frame, transform: Self.shift(Float(Self.width / 2)), mode: .stars)

        let image = try #require(accumulator.resolvedBytes(mode: .stars))
        let left = Self.mean(of: image, columns: 0..<(Self.width / 2))
        let right = Self.mean(of: image, columns: (Self.width / 2)..<Self.width)
        #expect(abs(left - 0.4) < 0.01)
        #expect(abs(right - 0.4) < 0.01, "right half darkened: \(right)")
    }

    @Test("A one-frame outlier is rejected once the pixel has a history")
    func sigmaClipRejectsOutlier() throws {
        let accumulator = try Self.accumulator()
        let sky = try Self.flat(0.2, type: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        let flash = try Self.flat(0.9, type: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        accumulator.add(sky, transform: nil, mode: .stars, replacingContents: true)
        for _ in 0..<9 { accumulator.add(sky, transform: nil, mode: .stars) }
        accumulator.add(flash, transform: nil, mode: .stars)

        let image = try #require(accumulator.resolvedBytes(mode: .stars))
        let value = Self.mean(of: image, columns: 0..<Self.width)
        // Averaged in, the flash would lift 0.2 to 0.264.
        #expect(abs(value - 0.2) < 0.01, "outlier averaged in: \(value)")
    }

    @Test("Trails keep the brightest value")
    func lightenKeepsPeak() throws {
        let accumulator = try Self.accumulator()
        let dim = try Self.flat(0.1, type: kCVPixelFormatType_32BGRA)
        let bright = try Self.flat(0.5, type: kCVPixelFormatType_32BGRA)
        accumulator.add(bright, transform: nil, mode: .trails, replacingContents: true)
        accumulator.add(dim, transform: nil, mode: .trails)

        let image = try #require(accumulator.resolvedBytes(mode: .trails))
        #expect(abs(Self.mean(of: image, columns: 0..<Self.width) - 0.5) < 0.01)
    }
}
