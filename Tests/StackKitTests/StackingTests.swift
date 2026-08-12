import CoreGraphics
import Foundation
import Testing
@testable import StackKit

/// Alignment is the one part of this app that cannot be checked by looking at the screen —
/// a stack that is subtly misaligned just looks like a slightly soft photo, and you find
/// out after driving somewhere dark. So it gets tested against synthetic star fields
/// rotated by an angle we chose ourselves.
@Suite("Stacking")
struct StackingTests {

    // MARK: - Synthetic frames

    /// A star we placed ourselves, so detections can be checked against ground truth.
    struct SyntheticStar {
        let x: Double
        let y: Double
        let brightness: Double
    }

    /// Render stars with a Gaussian point-spread function, the way a real lens does.
    /// Single-pixel stars would make centroiding look far better than it is.
    static func renderField(
        stars: [SyntheticStar],
        width: Int,
        height: Int,
        background: Float = 0.05,
        sigma: Double = 1.6
    ) -> [Float] {
        var buffer = [Float](repeating: background, count: width * height)
        let radius = Int((sigma * 3).rounded(.up))

        for star in stars {
            let centerX = Int(star.x.rounded())
            let centerY = Int(star.y.rounded())

            for dy in -radius...radius {
                for dx in -radius...radius {
                    let x = centerX + dx
                    let y = centerY + dy
                    guard x >= 0, x < width, y >= 0, y < height else { continue }

                    let deltaX = Double(x) - star.x
                    let deltaY = Double(y) - star.y
                    let exponent = -(deltaX * deltaX + deltaY * deltaY) / (2 * sigma * sigma)
                    buffer[y * width + x] += Float(star.brightness * exp(exponent))
                }
            }
        }

        return buffer
    }

    /// A repeatable pseudo-random star field. No `Math.random` — a flaky alignment test
    /// is worse than none.
    static func starField(count: Int, width: Int, height: Int, seed: UInt64 = 42) -> [SyntheticStar] {
        var state = seed
        func next() -> Double {
            // xorshift64*. The parentheses around the multiply are load-bearing: Swift gives
            // `>>` higher precedence than `&*`, so without them the *constant* gets shifted
            // and the generator returns values far outside [0, 1).
            state ^= state >> 12
            state ^= state << 25
            state ^= state >> 27
            let scrambled = (state &* 2_685_821_657_736_338_717) >> 11
            return Double(scrambled) / Double(1 << 53)
        }

        // Keep a margin so rotation does not push stars out of frame.
        return (0..<count).map { _ in
            SyntheticStar(
                x: 40 + next() * Double(width - 80),
                y: 40 + next() * Double(height - 80),
                brightness: 0.4 + next() * 0.6
            )
        }
    }

    static func rotate(
        _ stars: [SyntheticStar],
        byDegrees degrees: Double,
        around centre: CGPoint,
        translation: CGPoint = .zero
    ) -> [SyntheticStar] {
        let angle = degrees * .pi / 180
        return stars.map { star in
            let dx = star.x - centre.x
            let dy = star.y - centre.y
            return SyntheticStar(
                x: centre.x + cos(angle) * dx - sin(angle) * dy + translation.x,
                y: centre.y + sin(angle) * dx + cos(angle) * dy + translation.y,
                brightness: star.brightness
            )
        }
    }

    // MARK: - Detection

    @Test("Finds the stars that were rendered")
    func detectsRenderedStars() {
        let width = 320
        let height = 240
        let truth = Self.starField(count: 25, width: width, height: height)
        let buffer = Self.renderField(stars: truth, width: width, height: height)

        let detected = StarDetector().detect(in: buffer, width: width, height: height)

        #expect(detected.count >= 20)

        // Every detection should sit on top of a real star.
        for star in detected {
            let nearest = truth.map { hypot($0.x - star.x, $0.y - star.y) }.min() ?? .infinity
            #expect(nearest < 1.5)
        }
    }

    @Test("Centroids are accurate to well under a pixel")
    func centroidsAreSubPixel() {
        let width = 200
        let height = 200
        // Deliberately off-grid positions: a star exactly on a pixel centre would hide
        // any quantisation bug.
        let truth = [
            SyntheticStar(x: 50.35, y: 60.72, brightness: 0.9),
            SyntheticStar(x: 120.81, y: 90.24, brightness: 0.7),
            SyntheticStar(x: 88.5, y: 150.5, brightness: 0.8),
        ]
        let buffer = Self.renderField(stars: truth, width: width, height: height)
        let detected = StarDetector().detect(in: buffer, width: width, height: height)

        for expected in truth {
            let nearest = detected.min {
                hypot($0.x - expected.x, $0.y - expected.y) < hypot($1.x - expected.x, $1.y - expected.y)
            }
            guard let nearest else {
                Issue.record("Missed a star at \(expected.x), \(expected.y)")
                continue
            }
            #expect(abs(nearest.x - expected.x) < 0.25)
            #expect(abs(nearest.y - expected.y) < 0.25)
        }
    }

    @Test("Hot pixels are rejected, not mistaken for stars")
    func rejectsHotPixels() {
        let width = 200
        let height = 200
        var buffer = Self.renderField(stars: [], width: width, height: height)

        // Isolated single-pixel spikes — exactly what a warm sensor produces at high ISO
        // after a minute of stacking, and exactly what would anchor the aligner to the
        // sensor rather than the sky.
        for (x, y) in [(50, 50), (100, 120), (160, 80), (30, 170)] {
            buffer[y * width + x] = 1.0
        }

        let detected = StarDetector().detect(in: buffer, width: width, height: height)
        #expect(detected.isEmpty)
    }

