import Foundation

/// The lunar disc in one frame of downsampled luminance.
///
/// The Moon is the one target where the star pipeline has nothing to hold on to: it drowns
/// the stars it would align on, and the same shutter that keeps stars faint turns it into a
/// white blob. Moon mode works on the disc instead, so this is where it gets measured.
public struct MoonDisc: Sendable, Equatable {
    /// Centroid of the disc at half its peak brightness, in buffer pixels.
    public let x: Double
    public let y: Double
    /// Radius of a circle with the disc's area. For a crescent this undershoots the limb's
    /// true radius; nothing here needs the true one.
    public let radius: Double
    /// The disc's brightest level, linear: its 99th percentile, so a hot pixel does not count.
    public let peak: Double
    /// Share of the disc at or above 0.98: the part whose real brightness is unknown.
    public let clippedFraction: Double
    let minX: Int, minY: Int, maxX: Int, maxY: Int

    /// Fewest pixels a disc may cover. A star or a distant lamp is a handful of pixels; the
    /// Moon through the main lens is about 7 across in the quarter-size buffer.
    static let minimumPixels = 12
    static let clipLevel: Float = 0.98

    /// The largest bright blob in the frame, measured at half its own peak.
    ///
    /// Largest rather than brightest: a streetlight saturates as hard as the Moon and covers
    /// a fraction of the pixels. Half its own peak rather than half the frame's, so a lamp
    /// brighter than the disc cannot set the threshold the disc is measured at.
    public static func locate(in buffer: [Float], width: Int, height: Int) -> MoonDisc? {
        guard width > 2, height > 2, buffer.count >= width * height else { return nil }
        let (background, noise) = StarDetector.backgroundStatistics(buffer)
        guard let globalPeak = buffer.max(), Double(globalPeak) - background > 20 * noise else { return nil }

        let low = Float(background + max(8 * noise, 0.05 * (Double(globalPeak) - background)))
        let grid = Grid(pixels: buffer, width: width, height: height)
        guard let blob = largestBlob(in: grid, above: low),
              blob.count >= minimumPixels else { return nil }

        // The disc's level is its 99th percentile, not its maximum: one hot pixel, or a star
        // behind a thin cloud, would otherwise read as a blown-out Moon and drag the
        // exposure down by three stops at a time.
        let peakIndex = blob.max { buffer[$0] < buffer[$1] } ?? blob[0]
        let levels = blob.map { buffer[$0] }.sorted()
        let peak = Double(levels[min(levels.count - 1, levels.count * 99 / 100)])
        let half = Float(background + 0.5 * (peak - background))
        let core = flood(from: peakIndex, in: grid, above: half)
        guard core.count >= minimumPixels / 2 else { return nil }

        var sumX = 0.0, sumY = 0.0, clipped = 0
        var minX = width, minY = height, maxX = 0, maxY = 0
        for index in core {
            let px = index % width, py = index / width
            sumX += Double(px); sumY += Double(py)
            minX = min(minX, px); maxX = max(maxX, px); minY = min(minY, py); maxY = max(maxY, py)
            if buffer[index] >= clipLevel { clipped += 1 }
        }
        let count = Double(core.count)
        return MoonDisc(
            x: sumX / count, y: sumY / count, radius: (count / .pi).squareRoot(), peak: peak,
            clippedFraction: Double(clipped) / count, minX: minX, minY: minY, maxX: maxX, maxY: maxY
        )
    }

    /// How crisp the limb and the maria are: mean squared neighbour difference over the disc
    /// and a margin around it, divided by the peak squared so a brighter frame does not score
    /// sharper. Only comparable between frames of the same Moon.
    public func sharpness(in buffer: [Float], width: Int, height: Int) -> Double {
        let margin = 3
        let x0 = max(1, minX - margin), x1 = min(width - 1, maxX + margin)
        let y0 = max(1, minY - margin), y1 = min(height - 1, maxY + margin)
        guard x0 < x1, y0 < y1, peak > 0 else { return 0 }
        var energy = 0.0
        for y in y0..<y1 {
            for x in x0..<x1 {
                let here = Double(buffer[y * width + x])
                let dx = here - Double(buffer[y * width + x - 1])
                let dy = here - Double(buffer[(y - 1) * width + x])
                energy += dx * dx + dy * dy
            }
        }
        return energy / Double((x1 - x0) * (y1 - y0)) / (peak * peak)
    }

    /// A luminance buffer and its shape, so the fills below take one argument for it.
    struct Grid {
        let pixels: [Float]
        let width: Int
        let height: Int
    }

    private static func largestBlob(in grid: Grid, above level: Float) -> [Int]? {
        var seen = [Bool](repeating: false, count: grid.width * grid.height)
        var best: [Int]?
        for start in 0..<(grid.width * grid.height) where !seen[start] && grid.pixels[start] >= level {
            let blob = flood(from: start, in: grid, above: level, seen: &seen)
            if blob.count > (best?.count ?? 0) { best = blob }
        }
        return best
    }

