import Foundation

/// A star found in a frame, located to sub-pixel precision.
public struct StarPoint: Sendable, Hashable {
    public let x: Double
    public let y: Double
    /// Summed brightness above the local background.
    public let flux: Double

    public init(x: Double, y: Double, flux: Double) {
        self.x = x
        self.y = y
        self.flux = flux
    }

    public func distance(to other: StarPoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// Finds stars in a luminance buffer.
///
/// The hard part is not finding bright pixels — it is *not* finding the bright pixels that
/// are not stars. A long exposure at high ISO is full of hot pixels: single sensor sites
/// that read high every single frame, in exactly the same place. Averaged into a stack they
/// become fake stars, and worse, they are perfectly stationary, so an aligner that trusts
/// them will lock onto the sensor instead of the sky and undo the entire alignment.
///
/// The discriminator is shape. A real star is spread across several pixels by the lens
/// point-spread function; a hot pixel is one pixel with dead-normal neighbours.
public struct StarDetector: Sendable {

    /// How many median-absolute-deviations above the background a peak must sit.
    public var threshold: Double
    /// Most stars to return, brightest first. Alignment needs a few dozen, not thousands.
    public var maxStars: Int
    /// Minimum fraction of a peak's brightness that must appear in its neighbours.
    /// A hot pixel scores near zero here; a focused star scores well above 0.3.
    public var minimumSpread: Double

    public init(threshold: Double = 5.0, maxStars: Int = 60, minimumSpread: Double = 0.25) {
        self.threshold = threshold
        self.maxStars = maxStars
        self.minimumSpread = minimumSpread
    }

    public func detect(in buffer: [Float], width: Int, height: Int) -> [StarPoint] {
        guard width > 8, height > 8, buffer.count >= width * height else { return [] }

        let (background, noise) = Self.backgroundStatistics(buffer)
        let cutoff = background + threshold * noise

        var candidates: [StarPoint] = []
        // Skip a two-pixel border: centroiding needs a full neighbourhood.
        for y in 2..<(height - 2) {
            for x in 2..<(width - 2) {
                let value = Double(buffer[y * width + x])
                guard value > cutoff else { continue }
                guard Self.isLocalMaximum(buffer, x: x, y: y, width: width, value: value) else { continue }

                let peak = value - background
                let neighbourhood = Self.neighbourhoodFlux(
                    buffer, x: x, y: y, width: width, background: background
                )
                // Everything above the peak itself has to come from somewhere real.
                let spread = (neighbourhood - peak) / max(neighbourhood, 1e-6)
                guard spread >= minimumSpread else { continue }

                if let centroid = Self.centroid(
                    buffer, x: x, y: y, width: width, background: background
                ) {
                    candidates.append(centroid)
                }
            }
        }

        return Array(candidates.sorted { $0.flux > $1.flux }.prefix(maxStars))
    }

    // MARK: - Statistics

    /// Median and a median-absolute-deviation noise estimate.
    ///
    /// Mean and standard deviation would be pulled up by the very stars being looked for;
    /// the median does not care that 0.1% of the frame is a thousand times brighter.
    static func backgroundStatistics(_ buffer: [Float]) -> (background: Double, noise: Double) {
        // Sub-sample: a background estimate does not need every pixel, and this runs once
        // per frame at capture rate.
        let stride = max(1, buffer.count / 20_000)
        var samples: [Double] = []
        samples.reserveCapacity(buffer.count / stride + 1)
        for index in Swift.stride(from: 0, to: buffer.count, by: stride) {
            samples.append(Double(buffer[index]))
        }
        guard !samples.isEmpty else { return (0, 1e-6) }

        samples.sort()
        let median = samples[samples.count / 2]

        var deviations = samples.map { abs($0 - median) }
        deviations.sort()
        // 1.4826 converts MAD to a standard-deviation equivalent for Gaussian noise.
        let noise = max(deviations[deviations.count / 2] * 1.4826, 1e-6)

        return (median, noise)
    }

    static func isLocalMaximum(_ buffer: [Float], x: Int, y: Int, width: Int, value: Double) -> Bool {
        for dy in -1...1 {
            for dx in -1...1 where dx != 0 || dy != 0 {
                if Double(buffer[(y + dy) * width + (x + dx)]) > value { return false }
            }
        }
        return true
    }

    /// Total background-subtracted brightness in a 5×5 box.
    static func neighbourhoodFlux(
        _ buffer: [Float], x: Int, y: Int, width: Int, background: Double
    ) -> Double {
        var total = 0.0
        for dy in -2...2 {
            for dx in -2...2 {
                total += max(0, Double(buffer[(y + dy) * width + (x + dx)]) - background)
            }
        }
        return total
    }

    /// Brightness-weighted centre of a 5×5 box.
    ///
    /// This is what buys sub-pixel accuracy: a star straddling two pixels lands between
    /// them, and alignment inherits that precision. Without it, registration quantises to
    /// whole pixels and stacked stars come out square.
    static func centroid(
        _ buffer: [Float], x: Int, y: Int, width: Int, background: Double
    ) -> StarPoint? {
        var weightedX = 0.0
        var weightedY = 0.0
        var total = 0.0

        for dy in -2...2 {
            for dx in -2...2 {
                let weight = max(0, Double(buffer[(y + dy) * width + (x + dx)]) - background)
                weightedX += Double(x + dx) * weight
                weightedY += Double(y + dy) * weight
                total += weight
            }
        }

        guard total > 1e-9 else { return nil }
        return StarPoint(x: weightedX / total, y: weightedY / total, flux: total)
    }
}
