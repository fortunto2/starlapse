import Foundation

/// Something that appeared in the sky between one frame and the next.
public struct Transient: Sendable, Hashable {
    /// Centre of the brightened region, in buffer coordinates.
    public let x: Double
    public let y: Double
    /// Pixels involved.
    public let pixelCount: Int
    /// Total brightness above the previous frame.
    public let flux: Double
    /// Length of the long axis divided by the short one. A meteor is a streak, so this is
    /// well above 1; a defocused blob or a passing cloud edge is close to 1.
    public let elongation: Double
    /// Direction of the long axis in degrees — the streak's bearing across the frame.
    public let angle: Double

    /// Looks like a meteor rather than a blob.
    public var isStreak: Bool { elongation >= 2.5 }
}

/// Finds things that brighten suddenly, by comparing a frame against the one before it.
///
/// The comparison is only meaningful because frames are registered on the stars first: with
/// the sky held still, anything that moves or appears is a candidate by definition. Without
/// registration every star would light up this detector on every frame.
///
/// What it must *not* fire on is most of what a night sky actually does:
///
/// - **Clouds, headlights, the Moon rising** brighten a large fraction of the frame. Capped
///   by `maximumPixels`.
/// - **Hot pixels and cosmic ray hits** are one or two pixels. Floored by `minimumPixels`.
/// - **Aircraft and satellites** are real streaks, and this detector will happily flag them.
///   They are separated by persistence instead — they appear in frame after frame, a meteor
///   in one — which is the caller's job, not this function's.
public struct TransientDetector: Sendable {

    /// How many noise sigmas above the frame-to-frame difference counts as brightening.
    public var threshold: Double
    /// Below this, it is sensor noise rather than sky.
    public var minimumPixels: Int
    /// Above this fraction of the frame, it is weather or a light source, not an event.
    public var maximumFraction: Double
    /// How much brighter the region must get, relative to what was already shining there.
    ///
    /// This is what separates an event from a fluctuation, and it is the single most useful
    /// test in this file. A meteor lands on empty sky: the previous frame held background,
    /// so the ratio is huge. A star scintillating in the atmosphere varies by a few percent
    /// of its own brightness, in a place that was already bright — ratio near zero. Without
    /// this, forty twinkling stars set off the detector on every frame.
    public var minimumContrast: Double

    public init(
        threshold: Double = 6.0,
        minimumPixels: Int = 12,
        maximumFraction: Double = 0.05,
        minimumContrast: Double = 0.5
    ) {
        self.threshold = threshold
        self.minimumPixels = minimumPixels
        self.maximumFraction = maximumFraction
        self.minimumContrast = minimumContrast
    }

    /// Compare two registered luminance buffers of the same size.
    public func detect(
        current: [Float],
        previous: [Float],
        width: Int,
        height: Int
    ) -> Transient? {
        guard width > 4, height > 4,
              current.count >= width * height,
              previous.count >= width * height else { return nil }

        // Difference image. Only brightening matters — something fading is a cloud passing
        // off a star, not an event.
        var difference = [Float](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            difference[index] = max(0, current[index] - previous[index])
        }

        let (background, noise) = StarDetector.backgroundStatistics(difference)
        let cutoff = background + threshold * noise

        // A single connected region, not every bright pixel in the frame.
        //
        // Summing the whole frame at once was the first version, and it fired on
        // scintillation: forty stars twinkling by a few percent add up to a thousand
        // brightened pixels, which looked exactly like one large event. It also made the
        // centroid meaningless whenever more than one thing changed. An event is one thing
        // in one place, so the detector has to answer "one place" first.
        guard let region = largestRegion(in: difference, width: width, height: height, cutoff: cutoff) else {
            return nil
        }

        let maximumPixels = Int(Double(width * height) * maximumFraction)
        guard region.pixels.count >= minimumPixels,
              region.pixels.count <= maximumPixels else { return nil }

        // Did something appear, or did something that was already there merely change?
        var gained = 0.0
        var alreadyThere = 0.0
        for index in region.pixels {
            gained += Double(difference[index])
            alreadyThere += Double(previous[index])
        }
        guard gained > minimumContrast * alreadyThere else { return nil }

        guard let shape = measure(
            region: region, difference: difference, width: width, background: background
        ) else { return nil }

        return Transient(
            x: shape.centreX,
            y: shape.centreY,
            pixelCount: region.pixels.count,
            flux: shape.flux,
            elongation: shape.elongation,
            angle: shape.angle
        )
    }

