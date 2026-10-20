import Foundation
import SkyKit
import StackKit

/// A catalogue star found in the frame.
public struct MatchedStar: Sendable, Hashable {
    public let star: CatalogStar
    public let horizontal: HorizontalCoordinates
    public let pixel: StarPoint
}

/// Which detected stars are which catalogue stars.
///
/// The phone's own idea of where it points is good to a few degrees in azimuth (the
/// compass) and well under that in altitude and roll (gravity). A few degrees is a
/// hundred pixels, far beyond the radius a nearest-neighbour match can trust, so the
/// first step is a vote: every pairing of a bright detected star with a bright predicted
/// one proposes an offset, and the true offset is the one most pairings agree on. Small
/// rotations and focal-length errors are searched the same way. Then a similarity fit
/// (scale, rotation, shift) tightens it over every star that lines up.
public struct PlateMatch: Sendable {

    /// Predicted pixel → measured pixel.
    public struct Correction: Sendable, Hashable {
        /// scale × cos(rotation) and scale × sin(rotation).
        public var scaledCos: Double
        public var scaledSin: Double
        public var shiftX: Double
        public var shiftY: Double
        public static let identity = Correction(scaledCos: 1, scaledSin: 0, shiftX: 0, shiftY: 0)

        public func apply(_ point: (x: Double, y: Double)) -> (x: Double, y: Double) {
            (scaledCos * point.x - scaledSin * point.y + shiftX, scaledSin * point.x + scaledCos * point.y + shiftY)
        }

        /// Measured pixel → predicted pixel, so `CameraPointing.direction` can be asked.
        public func invert(_ point: (x: Double, y: Double)) -> (x: Double, y: Double) {
            let x = point.x - shiftX
            let y = point.y - shiftY
            let norm = scaledCos * scaledCos + scaledSin * scaledSin
            return ((scaledCos * x + scaledSin * y) / norm, (-scaledSin * x + scaledCos * y) / norm)
        }

        public var scale: Double { (scaledCos * scaledCos + scaledSin * scaledSin).squareRoot() }
        public var rotationDegrees: Double { atan2(scaledSin, scaledCos).degrees }
    }

    public let matches: [MatchedStar]
    public let correction: Correction
    /// RMS distance of the matches after the fit, in pixels.
    public let residual: Double
    /// The pointing the stars say the phone had: what the compass should have read.
    public let pointing: CameraPointing

    public var isTrustworthy: Bool { matches.count >= 8 && residual < 3 }

    struct Predicted {
        let star: CatalogStar
        let horizontal: HorizontalCoordinates
        let x: Double
        let y: Double
    }

    /// How hard to look.
    public struct Options: Sendable {
        public var magnitudeLimit = 6.5
        /// The whole circle by default: the sensor buffer is landscape however the phone
        /// is held, and which way its top points is cheaper to search than to derive.
        public var rotations = Array(stride(from: -180.0, through: 177.0, by: 3.0))
        public init() {}
    }

    /// Catalogue stars that should be in the frame, brightest first.
    static func predicted(
        pointing: CameraPointing, moment: SkyMoment, width: Int, height: Int, magnitudeLimit: Double
    ) -> [Predicted] {
        let margin = 0.15 * Double(width)
        let reach = pointing.horizontalFieldOfView * 0.9 + 10
        return StarCatalog.stars
            .filter { $0.magnitude <= magnitudeLimit }
            .compactMap { star -> Predicted? in
                let horizontal = star.position.horizontal(at: moment.location, date: moment.date)
                guard horizontal.altitude > 3,
                      horizontal.separation(from: pointing.center) < reach,
                      let pixel = pointing.project(horizontal, width: width, height: height),
                      pixel.x > -margin, pixel.x < Double(width) + margin,
                      pixel.y > -margin, pixel.y < Double(height) + margin
                else { return nil }
                return Predicted(star: star, horizontal: horizontal, x: pixel.x, y: pixel.y)
            }
            .sorted { $0.star.magnitude < $1.star.magnitude }
    }

