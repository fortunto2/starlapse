import Foundation
import SkyKit
import StackKit

/// One meteor, in the sky rather than in the frame: what a visual observer reports to the
/// IMO, and what a second phone's record of the same meteor would need for a trajectory.
public struct MeteorObservation: Sendable, Hashable, Codable {
    public let date: Date
    public let startAzimuth: Double
    public let startAltitude: Double
    public let endAzimuth: Double
    public let endAltitude: Double
    /// Degrees of sky the streak covered.
    public let length: Double
    /// IMO code of the shower whose radiant the streak points back to, or nil: sporadic.
    public let shower: String?
    /// Brightness above the previous frame, in the detector's linear units. Relative only:
    /// a magnitude needs the frame's zero point, which `SkyMeter` gives once a plate solves.
    public let flux: Double
}

public enum MeteorAstrometry {

    /// A detected streak, placed on the sky through `pointing`.
    ///
    /// The detector gives the centre, the axis and the elongation of the changed pixels.
    /// For a streak `long × short` pixels with `long / short = e` and area `n`, the long
    /// axis is √(n·e). Which end is the start is not known from one frame, so the pair is
    /// ordered so the radiant, when there is one, lies behind the start.
    public static func observe(
        _ transient: Transient, frame: LumaImage.Size, pointing: CameraPointing, moment: SkyMoment
    ) -> MeteorObservation {
        let half = (Double(transient.pixelCount) * max(transient.elongation, 1)).squareRoot() / 2
        let axis = transient.angle.radians
        let first = pointing.direction(
            x: transient.x - half * cos(axis), y: transient.y - half * sin(axis),
            width: frame.width, height: frame.height
        )
        let second = pointing.direction(
            x: transient.x + half * cos(axis), y: transient.y + half * sin(axis),
            width: frame.width, height: frame.height
        )
        let match = shower(through: first, and: second, moment: moment)
        let (start, end) = match?.reversed == true ? (second, first) : (first, second)
        return MeteorObservation(
            date: moment.date,
            startAzimuth: start.azimuth, startAltitude: start.altitude,
            endAzimuth: end.azimuth, endAltitude: end.altitude,
            length: first.separation(from: second),
            shower: match?.code, flux: transient.flux
        )
    }

    /// The active shower whose radiant the streak's great circle passes closest to,
    /// within `tolerance` degrees, with the radiant outside the streak on the side it came
    /// from. `reversed` says the radiant is behind `second`, not `first`.
    public static func shower(
        through first: HorizontalCoordinates, and second: HorizontalCoordinates, moment: SkyMoment,
        tolerance: Double = 8
    ) -> (code: String, reversed: Bool)? {
        let start = unit(first)
        let end = unit(second)
        let normal = cross(start, end)
        let normalLength = length(normal)
        guard normalLength > 1e-9 else { return nil }

        struct Candidate {
            let code: String
            let reversed: Bool
            let distance: Double
        }
        var best: Candidate?
        for candidate in MeteorShower.active(on: moment.date) {
            let radiantSky = candidate.radiant.horizontal(at: moment.location, date: moment.date)
            guard radiantSky.altitude > -5 else { continue }
            let radiant = unit(radiantSky)
            let offCircle = asin(min(1, abs(dot(normal, radiant)) / normalLength)).degrees
            guard offCircle <= tolerance else { continue }
            // Behind one end and not between them: a meteor travels away from its radiant.
            let toFirst = radiantSky.separation(from: first)
            let toSecond = radiantSky.separation(from: second)
            let span = first.separation(from: second)
            guard min(toFirst, toSecond) + span <= max(toFirst, toSecond) + 2 else { continue }
            if offCircle < (best?.distance ?? .infinity) {
                best = Candidate(code: candidate.code, reversed: toSecond < toFirst, distance: offCircle)
            }
        }
        return best.map { ($0.code, $0.reversed) }
    }

    static func unit(_ direction: HorizontalCoordinates) -> SIMD3<Double> {
        let azimuth = direction.azimuth.radians
        let altitude = direction.altitude.radians
        return SIMD3(cos(altitude) * cos(azimuth), cos(altitude) * sin(azimuth), sin(altitude))
    }

    static func cross(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(lhs.y * rhs.z - lhs.z * rhs.y, lhs.z * rhs.x - lhs.x * rhs.z, lhs.x * rhs.y - lhs.y * rhs.x)
    }

    static func dot(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>) -> Double {
        lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z
    }

    static func length(_ vector: SIMD3<Double>) -> Double { dot(vector, vector).squareRoot() }
}
