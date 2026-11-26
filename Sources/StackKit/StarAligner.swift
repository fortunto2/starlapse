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

    /// The same motion with its translation multiplied by `factor`: luma-buffer pixels to
    /// full-frame pixels. Rotation does not depend on scale and passes through.
    public func translationScaled(by factor: Double) -> SimilarityTransform {
        SimilarityTransform(
            rotation: rotation, translationX: translationX * factor, translationY: translationY * factor
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
/// ICP-style: nearest-neighbour pairs from a starting guess, solved in closed form, with a
/// radius that shrinks each round. On a tripod the sky moves a couple of pixels a second and
/// the guess alone converges. In the hand it does not: a wobble of tens of pixels puts the
/// wrong star nearest, so a vote over star-to-star offsets supplies the guess first.
/// Callers align every frame to one reference frame, never to the previous one — chained
/// steps compound their error into a rotation of the whole stack.
public struct StarAligner: Sendable {

    /// How far apart two stars may be and still be considered the same star, in pixels.
    public var matchRadius: Double
    /// Fewest matched pairs that can produce a transform worth trusting.
    public var minimumMatches: Int
    public var iterations: Int
    /// The radius a pair is judged at once the solution has converged.
    public var inlierRadius: Double

    public init(matchRadius: Double = 12.0, minimumMatches: Int = 6, iterations: Int = 4, inlierRadius: Double = 3.0) {
        self.matchRadius = matchRadius
        self.minimumMatches = minimumMatches
        self.iterations = iterations
        self.inlierRadius = inlierRadius
    }

    public struct Result: Sendable {
        public let transform: SimilarityTransform
        public let matchCount: Int
        /// Root-mean-square residual in pixels over the pairs matched at the tightest radius.
        /// Above a pixel or two the frame is probably trailed by wind or a bumped tripod.
        public let residual: Double
        /// Matched pairs as a share of the smaller star list. Random coincidences inside a
        /// 3-pixel radius stay a few per cent even in a dense field; a real lock is most of it.
        public let inlierShare: Double

        public var isTrustworthy: Bool { matchCount >= 6 && residual < 3.0 && inlierShare >= 0.25 }
    }

    /// Solve for the transform carrying `moving` onto `reference`.
    ///
    /// `initialGuess` is where the frame was last seen. A hand does not drift smoothly, it
    /// wobbles by tens of pixels between frames, so when the guess leaves too few stars inside
    /// the match radius, a vote over star-to-star offsets finds the shift first. The radius
    /// then halves each iteration down to `inlierRadius`: a wide radius to converge from, a
    /// tight one to judge with, so a stray noise "star" near a real one neither pulls the
    /// solution nor inflates the residual.
    public func align(
        moving: [StarPoint],
        reference: [StarPoint],
        initialGuess: SimilarityTransform = .identity
    ) -> Result? {
        guard moving.count >= minimumMatches, reference.count >= minimumMatches else { return nil }

        var transform = initialGuess
        let needed = max(minimumMatches, min(moving.count, reference.count) / 3)
        let locked = correspondences(moving: moving, reference: reference, transform: transform, radius: inlierRadius)
        if locked.count < needed,
           let voted = Self.votedShift(moving: moving, reference: reference, guess: transform) {
            transform = voted
        }

        var lastPairs: [(StarPoint, StarPoint)] = []
        var radius = matchRadius
        for _ in 0..<iterations {
            let pairs = correspondences(moving: moving, reference: reference, transform: transform, radius: radius)
            guard pairs.count >= minimumMatches, let solved = Self.solve(pairs: pairs) else { break }
            transform = solved
            lastPairs = pairs
            radius = max(inlierRadius, radius / 2)
        }
        // Judge at the tight radius whatever the iteration count left the radius at.
        let judged = correspondences(moving: moving, reference: reference, transform: transform, radius: inlierRadius)
        if judged.count >= minimumMatches { lastPairs = judged }

        guard lastPairs.count >= minimumMatches else { return nil }

        let residual = Self.residual(pairs: lastPairs, transform: transform)
        let share = Double(lastPairs.count) / Double(min(moving.count, reference.count))
        return Result(transform: transform, matchCount: lastPairs.count, residual: residual, inlierShare: share)
    }

    /// The translation most star pairs agree on, on top of `guess`. Brightest stars only:
    /// they are the ones both frames detect, and the vote is quadratic in the count.
    static func votedShift(
        moving: [StarPoint],
        reference: [StarPoint],
        guess: SimilarityTransform,
        brightest: Int = 40,
        bin: Double = 2
    ) -> SimilarityTransform? {
        let movers = moving.sorted { $0.flux > $1.flux }.prefix(brightest).map { guess.apply(to: $0) }
        let targets = reference.sorted { $0.flux > $1.flux }.prefix(brightest)
        var votes: [SIMD2<Int32>: Int] = [:]
        for mover in movers {
            for target in targets {
                let key = SIMD2(
                    Int32(((target.x - mover.x) / bin).rounded()),
                    Int32(((target.y - mover.y) / bin).rounded())
                )
                votes[key, default: 0] += 1
            }
        }
        // A bin and its neighbours: a shift landing on a bin edge splits its votes.
        func support(_ key: SIMD2<Int32>) -> Int {
            var total = 0
            for dx in -1...1 { for dy in -1...1 { total += votes[key &+ SIMD2(Int32(dx), Int32(dy))] ?? 0 } }
            return total
        }
        guard let best = votes.keys.max(by: { support($0) < support($1) }),
              support(best) >= 4 else { return nil }
        return SimilarityTransform(
            rotation: guess.rotation,
            translationX: guess.translationX + Double(best.x) * bin,
            translationY: guess.translationY + Double(best.y) * bin
        )
    }

    /// Pair each moved star with the nearest reference star inside the match radius.
    private func correspondences(
        moving: [StarPoint],
        reference: [StarPoint],
        transform: SimilarityTransform,
        radius: Double
    ) -> [(StarPoint, StarPoint)] {
        var pairs: [(StarPoint, StarPoint)] = []
        pairs.reserveCapacity(moving.count)

        for star in moving {
            let projected = transform.apply(to: star)
            var best: StarPoint?
            var bestDistance = radius

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