    public static func solve(
        detected: [StarPoint], pointing: CameraPointing, moment: SkyMoment,
        width: Int, height: Int, options: Options = Options()
    ) -> PlateMatch? {
        guard detected.count >= 8 else { return nil }
        var pointing = pointing
        var catalog = predicted(
            pointing: pointing, moment: moment, width: width, height: height, magnitudeLimit: options.magnitudeLimit
        )
        guard catalog.count >= 8 else { return nil }
        let brightDetected = Array(detected.sorted { $0.flux > $1.flux }.prefix(30))
        guard var correction = vote(
            detected: brightDetected, catalog: Array(catalog.prefix(45)), width: width, height: height,
            rotations: options.rotations
        ) else { return nil }

        // A wrong pointing is not a similarity in pixels: a few degrees off-axis changes the
        // perspective across a 70° field. So the fit is folded back into the pointing and the
        // catalogue re-projected, until what is left is a similarity near the identity.
        var pairs: [(Predicted, StarPoint)] = []
        for radius in [0.02, 0.012, 0.006, 0.004, 0.004].map({ $0 * Double(width) }) {
            pairs = nearest(catalog: catalog, detected: detected, correction: correction, radius: radius)
            guard pairs.count >= 4 else { return nil }
            pointing = refined(pointing, by: fit(pairs), width: width, height: height)
            catalog = predicted(
                pointing: pointing, moment: moment, width: width, height: height,
                magnitudeLimit: options.magnitudeLimit
            )
            correction = .identity
        }
        pairs = nearest(catalog: catalog, detected: detected, correction: .identity, radius: 0.004 * Double(width))
        guard pairs.count >= 4 else { return nil }
        correction = fit(pairs)
        return PlateMatch(
            matches: pairs.map { MatchedStar(star: $0.0.star, horizontal: $0.0.horizontal, pixel: $0.1) },
            correction: correction, residual: rms(pairs, correction: correction), pointing: pointing
        )
    }

    /// The pointing that would have predicted what `correction` says was measured.
    static func refined(
        _ pointing: CameraPointing, by correction: Correction, width: Int, height: Int
    ) -> CameraPointing {
        // Two measured points, the centre and one straight above it, and the directions the
        // old pointing says they look at. The new pointing is whatever puts them back there.
        //
        // Reading roll off the fit's rotation instead was wrong whenever the centre moved
        // sideways: away from the horizon, a few degrees of azimuth also turn the field
        // (the meridians converge toward the zenith), so the fit's rotation is partly the
        // move itself. Subtracting all of it as roll sent a 6° compass error at 45° up to a
        // false solution — 18 of 150 stars matched and the roll 3.5° out. Projecting a
        // second point counts the move once.
        let cx = Double(width) / 2
        let cy = Double(height) / 2
        let step = 0.25 * Double(width)
        let centre = correction.invert((cx, cy))
        let above = correction.invert((cx, cy - step))
        var next = CameraPointing(
            center: pointing.direction(x: centre.x, y: centre.y, width: width, height: height),
            roll: 0,
            horizontalFieldOfView: pointing.horizontalFieldOfView
        )
        let up = pointing.direction(x: above.x, y: above.y, width: width, height: height)
        guard let drawn = next.project(up, width: width, height: height) else { return pointing }
        let vx = drawn.x - cx
        let vy = cy - drawn.y
        next.roll = (90 - atan2(vy, vx).degrees).signedDegrees
        let focal = next.focalLength(width: width) * step / hypot(vx, vy)
        next.horizontalFieldOfView = 2 * atan(Double(width) / 2 / focal).degrees
        return next
    }

