import CoreGraphics
import Foundation
import Testing
@testable import StackKit

/// Focusing is the one thing you cannot check by looking at a phone screen in the dark —
/// a star that is one pixel too fat looks identical to a sharp one at arm's length, and you
/// find out when the stack comes back soft. So the sweep is tested against synthetic frames
/// rendered at a known blur, where the right answer is a number we chose.
@Suite("Focus")
struct FocusTests {

    static let width = 300
    static let height = 240

    /// A star field at a given blur. Sigma stands in for defocus: the further the lens is
    /// from the sharp position, the wider each star spreads.
    static func frame(sigma: Double, seed: UInt64 = 31) -> [Float] {
        let stars = StackingTests.starField(count: 26, width: width, height: height, seed: seed)
        return StackingTests.renderField(
            stars: stars, width: width, height: height, sigma: sigma
        )
    }

    /// Blur as a function of lens position, peaking sharp at `best`. Stands in for the
    /// optics during a simulated sweep.
    static func sigma(at position: Float, best: Float = 0.87) -> Double {
        let distance = abs(Double(position - best))
        return 1.1 + distance * 26
    }

    // MARK: - The metric

    @Test("Sharper frames measure smaller")
    func metricFollowsBlur() {
        let evaluator = FocusEvaluator()
        var previous = 0.0

        for sigma in [1.1, 1.6, 2.4, 3.4] {
            let metric = evaluator.measure(
                Self.frame(sigma: sigma), width: Self.width, height: Self.height
            )
            #expect(metric.isUsable, "no reading at sigma \(sigma)")
            #expect(metric.halfFluxDiameter > previous, "not monotonic at sigma \(sigma)")
            previous = metric.halfFluxDiameter
        }
    }

    @Test("An empty frame yields no reading rather than a wrong one")
    func emptyFrameIsUnusable() {
        let blank = [Float](repeating: 0.05, count: Self.width * Self.height)
        let metric = FocusEvaluator().measure(blank, width: Self.width, height: Self.height)
        #expect(!metric.isUsable)
        // And it must lose every comparison, so a sweep never picks a blank frame.
        let real = FocusEvaluator().measure(
            Self.frame(sigma: 3.0), width: Self.width, height: Self.height
        )
        #expect(!metric.sharper(than: real))
        #expect(real.sharper(than: metric))
    }

    // MARK: - The sweep

    @Test("The sweep only looks where stars can focus")
    func sweepSkipsTheCloseHalf() {
        let positions = FocusSweep().coarsePositions()
        #expect(positions.allSatisfy { $0 >= 0.5 })
        #expect(positions.contains { $0 > 0.95 })
        #expect(positions.count >= 8)
    }

    @Test("A simulated sweep finds the true focus position")
    func sweepConverges() {
        let truth: Float = 0.87
        let sweep = FocusSweep()
        let evaluator = FocusEvaluator()

        func sample(_ position: Float) -> FocusSweep.Sample {
            FocusSweep.Sample(
                position: position,
                metric: evaluator.measure(
                    Self.frame(sigma: Self.sigma(at: position, best: truth)),
                    width: Self.width, height: Self.height
                )
            )
        }

        let coarse = sweep.coarsePositions().map(sample)
        guard let roughBest = sweep.bestPosition(from: coarse) else {
            Issue.record("Coarse pass found nothing")
            return
        }
        // The coarse grid is 0.05 apart, so this is as close as it can get.
        #expect(abs(roughBest - truth) < 0.06)

        let fine = sweep.finePositions(around: roughBest).map(sample)
        guard let best = sweep.bestPosition(from: coarse + fine) else {
            Issue.record("Fine pass found nothing")
            return
        }
        #expect(abs(best - truth) < 0.02)
    }

    @Test("Interpolation lands between samples, not on one")
    func interpolatesTheMinimum() {
        // A symmetric bracket with the true minimum halfway between two samples: the answer
        // must not be either sample. The lens is continuous; the grid is not.
        let samples = [
            FocusSweep.Sample(position: 0.80, metric: FocusMetric(halfFluxDiameter: 6.0, sampleCount: 20)),
            FocusSweep.Sample(position: 0.85, metric: FocusMetric(halfFluxDiameter: 3.0, sampleCount: 20)),
            FocusSweep.Sample(position: 0.90, metric: FocusMetric(halfFluxDiameter: 4.0, sampleCount: 20)),
        ]
        guard let best = FocusSweep().bestPosition(from: samples) else {
            Issue.record("No result")
            return
        }
        #expect(best > 0.85 && best < 0.90)
    }

    @Test("Unusable samples are ignored, not averaged in")
    func ignoresUnusableSamples() {
        // Clouds drift through a sweep and take the stars with them. Those readings must not
        // drag the answer.
        let samples = [
            FocusSweep.Sample(position: 0.70, metric: .none),
            FocusSweep.Sample(position: 0.80, metric: FocusMetric(halfFluxDiameter: 5.0, sampleCount: 12)),
            FocusSweep.Sample(position: 0.88, metric: FocusMetric(halfFluxDiameter: 2.2, sampleCount: 14)),
            FocusSweep.Sample(position: 0.95, metric: .none),
            FocusSweep.Sample(position: 1.00, metric: FocusMetric(halfFluxDiameter: 4.8, sampleCount: 11)),
        ]
        guard let best = FocusSweep().bestPosition(from: samples) else {
            Issue.record("No result")
            return
        }
        #expect(abs(best - 0.88) < 0.05)
    }

    @Test("A sweep that sees nothing reports nothing")
    func noStarsMeansNoAnswer() {
        let samples = (0..<6).map {
            FocusSweep.Sample(position: 0.6 + Float($0) * 0.08, metric: .none)
        }
        #expect(FocusSweep().bestPosition(from: samples) == nil)
    }
}
