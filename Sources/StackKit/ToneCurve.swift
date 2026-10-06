import Foundation

/// The display stretch, as `Stacking.metal` applies it: subtract the sky, then asinh.
///
/// Here so the defaults can be derived rather than eyeballed. When the stack moved from
/// encoded camera values to linear light, the same numbers would have produced a much
/// darker picture; `fitLinear` finds the linear-space settings that reproduce the look
/// the encoded pipeline shipped with.
public struct ToneCurve: Sendable, Hashable {
    public var blackPoint: Float
    public var stretch: Float

    public init(blackPoint: Float, stretch: Float) {
        self.blackPoint = blackPoint
        self.stretch = stretch
    }

    public func apply(_ value: Float) -> Float {
        let pedestal = max(value - blackPoint, 0) / max(1 - blackPoint, 1e-4)
        let denominator = asinh(stretch)
        guard denominator >= 1e-4 else { return pedestal }
        return asinh(stretch * pedestal) / denominator
    }

    /// Settings for linear input that best match `encoded` applied to camera-encoded input,
    /// over the range where night skies live.
    public static func fitLinear(matching encoded: ToneCurve, transfer: TransferFunction) -> ToneCurve {
        let samples = (0..<200).map { 0.002 * pow(Float(250), Float($0) / 199) } // 0.002...0.5
        var best = ToneCurve(blackPoint: 0, stretch: 1)
        var bestError = Float.infinity
        for blackStep in 0...100 {
            let blackPoint = Float(blackStep) * 0.0002
            for stretchStep in 0...120 {
                let stretch = 1 * pow(Float(1000), Float(stretchStep) / 120)
                let candidate = ToneCurve(blackPoint: blackPoint, stretch: stretch)
                let error = samples.reduce(Float(0)) { sum, linear in
                    let diff = candidate.apply(linear) - encoded.apply(transfer.encode(linear))
                    return sum + diff * diff
                }
                if error < bestError {
                    bestError = error
                    best = candidate
                }
            }
        }
        return best
    }
}
