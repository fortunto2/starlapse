import Foundation

/// Walks the lens through its range and picks the sharpest position.
///
/// A coarse pass, then a fine pass around the winner. That is how a focus sweep is done on a
/// telescope, and for the same reason: measurements are noisy and expensive — each one costs
/// a full exposure — so you spend them where the answer is, not spread evenly over a range
/// that is mostly hopeless.
///
/// Everything astronomical about focusing lives here: infinity is *not* simply
/// `lensPosition = 1.0`. That is the mechanical end stop, and on a given lens at a given
/// temperature the sharpest point sits slightly inside it. It also moves overnight as the
/// phone cools, which is why this is worth re-running rather than setting once.
public struct FocusSweep: Sendable {

    public struct Sample: Sendable, Hashable {
        public let position: Float
        public let metric: FocusMetric

        public init(position: Float, metric: FocusMetric) {
            self.position = position
            self.metric = metric
        }
    }

    /// Where to look. Stars only focus near the far end, so the sweep never visits the close
    /// half of the range — that is a third of the exposures saved for free.
    public var coarseRange: ClosedRange<Float>
    public var coarseSteps: Int
    /// Half-width of the fine pass around the coarse winner.
    public var fineRadius: Float
    public var fineSteps: Int

    public init(
        coarseRange: ClosedRange<Float> = 0.55...1.0,
        coarseSteps: Int = 10,
        fineRadius: Float = 0.06,
        fineSteps: Int = 6
    ) {
        self.coarseRange = coarseRange
        self.coarseSteps = coarseSteps
        self.fineRadius = fineRadius
        self.fineSteps = fineSteps
    }

    /// Lens positions for the first pass.
    public func coarsePositions() -> [Float] {
        positions(in: coarseRange, count: coarseSteps)
    }

    /// Lens positions for the second pass, given where the first one landed.
    public func finePositions(around best: Float) -> [Float] {
        let lower = max(coarseRange.lowerBound, best - fineRadius)
        let upper = min(coarseRange.upperBound, best + fineRadius)
        guard lower < upper else { return [best] }
        return positions(in: lower...upper, count: fineSteps)
    }

    private func positions(in range: ClosedRange<Float>, count: Int) -> [Float] {
        guard count > 1 else { return [range.lowerBound] }
        let step = (range.upperBound - range.lowerBound) / Float(count - 1)
        return (0..<count).map { range.lowerBound + Float($0) * step }
    }

    /// Best position from a set of samples.
    ///
    /// When three or more usable samples bracket the minimum, a parabola through the best
    /// point and its neighbours locates the true bottom between them — the lens is
    /// continuous, so the sharpest focus almost never falls exactly on a sampled position.
    public func bestPosition(from samples: [Sample]) -> Float? {
        let usable = samples.filter(\.metric.isUsable).sorted { $0.position < $1.position }
        guard let best = usable.min(by: { $0.metric.sharper(than: $1.metric) }) else { return nil }
        guard let index = usable.firstIndex(of: best),
              index > 0, index < usable.count - 1 else { return best.position }

        let left = usable[index - 1]
        let right = usable[index + 1]

        // Vertex of the parabola through the three points.
        let leftValue = left.metric.halfFluxDiameter
        let middleValue = best.metric.halfFluxDiameter
        let rightValue = right.metric.halfFluxDiameter
        let denominator = leftValue - 2 * middleValue + rightValue
        guard abs(denominator) > 1e-9 else { return best.position }

        let offset = 0.5 * (leftValue - rightValue) / denominator
        // A vertex outside the bracket means the samples are noise, not a curve.
        guard abs(offset) <= 1 else { return best.position }

        let spacing = right.position - left.position
        return best.position + Float(offset) * spacing / 2
    }
}