    private struct Shape {
        let centreX: Double
        let centreY: Double
        let flux: Double
        let elongation: Double
        let angle: Double
    }

    /// Brightness-weighted centre and second moments of a region.
    ///
    /// The second moments are what tell a meteor from a blob: a streak's covariance matrix
    /// has one large eigenvalue and one small one, a round glow has two similar ones.
    private func measure(
        region: Region,
        difference: [Float],
        width: Int,
        background: Double
    ) -> Shape? {
        var sumX = 0.0
        var sumY = 0.0
        var flux = 0.0

        for index in region.pixels {
            let weight = Double(difference[index]) - background
            guard weight > 0 else { continue }
            sumX += Double(index % width) * weight
            sumY += Double(index / width) * weight
            flux += weight
        }
        guard flux > 0 else { return nil }

        let centreX = sumX / flux
        let centreY = sumY / flux

        var mxx = 0.0
        var myy = 0.0
        var mxy = 0.0

        for index in region.pixels {
            let weight = Double(difference[index]) - background
            guard weight > 0 else { continue }
            let deltaX = Double(index % width) - centreX
            let deltaY = Double(index / width) - centreY
            mxx += weight * deltaX * deltaX
            myy += weight * deltaY * deltaY
            mxy += weight * deltaX * deltaY
        }

        mxx /= flux
        myy /= flux
        mxy /= flux

        let trace = mxx + myy
        let determinant = mxx * myy - mxy * mxy
        let discriminant = max(0, trace * trace / 4 - determinant).squareRoot()
        let major = (trace / 2 + discriminant).squareRoot()
        // Floor the minor axis: a perfectly thin line would divide by zero.
        let minor = max((trace / 2 - discriminant).squareRoot(), 0.35)

        return Shape(
            centreX: centreX,
            centreY: centreY,
            flux: flux,
            elongation: major / minor,
            angle: 0.5 * atan2(2 * mxy, mxx - myy) * 180 / .pi
        )
    }

    private struct Region {
        var pixels: [Int]
    }

    /// Largest 8-connected group of pixels above the cutoff.
    ///
    /// Eight-connected rather than four: a meteor crossing the frame diagonally is a
    /// one-pixel-wide line whose pixels touch only at their corners, and four-connectivity
    /// would shatter it into dozens of fragments — none of them big enough to report.
    private func largestRegion(
        in difference: [Float],
        width: Int,
        height: Int,
        cutoff: Double
    ) -> Region? {
        var visited = [Bool](repeating: false, count: width * height)
        var best: Region?
        var stack: [Int] = []

        for start in 0..<(width * height) {
            guard !visited[start], Double(difference[start]) > cutoff else { continue }

            visited[start] = true
            stack.removeAll(keepingCapacity: true)
            stack.append(start)
            var pixels: [Int] = []

            while let index = stack.popLast() {
                pixels.append(index)
                let x = index % width
                let y = index / width

                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx
                        let ny = y + dy
                        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                        let neighbour = ny * width + nx
                        guard !visited[neighbour],
                              Double(difference[neighbour]) > cutoff else { continue }
                        visited[neighbour] = true
                        stack.append(neighbour)
                    }
                }
            }

            if pixels.count > (best?.pixels.count ?? 0) {
                best = Region(pixels: pixels)
            }
        }

        return best
    }
}
