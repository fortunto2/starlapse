import Foundation
import SkyKit
import SwiftUI

/// How far the camera is off target, and which way to swing it.
///
/// A named type rather than a tuple because it crosses from the view model into the
/// overlay and is read at arm's length in the dark — `guidance.altitude` says what it is,
/// `error.1` does not.
struct AimGuidance: Sendable, Equatable {
    /// Signed degrees to turn horizontally. Positive means clockwise, to the right.
    let azimuth: Double
    /// Signed degrees to tilt. Positive means raise the phone.
    let altitude: Double
    /// Great-circle distance to the target, degrees.
    let separation: Double

    /// Close enough that pointing more precisely gains nothing — the field of view of even
    /// the telephoto lens is far wider than this.
    var isOnTarget: Bool { separation <= 6 }

    init(from current: HorizontalCoordinates, to target: HorizontalCoordinates) {
        azimuth = (target.azimuth - current.azimuth).signedDegrees
        altitude = target.altitude - current.altitude
        separation = target.separation(from: current)
    }

    /// Spoken-word instruction: "right 24° · up 12°".
    var instruction: String {
        var parts: [String] = []
        if abs(azimuth) > 3 {
            parts.append(String(format: "%@ %.0f°", azimuth > 0 ? "right" : "left", abs(azimuth)))
        }
        if abs(altitude) > 3 {
            parts.append(String(format: "%@ %.0f°", altitude > 0 ? "up" : "down", abs(altitude)))
        }
        return parts.isEmpty ? "on target" : parts.joined(separator: " · ")
    }

    /// Rotation for an arrow that points along the shortest path to the target.
    var arrowAngle: Angle { .radians(atan2(azimuth, altitude)) }
}
