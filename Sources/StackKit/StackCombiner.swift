import Foundation

/// How frames become one picture. The CPU reference for `Stacking.metal`: same rules,
/// readable, and fast enough to run hundreds of emulated frames in the CLI.
public enum CombineMode: Sendable, Hashable {
    /// Average everything. Noise falls as √N; anything that crossed the frame once —
    /// a plane, a satellite, a cosmic ray — is averaged in at 1/N strength.
    case mean
    /// Average, but leave out any sample more than `kappa` standard deviations from the
    /// running mean of that pixel. Static things (stars, sky) pass; things that were there
    /// for one frame do not. Rejection starts after `warmup` samples, once σ means something.
    case sigmaClip(kappa: Float, warmup: Int)
    /// Brightest value wins. Star trails.
    case lighten
    /// Brightest value wins, but older light fades by `decay` per frame: trails with a head.
    case comet(decay: Float)
}

/// Per-pixel online combiner over linear, single-channel frames.
///
/// A `nan` sample means "this frame did not cover this pixel" — what the edge of an
/// aligned, rotating field looks like. Each pixel divides by its own count, so edges are
/// not darkened by frames that never reached them.
public struct StackCombiner: Sendable {
    public let width: Int
    public let height: Int
    public let mode: CombineMode

    private var count: [Float]
    private var mean: [Float]
    private var m2: [Float]
    private var peak: [Float]
    public private(set) var frames = 0
    public private(set) var rejected = 0

    public init(width: Int, height: Int, mode: CombineMode) {
        self.width = width
        self.height = height
        self.mode = mode
        let size = width * height
        count = [Float](repeating: 0, count: size)
        mean = [Float](repeating: 0, count: size)
        m2 = [Float](repeating: 0, count: size)
        peak = [Float](repeating: 0, count: size)
    }

    public mutating func add(_ frame: [Float]) {
        precondition(frame.count == width * height, "frame size mismatch")
        frames += 1
        for index in frame.indices {
            let sample = frame[index]
            guard !sample.isNaN else { continue }
            switch mode {
            case .mean:
                accept(sample, at: index)
            case .sigmaClip(let kappa, let warmup):
                let n = count[index]
                if n >= Float(warmup), n > 1 {
                    let sigma = (m2[index] / (n - 1)).squareRoot()
                    // A floor on σ: a pixel that has been perfectly constant (clipped black,
                    // or a quantised sky with no noise) would otherwise reject everything.
                    if abs(sample - mean[index]) > kappa * max(sigma, 1e-4) {
                        rejected += 1
                        continue
                    }
                }
                accept(sample, at: index)
            case .lighten:
                peak[index] = count[index] == 0 ? sample : max(peak[index], sample)
                count[index] += 1
            case .comet(let decay):
                peak[index] = count[index] == 0 ? sample : max(peak[index] * decay, sample)
                count[index] += 1
            }
        }
    }

    /// Welford's update: mean and variance in one pass, without the catastrophic
    /// cancellation of sum-of-squares in Float.
    private mutating func accept(_ sample: Float, at index: Int) {
        count[index] += 1
        let delta = sample - mean[index]
        mean[index] += delta / count[index]
        m2[index] += delta * (sample - mean[index])
    }

    /// The combined frame. Pixels no frame covered come out as `nan`.
    public func result() -> [Float] {
        switch mode {
        case .mean, .sigmaClip:
            return zip(mean, count).map { $1 > 0 ? $0 : .nan }
        case .lighten, .comet:
            return zip(peak, count).map { $1 > 0 ? $0 : .nan }
        }
    }
}

/// Dark frames: shots with the lens covered, at the same exposure and ISO.
///
/// What they hold is everything that is not sky — hot pixels, amplifier glow, the
/// sensor's fixed pattern. Averaged into a master and subtracted from every light frame,
/// they take it out before stacking can mistake it for a star.
public enum MasterDark {

    public static func average(_ darks: [[Float]]) -> [Float]? {
        guard let first = darks.first else { return nil }
        var sum = [Float](repeating: 0, count: first.count)
        for dark in darks where dark.count == sum.count {
            for index in dark.indices { sum[index] += dark[index] }
        }
        let n = Float(darks.count)
        return sum.map { $0 / n }
    }

    /// Only the pixels that are actually hot: master dark values more than `kappa` noise
    /// above the dark's own median, zero everywhere else.
    ///
    /// A phone's processed frames clip at black, so a full master dark is biased upward
    /// by the clipped read noise and adds its own noise to every pixel. Measured on the
    /// emulated sky (`starlapse-stack compare`): full subtraction cost 15% of faint-star
    /// SNR and left a -0.0012 bias, for hot pixels it removes just as well this way.
    public static func hotPixelMap(_ dark: [Float], kappa: Float = 6) -> [Float] {
        let sorted = dark.filter { !$0.isNaN }.sorted()
        guard !sorted.isEmpty else { return dark }
        let median = sorted[sorted.count / 2]
        let deviations = sorted.map { abs($0 - median) }.sorted()
        // MAD → σ for Gaussian noise; floored so a noiseless dark still flags real outliers.
        let sigma = max(1.4826 * deviations[deviations.count / 2], 1e-4)
        return dark.map { $0 - median > kappa * sigma ? $0 - median : 0 }
    }

    /// Subtract, keeping `nan` coverage holes. Negative values are kept on purpose: the
    /// noise around zero has to average out, and clipping it first biases the sky upward.
    public static func subtract(_ dark: [Float], from frame: [Float]) -> [Float] {
        zip(frame, dark).map { $0.isNaN ? .nan : $0 - $1 }
    }
}

/// Hot pixels without dark frames: a pixel far brighter than all eight of its neighbours.
///
/// A star cannot look like that — the lens spreads even the faintest one over a few
/// pixels, so its neighbours are lit too. A hot pixel is one photosite, alone. The same
/// rule runs per frame in `Stacking.metal`, before alignment moves anything.
public enum CosmeticCorrection {

    /// Replace isolated spikes with the mean of their neighbours.
    ///
    /// - Parameters:
    ///   - ratio: how many times brighter than the brightest neighbour (above the sky) a
    ///     pixel must be to count as hot.
    ///   - floor: minimum excess, so noise in an empty sky is never "corrected".
    public static func apply(
        _ frame: [Float], width: Int, height: Int, ratio: Float = 3, floor: Float = 0.02
    ) -> [Float] {
        var out = frame
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let index = y * width + x
                let value = frame[index]
                guard !value.isNaN else { continue }
                var brightest = -Float.infinity
                var darkest = Float.infinity
                var sum: Float = 0
                var count: Float = 0
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let neighbour = frame[index + dy * width + dx]
                        guard !neighbour.isNaN else { continue }
                        brightest = max(brightest, neighbour)
                        darkest = min(darkest, neighbour)
                        sum += neighbour
                        count += 1
                    }
                }
                guard count == 8 else { continue }
                let excess = value - darkest
                if excess > floor, excess > ratio * (brightest - darkest) {
                    out[index] = sum / count
                }
            }
        }
        return out
    }
}