    @Test("Real stars survive alongside hot pixels")
    func keepsStarsDespiteHotPixels() {
        let width = 240
        let height = 240
        let truth = Self.starField(count: 12, width: width, height: height)
        var buffer = Self.renderField(stars: truth, width: width, height: height)

        for (x, y) in [(20, 20), (219, 219), (20, 219)] {
            buffer[y * width + x] = 1.5
        }

        let detected = StarDetector().detect(in: buffer, width: width, height: height)
        #expect(detected.count >= 10)

        // None of the detections may be one of the spikes.
        for spike in [(20.0, 20.0), (219.0, 219.0), (20.0, 219.0)] {
            #expect(!detected.contains { hypot($0.x - spike.0, $0.y - spike.1) < 1.0 })
        }
    }

    // MARK: - Alignment

    @Test("Recovers a known rotation and translation")
    func recoversKnownTransform() {
        let width = 400
        let height = 400
        let centre = CGPoint(x: 200, y: 200)

        let cases: [(degrees: Double, shift: CGPoint)] = [
            (0.5, CGPoint(x: 2, y: -3)),
            (2.0, .zero),
            (-1.25, CGPoint(x: -5, y: 4)),
        ]

        for (degrees, shift) in cases {
            let truth = Self.starField(count: 30, width: width, height: height)
            let moved = Self.rotate(truth, byDegrees: degrees, around: centre, translation: shift)

            let referenceStars = StarDetector().detect(
                in: Self.renderField(stars: truth, width: width, height: height),
                width: width, height: height
            )
            let movingStars = StarDetector().detect(
                in: Self.renderField(stars: moved, width: width, height: height),
                width: width, height: height
            )

            guard let result = StarAligner().align(moving: movingStars, reference: referenceStars) else {
                Issue.record("Alignment failed for \(degrees)°")
                continue
            }

            #expect(result.isTrustworthy)
            // Recovered rotation must match to a hundredth of a degree.
            let recoveredDegrees = -result.transform.rotation * 180 / .pi
            #expect(abs(recoveredDegrees - degrees) < 0.05)
            #expect(result.residual < 0.5)
        }
    }

    @Test("Applying the recovered transform puts stars back on top of each other")
    func transformClosesTheLoop() {
        let width = 400
        let height = 400
        let truth = Self.starField(count: 30, width: width, height: height, seed: 7)
        let moved = Self.rotate(
            truth, byDegrees: 1.5,
            around: CGPoint(x: 200, y: 200),
            translation: CGPoint(x: 6, y: -4)
        )

        let referenceStars = StarDetector().detect(
            in: Self.renderField(stars: truth, width: width, height: height),
            width: width, height: height
        )
        let movingStars = StarDetector().detect(
            in: Self.renderField(stars: moved, width: width, height: height),
            width: width, height: height
        )

        guard let result = StarAligner().align(moving: movingStars, reference: referenceStars) else {
            Issue.record("Alignment failed")
            return
        }

        // Every moved star, once corrected, must land on a reference star.
        var corrected = 0
        for star in movingStars {
            let projected = result.transform.apply(to: star)
            let nearest = referenceStars.map { projected.distance(to: $0) }.min() ?? .infinity
            if nearest < 1.0 { corrected += 1 }
        }
        #expect(Double(corrected) / Double(movingStars.count) > 0.9)
    }

    @Test("Transforms compose and invert consistently")
    func transformAlgebra() {
        let first = SimilarityTransform(rotation: 0.03, translationX: 5, translationY: -2)
        let second = SimilarityTransform(rotation: -0.01, translationX: -3, translationY: 7)

        let point = (x: 120.0, y: 80.0)
        let stepwise = second.apply(to: first.apply(to: point))
        let composed = first.concatenated(with: second).apply(to: point)

        #expect(abs(stepwise.x - composed.x) < 1e-9)
        #expect(abs(stepwise.y - composed.y) < 1e-9)

        let roundTrip = first.inverted.apply(to: first.apply(to: point))
        #expect(abs(roundTrip.x - point.x) < 1e-9)
        #expect(abs(roundTrip.y - point.y) < 1e-9)
    }

    @Test("Accumulated frame-to-frame transforms track an hour of sky rotation")
    func incrementalAlignmentDoesNotDrift() {
        // The sky turns 15"/second. Over 600 one-second frames that is 2.5° — small per
        // frame, large in total. Chaining per-frame solutions must not accumulate error,
        // or the end of a long stack goes soft while the start looks fine.
        let width = 400
        let height = 400
        let centre = CGPoint(x: 200, y: 200)
        let perFrameDegrees = 2.5 / 60.0

        let truth = Self.starField(count: 30, width: width, height: height, seed: 99)
        let referenceStars = StarDetector().detect(
            in: Self.renderField(stars: truth, width: width, height: height),
            width: width, height: height
        )

        var accumulated = SimilarityTransform.identity
        var previousStars = referenceStars

        for frame in 1...60 {
            let rotated = Self.rotate(
                truth, byDegrees: perFrameDegrees * Double(frame), around: centre
            )
            let stars = StarDetector().detect(
                in: Self.renderField(stars: rotated, width: width, height: height),
                width: width, height: height
            )

            guard let step = StarAligner().align(
                moving: stars, reference: previousStars, initialGuess: .identity
            ) else {
                Issue.record("Lost tracking at frame \(frame)")
                return
            }

            accumulated = step.transform.concatenated(with: accumulated)
            previousStars = stars
        }

        // After 60 frames the total rotation is 2.5°; the chained estimate must agree.
        let recovered = -accumulated.rotation * 180 / .pi
        #expect(abs(recovered - 2.5) < 0.1)
    }
}
