import Foundation

/// How sharp the stars are in one frame.
///
/// Astronomical focusing does not use contrast the way a daylight autofocus does — there is
/// almost no contrast in a night sky to hill-climb on. It uses the *size of the stars*: a
/// star is a point source, so the tighter its image, the better the focus. Every observatory
/// on Earth focuses this way, and the phone has everything needed to do it.
public struct FocusMetric: Sendable, Hashable {
    /// Half-flux diameter, in pixels: the diameter of the circle containing half the star's
    /// light. Lower is sharper.
    ///
    /// HFD rather than the more familiar FWHM because it degrades gracefully. Badly
    /// defocused stars turn into donuts with a dip in the middle, where fitting a width to
    /// the peak becomes meaningless — but the radius holding half the light stays perfectly
    /// well-defined, which is exactly the regime a focus sweep starts in.
    public let halfFluxDiameter: Double
    /// How many stars the measurement is based on.
    public let sampleCount: Double

    /// Nothing measurable in frame.
    public static let none = FocusMetric(halfFluxDiameter: .infinity, sampleCount: 0)

    public var isUsable: Bool { sampleCount >= 3 && halfFluxDiameter.isFinite }

    /// Sharper of the two, treating an unusable reading as infinitely soft.
    public func sharper(than other: FocusMetric) -> Bool {
        guard isUsable else { return false }
        guard other.isUsable else { return true }
        return halfFluxDiameter < other.halfFluxDiameter
    }
}

/// Measures star sharpness, for focusing by starlight.
public struct FocusEvaluator: Sendable {

    private let detector: StarDetector
    /// Box half-width around each star, in pixels. Wide enough to contain a defocused disc.
    private let window: Int

    public init(detector: StarDetector = StarDetector(maxStars: 25), window: Int = 9) {
        self.detector = detector
        self.window = window
    }

    /// Measure the frame. Returns `.none` when too few stars are visible to trust.
    public func measure(_ buffer: [Float], width: Int, height: Int) -> FocusMetric {
        let stars = detector.detect(in: buffer, width: width, height: height)
        guard stars.count >= 3 else { return .none }

        let (background, _) = StarDetector.backgroundStatistics(buffer)

        // Median rather than mean: one satellite trail or a hot column would drag an average
        // and send the sweep to the wrong end.
        var diameters: [Double] = []
        diameters.reserveCapacity(stars.count)

        for star in stars {
            if let hfd = halfFluxDiameter(
                around: star, in: buffer, width: width, height: height, background: background
            ) {
                diameters.append(hfd)
            }
        }

        guard diameters.count >= 3 else { return .none }
        diameters.sort()

        return FocusMetric(
            halfFluxDiameter: diameters[diameters.count / 2],
            sampleCount: Double(diameters.count)
        )
    }

    /// Half-flux diameter of one star: twice the flux-weighted mean distance from its centre.
    ///
    /// The weighted-mean-radius form is the standard estimator — it avoids searching for a
    /// radius by iteration, and gives the same answer for a Gaussian profile up to a
    /// constant factor, which is all a comparison between focus positions needs.
    private func halfFluxDiameter(
        around star: StarPoint,
        in buffer: [Float],
        width: Int,
        height: Int,
        background: Double
    ) -> Double? {
        let centreX = Int(star.x.rounded())
        let centreY = Int(star.y.rounded())
        guard centreX >= window, centreX < width - window,
              centreY >= window, centreY < height - window else { return nil }

        var weightedRadius = 0.0
        var totalFlux = 0.0

        for dy in -window...window {
            for dx in -window...window {
                let value = Double(buffer[(centreY + dy) * width + (centreX + dx)]) - background
                guard value > 0 else { continue }
                let offsetX = Double(centreX + dx) - star.x
                let offsetY = Double(centreY + dy) - star.y
                let distance = (offsetX * offsetX + offsetY * offsetY).squareRoot()
                weightedRadius += value * distance
                totalFlux += value
            }
        }

        guard totalFlux > 1e-9 else { return nil }
        return 2.0 * weightedRadius / totalFlux
    }
}