    private static func flood(from start: Int, in grid: Grid, above level: Float) -> [Int] {
        var seen = [Bool](repeating: false, count: grid.width * grid.height)
        return flood(from: start, in: grid, above: level, seen: &seen)
    }

    /// 4-connected fill over pixels at or above `level`, iterative so a large disc cannot
    /// overflow the stack.
    private static func flood(from start: Int, in grid: Grid, above level: Float, seen: inout [Bool]) -> [Int] {
        var pending = [start]
        var blob: [Int] = []
        seen[start] = true
        while let index = pending.popLast() {
            blob.append(index)
            let x = index % grid.width, y = index / grid.width
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
            where nx >= 0 && ny >= 0 && nx < grid.width && ny < grid.height {
                let next = ny * grid.width + nx
                if !seen[next] && grid.pixels[next] >= level {
                    seen[next] = true
                    pending.append(next)
                }
            }
        }
        return blob
    }
}

/// Registers Moon frames onto the first steady one: lucky selection, then a shift that puts
/// this frame's disc centroid on the reference's.
///
/// Translation only: over the few seconds of a Moon stack the field turns by a fraction of
/// an arcminute, and the centroid fixes the shift to a fraction of a pixel.
public struct MoonTracker: Sendable {
    private var reference: MoonDisc?
    private var lucky = LuckySelector()

    public init() {}

    /// Frame-to-reference transform in luminance-buffer pixels, or nil to drop the frame:
    /// no disc in it, or softer than the median of the frames so far.
    public mutating func register(_ buffer: [Float], width: Int, height: Int) -> SimilarityTransform? {
        guard let disc = MoonDisc.locate(in: buffer, width: width, height: height),
              lucky.accepts(disc.sharpness(in: buffer, width: width, height: height))
        else { return nil }
        guard let reference else {
            reference = disc
            return .identity
        }
        return SimilarityTransform(rotation: 0, translationX: reference.x - disc.x, translationY: reference.y - disc.y)
    }
}

/// Shutter and ISO for the Moon, metered off the disc.
///
/// The Moon's brightness swings by more than six stops between a thin crescent and full, and
/// a camera meter averaging the whole frame sees mostly black sky and blows the disc out.
/// This meters the disc's own peak to a target with headroom, prefers base ISO, and only
/// raises gain once the shutter would be long enough for shake and seeing to smear the limb.
public enum MoonExposure {

    public struct Limits: Sendable, Equatable {
        public var shutter: ClosedRange<Double>
        public var iso: ClosedRange<Float>
        public init(shutter: ClosedRange<Double>, iso: ClosedRange<Float>) {
            self.shutter = shutter
            self.iso = iso
        }
    }

    /// Linear peak the disc is steered to. Highlands sit near it; the maria well below.
    public static let targetPeak = 0.7
    /// Closer than this (in stops) and nothing changes: no hunting between two frames.
    static let deadband = 0.15

    public static func next(
        shutter: Double, iso: Float, peak: Double, clippedFraction: Double, limits: Limits
    ) -> (shutter: Double, iso: Float) {
        let factor: Double
        if clippedFraction > 0.02 || peak >= Double(MoonDisc.clipLevel) {
            // A clipped disc's real brightness is unknown, so step down by a fixed three stops.
            factor = 1.0 / 8
        } else {
            guard peak > 0 else { return (shutter, iso) }
            let wanted = targetPeak / peak
            guard abs(log2(wanted)) > deadband else { return (shutter, iso) }
            factor = min(16, max(1.0 / 16, wanted))
        }

        let light = shutter * Double(iso) * factor
        let baseISO = Double(limits.iso.lowerBound)
        let newShutter = (light / baseISO).clamped(to: limits.shutter)
        let newISO = Float(light / newShutter).clamped(to: limits.iso)
        return (newShutter, newISO)
    }
}

/// Keeps the steadier half of a stream of frames: lucky imaging, as a running decision.
///
/// The stack cannot wait for the session to end and pick the best frames afterwards — it has
/// nowhere to keep them. So each frame is judged against every score seen so far, and kept
/// when it is at least as sharp as their median. The first few go in unjudged so the median
/// has something to stand on.
public struct LuckySelector: Sendable {
    private var scores: [Double] = []
    let warmup: Int

    public init(warmup: Int = 8) {
        self.warmup = warmup
    }

    public mutating func accepts(_ score: Double) -> Bool {
        defer { scores.append(score) }
        guard scores.count >= warmup else { return true }
        let sorted = scores.sorted()
        let median = sorted.count.isMultiple(of: 2)
            ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
            : sorted[sorted.count / 2]
        return score >= median
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