    /// The rotation, scale and shift most star pairings agree on.
    static func vote(
        detected: [StarPoint], catalog: [Predicted], width: Int, height: Int, rotations: [Double]
    ) -> Correction? {
        let cell = 0.012 * Double(width)
        let cx = Double(width) / 2
        let cy = Double(height) / 2
        var best: (votes: Int, correction: Correction) = (0, .identity)

        for rotation in rotations {
            for scale in stride(from: 0.88, through: 1.12, by: 0.04) {
                let cosine = scale * cos(rotation.radians)
                let sine = scale * sin(rotation.radians)
                // Rotate and scale about the frame centre, then let the shift be voted.
                let base = Correction(
                    scaledCos: cosine, scaledSin: sine,
                    shiftX: cx - cosine * cx + sine * cy, shiftY: cy - sine * cx - cosine * cy
                )
                var bins: [Int: Bin] = [:]
                for entry in catalog {
                    let moved = base.apply((entry.x, entry.y))
                    for star in detected {
                        let dx = star.x - moved.x
                        let dy = star.y - moved.y
                        let key = Int((dx / cell).rounded()) &* 100_003 &+ Int((dy / cell).rounded())
                        bins[key, default: Bin()].add(dx: dx, dy: dy)
                    }
                }
                guard let top = bins.values.max(by: { $0.count < $1.count }), top.count > best.votes
                else { continue }
                var shifted = base
                shifted.shiftX += top.sumX / Double(top.count)
                shifted.shiftY += top.sumY / Double(top.count)
                best = (top.count, shifted)
            }
        }
        return best.votes >= 5 ? best.correction : nil
    }

    struct Bin {
        var count = 0
        var sumX = 0.0
        var sumY = 0.0

        mutating func add(dx: Double, dy: Double) {
            count += 1
            sumX += dx
            sumY += dy
        }
    }

    static func nearest(
        catalog: [Predicted], detected: [StarPoint], correction: Correction, radius: Double
    ) -> [(Predicted, StarPoint)] {
        var used = Set<Int>()
        var pairs: [(Predicted, StarPoint)] = []
        for entry in catalog {
            let moved = correction.apply((entry.x, entry.y))
            var bestIndex: Int?
            var bestDistance = radius
            for (index, star) in detected.enumerated() where !used.contains(index) {
                let distance = hypot(star.x - moved.x, star.y - moved.y)
                if distance < bestDistance {
                    bestDistance = distance
                    bestIndex = index
                }
            }
            if let bestIndex {
                used.insert(bestIndex)
                pairs.append((entry, detected[bestIndex]))
            }
        }
        return pairs
    }

    /// Least-squares similarity from predicted to measured pixels.
    static func fit(_ pairs: [(Predicted, StarPoint)]) -> Correction {
        let count = Double(pairs.count)
        let px = pairs.map(\.0.x).reduce(0, +) / count
        let py = pairs.map(\.0.y).reduce(0, +) / count
        let qx = pairs.map(\.1.x).reduce(0, +) / count
        let qy = pairs.map(\.1.y).reduce(0, +) / count
        var dot = 0.0
        var cross = 0.0
        var norm = 0.0
        for (predicted, measured) in pairs {
            let ux = predicted.x - px
            let uy = predicted.y - py
            let vx = measured.x - qx
            let vy = measured.y - qy
            dot += ux * vx + uy * vy
            cross += ux * vy - uy * vx
            norm += ux * ux + uy * uy
        }
        guard norm > 0 else { return .identity }
        let cosine = dot / norm
        let sine = cross / norm
        return Correction(
            scaledCos: cosine, scaledSin: sine,
            shiftX: qx - (cosine * px - sine * py), shiftY: qy - (sine * px + cosine * py)
        )
    }

    static func rms(_ pairs: [(Predicted, StarPoint)], correction: Correction) -> Double {
        guard !pairs.isEmpty else { return .infinity }
        let total = pairs.reduce(0.0) { sum, pair in
            let moved = correction.apply((pair.0.x, pair.0.y))
            let distance = hypot(pair.1.x - moved.x, pair.1.y - moved.y)
            return sum + distance * distance
        }
        return (total / Double(pairs.count)).squareRoot()
    }
}
