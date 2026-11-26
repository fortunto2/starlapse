import Foundation
import StackKit

/// `starlapse-stack align <photo>`: a daytime scene shaken the way a hand shakes it, run
/// through the detector and aligner the way `StackEngine.track` runs them. The true motion
/// is known, so a rotation the aligner invents is a number, not an impression.
enum AlignProbe {

    struct Outcome {
        var accepted = 0, dropped = 0
        var worstRotationError = 0.0, worstCornerError = 0.0
    }

    /// Bilinear resample of `source` under `motion` (reference → frame), plus sensor noise.
    static func frame(_ source: PhotoLuma, motion: SimilarityTransform, noise: Float, seed: inout UInt64) -> [Float] {
        let inverse = motion.inverted
        var out = [Float](repeating: 0, count: source.width * source.height)
        for y in 0..<source.height {
            for x in 0..<source.width {
                let at = inverse.apply(to: (Double(x), Double(y)))
                let x0 = Int(floor(at.x)), y0 = Int(floor(at.y))
                guard x0 >= 0, y0 >= 0, x0 + 1 < source.width, y0 + 1 < source.height else { continue }
                let fx = Float(at.x - Double(x0)), fy = Float(at.y - Double(y0))
                let row = y0 * source.width + x0, below = row + source.width
                let top = source.pixels[row] + (source.pixels[row + 1] - source.pixels[row]) * fx
                let bottom = source.pixels[below] + (source.pixels[below + 1] - source.pixels[below]) * fx
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let jitter = (Float(seed >> 40) / Float(1 << 24) - 0.5) * 2 * noise
                out[y * source.width + x] = max(0, top + (bottom - top) * fy + jitter)
            }
        }
        return out
    }

    static func run(_ source: PhotoLuma, frames: Int, shake: Double, roll: Double, verbose: Bool) -> Outcome {
        let detector = StarDetector()
        let aligner = StarAligner()
        var seed: UInt64 = 7
        var outcome = Outcome()
        let reference = detector.detect(in: source.pixels, width: source.width, height: source.height)
        var guess = SimilarityTransform.identity
        let corners = [(0.0, 0.0), (Double(source.width), 0), (0, Double(source.height)),
                       (Double(source.width), Double(source.height))]
        print("reference stars \(reference.count) on \(source.width)×\(source.height)")
        if verbose {
            for star in reference.prefix(60) { print(String(format: "  %.0f,%.0f", star.x, star.y), terminator: "") }
            print()
        }
        for index in 1...frames {
            // A hand: a wander of tens of pixels, a roll of a fraction of a degree.
            let t = Double(index)
            let truth = SimilarityTransform(
                rotation: roll * .pi / 180 * sin(t * 0.37),
                translationX: shake * sin(t * 0.73) + shake * 0.4 * sin(t * 2.1),
                translationY: shake * cos(t * 0.59) + shake * 0.3 * sin(t * 1.7)
            )
            let pixels = frame(source, motion: truth, noise: 0.004, seed: &seed)
            let stars = detector.detect(in: pixels, width: source.width, height: source.height)
            // The aligner solves frame → reference, the inverse of the motion drawn.
            let expected = truth.inverted
            guard let result = aligner.align(moving: stars, reference: reference, initialGuess: guess),
                  result.isTrustworthy else {
                outcome.dropped += 1
                if verbose { print("\(index)\tdropped\tstars \(stars.count)") }
                continue
            }
            guess = result.transform
            outcome.accepted += 1
            let rotationError = abs(result.transform.rotation - expected.rotation) * 180 / .pi
            let cornerError = corners.map { corner in
                let solved = result.transform.apply(to: corner), truth = expected.apply(to: corner)
                return hypot(solved.x - truth.x, solved.y - truth.y)
            }.max() ?? 0
            outcome.worstRotationError = max(outcome.worstRotationError, rotationError)
            outcome.worstCornerError = max(outcome.worstCornerError, cornerError)
            let truthPairs = stars.filter { star in
                let landed = expected.apply(to: star)
                return reference.contains { hypot($0.x - landed.x, $0.y - landed.y) < 3 }
            }.count
            if verbose {
                print("\ttruth would pair \(truthPairs)")
                print(String(
                    format: "%d\tstars %d\tmatched %d share %.2f res %.2f\trot %.3f° (true %.3f°)\tcorner err %.1f px",
                    index, stars.count, result.matchCount, result.inlierShare, result.residual,
                    result.transform.rotation * 180 / .pi, expected.rotation * 180 / .pi, cornerError
                ))
            }
        }
        print(String(
            format: "accepted %d dropped %d · worst rotation error %.2f° · worst corner error %.1f px",
            outcome.accepted, outcome.dropped, outcome.worstRotationError, outcome.worstCornerError
        ))
        return outcome
    }
}
