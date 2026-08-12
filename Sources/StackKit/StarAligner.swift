import Foundation
import simd

/// A rotation about the frame centre plus a translation. Scale is fixed at 1 — the sky
/// does not zoom, and letting scale float would let a bad match quietly shrink the stack.
public struct SimilarityTransform: Sendable, Hashable {
    /// Radians, counter-clockwise.
    public var rotation: Double
    public var translationX: Double
    public var translationY: Double

    public static let identity = SimilarityTransform(rotation: 0, translationX: 0, translationY: 0)

    public init(rotation: Double, translationX: Double, translationY: Double) {
        self.rotation = rotation
        self.translationX = translationX
        self.translationY = translationY
    }

    public func apply(to point: (x: Double, y: Double)) -> (x: Double, y: Double) {
        let cosine = cos(rotation)
        let sine = sin(rotation)
        return (
            x: cosine * point.x - sine * point.y + translationX,
            y: sine * point.x + cosine * point.y + translationY
        )
    }

    public func apply(to star: StarPoint) -> StarPoint {
        let moved = apply(to: (star.x, star.y))
        return StarPoint(x: moved.x, y: moved.y, flux: star.flux)
    }

    /// This transform followed by `next`.
    public func concatenated(with next: SimilarityTransform) -> SimilarityTransform {
        let moved = next.apply(to: (translationX, translationY))
        return SimilarityTransform(
            rotation: rotation + next.rotation,
            translationX: moved.x,
            translationY: moved.y
        )
    }

    public var inverted: SimilarityTransform {
        let cosine = cos(-rotation)
        let sine = sin(-rotation)
        return SimilarityTransform(
            rotation: -rotation,
            translationX: -(cosine * translationX - sine * translationY),
            translationY: -(sine * translationX + cosine * translationY)
        )
    }

    /// As a 3×3 matrix, ready to hand to a shader.
    public var matrix: simd_float3x3 {
        let cosine = Float(cos(rotation))
        let sine = Float(sin(rotation))
        return simd_float3x3(rows: [
            SIMD3(cosine, -sine, Float(translationX)),
            SIMD3(sine, cosine, Float(translationY)),
            SIMD3(0, 0, 1),
        ])
    }
}

/// Registers one frame's stars onto another's.
///
/// Deliberately an ICP-style loop rather than triangle-pattern matching. Between
/// consecutive frames the sky moves by a hair — it turns 15 arcseconds per second, which
/// over a one-second frame is a couple of pixels — so nearest-neighbour matching from a
/// good starting guess converges immediately and never needs to solve the hard global
/// problem. The accumulated transform carries the guess forward across the whole session.
public struct StarAligner: Sendable {

    /// How far apart two stars may be and still be considered the same star, in pixels.
    public var matchRadius: Double
    /// Fewest matched pairs that can produce a transform worth trusting.
    public var minimumMatches: Int
    public var iterations: Int

    public init(matchRadius: Double = 12.0, minimumMatches: Int = 6, iterations: Int = 3) {
        self.matchRadius = matchRadius
        self.minimumMatches = minimumMatches
        self.iterations = iterations
    }

    public struct Result: Sendable {
        public let transform: SimilarityTransform
        public let matchCount: Int
        /// Root-mean-square residual in pixels. Above a pixel or two the frame is probably
        /// trailed by wind or a bumped tripod and is better dropped than stacked.
        public let residual: Double

        public var isTrustworthy: Bool { matchCount >= 6 && residual < 3.0 }
    }

    /// Solve for the transform carrying `moving` onto `reference`.
    /// `initialGuess` should be the previous frame's answer; the sky's motion is smooth.
    public func align(
        moving: [StarPoint],
        reference: [StarPoint],
        initialGuess: SimilarityTransform = .identity
    ) -> Result? {
        guard moving.count >= minimumMatches, reference.count >= minimumMatches else { return nil }

        var transform = initialGuess
        var lastPairs: [(StarPoint, StarPoint)] = []

        for _ in 0..<iterations {
            let pairs = correspondences(moving: moving, reference: reference, transform: transform)
            guard pairs.count >= minimumMatches else { break }

            guard let solved = Self.solve(pairs: pairs) else { break }
            transform = solved
            lastPairs = pairs
        }

        guard lastPairs.count >= minimumMatches else { return nil }

        let residual = Self.residual(pairs: lastPairs, transform: transform)
        return Result(transform: transform, matchCount: lastPairs.count, residual: residual)
    }

    /// Pair each moved star with the nearest reference star inside the match radius.
    private func correspondences(
        moving: [StarPoint],
        reference: [StarPoint],
        transform: SimilarityTransform
    ) -> [(StarPoint, StarPoint)] {
        var pairs: [(StarPoint, StarPoint)] = []
        pairs.reserveCapacity(moving.count)

        for star in moving {
            let projected = transform.apply(to: star)
            var best: StarPoint?
            var bestDistance = matchRadius

            for candidate in reference {
                let distance = projected.distance(to: candidate)
                if distance < bestDistance {
                    bestDistance = distance
                    best = candidate
                }
            }

            if let best {
                pairs.append((star, best))
            }
        }

        return pairs
    }

    /// Closed-form least-squares rotation and translation for matched 2D point sets
    /// (the 2D case of Kabsch/Umeyama). No iteration, no local minima — the optimal
    /// rotation falls straight out of an arctangent over the cross- and dot-products.
    static func solve(pairs: [(StarPoint, StarPoint)]) -> SimilarityTransform? {
        guard pairs.count >= 2 else { return nil }

        let count = Double(pairs.count)
        let movingCentre = pairs.reduce(into: (x: 0.0, y: 0.0)) { total, pair in
            total.x += pair.0.x
            total.y += pair.0.y
        }
        let referenceCentre = pairs.reduce(into: (x: 0.0, y: 0.0)) { total, pair in
            total.x += pair.1.x
            total.y += pair.1.y
        }
        let movingMean = (x: movingCentre.x / count, y: movingCentre.y / count)
        let referenceMean = (x: referenceCentre.x / count, y: referenceCentre.y / count)

        var crossProduct = 0.0
        var dotProduct = 0.0
        for (moving, reference) in pairs {
            let mx = moving.x - movingMean.x
            let my = moving.y - movingMean.y
            let rx = reference.x - referenceMean.x
            let ry = reference.y - referenceMean.y
            crossProduct += mx * ry - my * rx
            dotProduct += mx * rx + my * ry
        }

        guard abs(crossProduct) > 1e-12 || abs(dotProduct) > 1e-12 else { return nil }

        let rotation = atan2(crossProduct, dotProduct)
        let cosine = cos(rotation)
        let sine = sin(rotation)

        return SimilarityTransform(
            rotation: rotation,
            translationX: referenceMean.x - (cosine * movingMean.x - sine * movingMean.y),
            translationY: referenceMean.y - (sine * movingMean.x + cosine * movingMean.y)
        )
    }

    static func residual(pairs: [(StarPoint, StarPoint)], transform: SimilarityTransform) -> Double {
        guard !pairs.isEmpty else { return .infinity }
        var total = 0.0
        for (moving, reference) in pairs {
            let projected = transform.apply(to: moving)
            let dx = projected.x - reference.x
            let dy = projected.y - reference.y
            total += dx * dx + dy * dy
        }
        return (total / Double(pairs.count)).squareRoot()
    }
}
