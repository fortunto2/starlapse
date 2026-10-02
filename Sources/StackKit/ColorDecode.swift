import Foundation

/// The curve a camera applies to light before quantising it, and its inverse.
///
/// Stacking is averaging photons, and photons add linearly. A camera hands over values
/// *after* a transfer curve, so averaging them as they arrive averages the wrong thing:
/// the mean of encoded values is not the encoding of the mean, and the error lands on
/// exactly the faint, noisy pixels astrophotography is about.
public enum TransferFunction: Sendable, CaseIterable {
    /// IEC 61966-2-1. What a BGRA buffer from the camera carries.
    case sRGB
    /// ITU-R BT.709 OETF. What the camera's YCbCr video formats carry.
    case bt709

    public func decode(_ value: Float) -> Float {
        let v = max(value, 0)
        switch self {
        case .sRGB:
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        case .bt709:
            return v < 0.081 ? v / 4.5 : pow((v + 0.099) / 1.099, 1 / 0.45)
        }
    }

    public func encode(_ value: Float) -> Float {
        let v = min(max(value, 0), 1)
        switch self {
        case .sRGB:
            return v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
        case .bt709:
            return v < 0.018 ? v * 4.5 : 1.099 * pow(v, 0.45) - 0.099
        }
    }
}

/// Biplanar 4:2:0 YCbCr, as the camera's `420v`, `420f`, `x420` and `xf20` formats deliver.
///
/// The same arithmetic runs in `Stacking.metal`; this copy exists so it can be tested,
/// and so the CLI can emulate what a given bit depth costs before a phone is involved.
public struct YCbCrDecoder: Sendable, Hashable {
    public let bitDepth: Int
    /// Full range uses every code; video range keeps headroom (Y 16–235, C 16–240 at 8 bits).
    public let fullRange: Bool

    public init(bitDepth: Int, fullRange: Bool) {
        self.bitDepth = bitDepth
        self.fullRange = fullRange
    }

    private var scale: Float { Float(1 << (bitDepth - 8)) }
    private var maxCode: Float { Float((1 << bitDepth) - 1) }

    /// Codes → encoded (non-linear) RGB in 0...1. BT.709 matrix.
    public func rgb(y: Int, cb: Int, cr: Int) -> (r: Float, g: Float, b: Float) {
        let luma: Float
        let blue: Float
        let red: Float
        if fullRange {
            luma = Float(y) / maxCode
            blue = Float(cb) / maxCode - 0.5
            red = Float(cr) / maxCode - 0.5
        } else {
            luma = (Float(y) - 16 * scale) / (219 * scale)
            blue = (Float(cb) - 128 * scale) / (224 * scale)
            red = (Float(cr) - 128 * scale) / (224 * scale)
        }
        let r = luma + 1.5748 * red
        let g = luma - 0.1873 * blue - 0.4681 * red
        let b = luma + 1.8556 * blue
        return (min(max(r, 0), 1), min(max(g, 0), 1), min(max(b, 0), 1))
    }

    /// The code a camera would write for an encoded luma value — the quantisation step.
    public func lumaCode(_ encoded: Float) -> Int {
        let value = min(max(encoded, 0), 1)
        let code = fullRange ? value * maxCode : 16 * scale + value * 219 * scale
        return Int(code.rounded())
    }

    /// Neutral chroma: what a grey pixel carries in Cb and Cr.
    public var neutralChroma: Int {
        fullRange ? Int((maxCode / 2).rounded()) : Int(128 * scale)
    }
}
