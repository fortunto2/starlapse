import CoreVideo
import Foundation

/// What the camera put in a pixel buffer, as far as decoding cares.
enum FramePixels: Equatable {
    case biplanar(tenBit: Bool, fullRange: Bool)
    case bgra
    case unsupported

    init(_ type: OSType) {
        switch type {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange: self = .biplanar(tenBit: false, fullRange: false)
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange: self = .biplanar(tenBit: false, fullRange: true)
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange: self = .biplanar(tenBit: true, fullRange: false)
        case kCVPixelFormatType_420YpCbCr10BiPlanarFullRange: self = .biplanar(tenBit: true, fullRange: true)
        case kCVPixelFormatType_32BGRA: self = .bgra
        default: self = .unsupported
        }
    }

    /// Where the codes sit once Metal has normalised the plane to 0...1.
    ///
    /// Matches StackKit's `YCbCrDecoder`: full range is `code / maxCode` with chroma
    /// centred at half of it, video range is `(code − 16) / 219` and `(code − 128) / 224`
    /// at 8 bits, four times those at 10. A 10-bit plane is wrapped as `r16Unorm` with the
    /// ten bits in the top of the word, so a code normalises to `code × 64 / 65535`.
    struct CodeRange: Equatable {
        let black: Float
        let lumaRange: Float
        let chromaMid: Float
        let chromaRange: Float
    }

    var codeRange: CodeRange {
        guard case .biplanar(let tenBit, let fullRange) = self else {
            return CodeRange(black: 0, lumaRange: 1, chromaMid: 0.5, chromaRange: 1)
        }
        let unit: Float = tenBit ? 64 / 65535 : 1 / 255   // one code, normalised
        let maxCode: Float = tenBit ? 1023 : 255
        let scale: Float = tenBit ? 4 : 1
        if fullRange {
            let full = maxCode * unit
            return CodeRange(black: 0, lumaRange: full, chromaMid: full / 2, chromaRange: full)
        }
        return CodeRange(
            black: 16 * scale * unit, lumaRange: 219 * scale * unit,
            chromaMid: 128 * scale * unit, chromaRange: 224 * scale * unit
        )
    }

    /// The output formats to ask the camera for when stacking, best first: the sensor's
    /// own 4:2:0 at full range, then video range, then 10-bit. BGRA is the last resort.
    static let stackingPreference: [OSType] = [
        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
        kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
        kCVPixelFormatType_32BGRA,
    ]
}
