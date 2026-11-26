import Foundation
import Testing
@testable import StackKit

/// "The app works strangely in the hand, the layers seem to rotate" (26 Nov 2026).
/// The engine chained frame-to-frame alignment from an identity guess with a 12 px radius:
/// on an emulated handheld sky (wobble σ 15 px, 0.5°, 30 noise "stars" a frame) it kept
/// 93–295 of 1180 frames, and its stack corners drifted up to 9 px (quarter-res).
/// Aligned to the reference with a voted shift: 1180 of 1180, corners within 1 px.
@Suite("Handheld alignment")
struct HandheldAlignmentTests {

    struct Wobble {
        var shift: Double
        var degrees: Double
    }

    /// A random pose each frame: hands wobble around the aim, they do not drift.
    static func pose(_ wobble: Wobble, _ rng: inout SeededRandom) -> SimilarityTransform {
        SimilarityTransform(
            rotation: Double(rng.gaussian()) * wobble.degrees * .pi / 180,
            translationX: Double(rng.gaussian()) * wobble.shift,
            translationY: Double(rng.gaussian()) * wobble.shift
        )
    }

    /// What the detector sees: 85% of the stars, 0.3 px centroid noise, plus faint noise peaks.
    static func detect(
        _ sky: [StarPoint], through pose: SimilarityTransform, noise: Int, _ rng: inout SeededRandom
    ) -> [StarPoint] {
        var seen: [StarPoint] = []
        for star in sky where rng.unit() > 0.15 {
            let point = pose.apply(to: star)
            guard point.x >= 0, point.x < 480, point.y >= 0, point.y < 360 else { continue }
            seen.append(StarPoint(
                x: point.x + Double(rng.gaussian()) * 0.3,
                y: point.y + Double(rng.gaussian()) * 0.3,
                flux: star.flux * (0.8 + 0.4 * rng.unit())
            ))
        }
        for _ in 0..<noise {
            seen.append(StarPoint(x: rng.unit() * 480, y: rng.unit() * 360, flux: 0.5 + 1.5 * rng.unit()))
        }
        return seen
    }

    @Test("A shaking hand: every frame lands on the reference, the corners stay put")
    func handheldStackStaysRegistered() {
        var rng = SeededRandom(seed: 7)
        let sky = (0..<150).map { _ in
            StarPoint(x: rng.unit() * 480, y: rng.unit() * 360, flux: 1 + 20 * pow(rng.unit(), 3))
        }
        let wobble = Wobble(shift: 15, degrees: 0.5)
        let reference = Self.detect(sky, through: .identity, noise: 30, &rng)
        let aligner = StarAligner()
        let corner = StarPoint(x: 480, y: 360, flux: 1)

        var guess = SimilarityTransform.identity
        var landed = 0
        var worstCorner = 0.0
        for _ in 0..<60 {
            let truth = Self.pose(wobble, &rng)
            let frame = Self.detect(sky, through: truth, noise: 30, &rng)
            guard let step = aligner.align(moving: frame, reference: reference, initialGuess: guess),
                  step.isTrustworthy else { continue }
            guess = step.transform
            landed += 1
            let expected = truth.inverted.apply(to: corner)
            worstCorner = max(worstCorner, expected.distance(to: step.transform.apply(to: corner)))
        }
        #expect(landed >= 57)
        #expect(worstCorner < 2)
    }

    @Test("A shift beyond the match radius is found by the vote")
    func votedShiftFindsLargeWobble() {
        var rng = SeededRandom(seed: 3)
        let sky = (0..<80).map { _ in
            StarPoint(x: rng.unit() * 480, y: rng.unit() * 360, flux: 1 + 20 * pow(rng.unit(), 3))
        }
        let truth = SimilarityTransform(rotation: 0.004, translationX: 41, translationY: -27)
        let reference = Self.detect(sky, through: .identity, noise: 20, &rng)
        let frame = Self.detect(sky, through: truth, noise: 20, &rng)
        let step = StarAligner().align(moving: frame, reference: reference)
        #expect(step?.isTrustworthy == true)
        #expect(abs((step?.transform.translationX ?? 0) + 41) < 2)
        #expect(abs((step?.transform.translationY ?? 0) - 27) < 2)
    }

    /// A daylight test, 26 Nov 2026: "the frames rotate a lot", from a hand that rolled a
    /// fraction of a degree. A blown highlight read as a cluster of "stars" (60 of 60 in a
    /// 15 px patch of a real photo, `starlapse-stack align`), and a cluster pins the shift
    /// while leaving the rotation free: 8–14° solved for a 0.3° roll.
    @Test("A blown highlight is not a cluster of stars, and does not turn the stack")
    func blownHighlightDoesNotTurnTheStack() throws {
        let width = 320, height = 240
        let stars = StackingTests.starField(count: 10, width: width, height: height, seed: 5)
        func render(shiftX: Double, shiftY: Double) -> [Float] {
            let moved = stars.map {
                StackingTests.SyntheticStar(x: $0.x + shiftX, y: $0.y + shiftY, brightness: $0.brightness)
            }
            var pixels = StackingTests.renderField(stars: moved, width: width, height: height)
            // A lamp or a sunlit window: bright, wide, clipped in the middle, with a falloff.
            for y in 0..<height {
                for x in 0..<width {
                    let distance = hypot(Double(x) - 250 - shiftX, Double(y) - 60 - shiftY)
                    let glow = Float(max(0, min(1, 1.6 * (1 - distance / 16))))
                    pixels[y * width + x] = min(1, pixels[y * width + x] + glow)
                }
            }
            return pixels
        }
        let detector = StarDetector()
        let reference = detector.detect(in: render(shiftX: 0, shiftY: 0), width: width, height: height)
        let inPatch = reference.filter { hypot($0.x - 250, $0.y - 60) < 16 }
        #expect(inPatch.count <= 1)

        let moving = detector.detect(in: render(shiftX: 9, shiftY: -6), width: width, height: height)
        let step = try #require(StarAligner().align(moving: moving, reference: reference))
        #expect(abs(step.transform.rotation) * 180 / .pi < 0.2)
        #expect(abs(step.transform.translationX + 9) < 1)
        #expect(abs(step.transform.translationY - 6) < 1)
    }
}
