import Foundation
import SkyKit

/// What the stars say the sensors got wrong, applied to everything the overlay draws.
///
/// The compass is good to a few degrees in azimuth, and a few degrees is a hundred points
/// on screen: the markers sit beside their stars, not on them. A plate solve of a live
/// frame knows the true pointing to a fraction of a pixel. The difference between the two,
/// taken while the phone is steady, is the sensors' bias, and a bias stays put while the
/// phone moves — so the gyro keeps the overlay smooth and the stars keep it honest.
///
/// It corrects four things: heading (the compass), altitude and roll (small gravity
/// errors), and the field of view (the lens's published figure against what it shows).
public struct SkyLock: Sendable, Equatable {
    public var azimuthOffset: Double
    public var altitudeOffset: Double
    public var rollOffset: Double
    /// Solved field across the width ÷ the field the geometry assumed.
    public var fieldScale: Double
    public var matchedStars: Int
    public var solvedAt: Date

    /// How long a lock is trusted without a fresh solve. Compass bias drifts slowly as the
    /// phone warms or moves near metal; ten minutes is well inside that.
    public static let lifetime: TimeInterval = 600

    /// - Parameters:
    ///   - assumed: the pointing the overlay would have used, from the sensors.
    ///   - solved: the pointing the stars gave for the same frame.
    public init(assumed: CameraPointing, solved: CameraPointing, matchedStars: Int, at date: Date) {
        azimuthOffset = (solved.center.azimuth - assumed.center.azimuth).signedDegrees
        altitudeOffset = solved.center.altitude - assumed.center.altitude
        rollOffset = (solved.roll - assumed.roll).signedDegrees
        fieldScale = solved.horizontalFieldOfView / assumed.horizontalFieldOfView
        self.matchedStars = matchedStars
        solvedAt = date
    }

    public func isFresh(at date: Date) -> Bool {
        date.timeIntervalSince(solvedAt) < Self.lifetime
    }

    /// A sensor reading, corrected.
    public func apply(aim: HorizontalCoordinates, roll: Double) -> (aim: HorizontalCoordinates, roll: Double) {
        let azimuth = (aim.azimuth + azimuthOffset).truncatingRemainder(dividingBy: 360)
        return (
            HorizontalCoordinates(
                azimuth: azimuth < 0 ? azimuth + 360 : azimuth,
                altitude: min(90, max(-90, aim.altitude + altitudeOffset))
            ),
            roll + rollOffset
        )
    }

    /// Whether a solve is worth taking as the new lock. The solver's own bar, plus a sanity
    /// limit: a "correction" of more than 25° is a mismatch, not a compass error.
    public static func accepts(_ match: PlateMatch, assumed: CameraPointing) -> Bool {
        match.isTrustworthy && match.pointing.center.separation(from: assumed.center) < 25
    }
}
