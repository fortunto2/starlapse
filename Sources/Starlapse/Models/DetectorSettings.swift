import Foundation

/// Watch the sky and keep only the moments something happened.
///
/// The tripod stands there for hours; you are asleep, or looking the other way. What comes
/// back is a handful of two-second clips with the event in the middle of each — which is
/// both what a reel wants and what an observation report needs.
struct DetectorSettings: Sendable, Equatable {
    /// Seconds kept before the trigger. The whole point: a meteor is over before anything
    /// could react to it, so the clip has to start in the past.
    var preRoll: TimeInterval
    /// Seconds recorded after the trigger.
    var postRoll: TimeInterval
    /// Exposure per frame. Longer collects more light and draws the meteor as a longer
    /// streak; shorter gives smoother video. A quarter second is a reasonable middle.
    var frameExposure: Double
    /// Frames per second in the saved clip. Sped up from the capture rate — the sky moves
    /// slowly and nobody wants a two-second clip that plays for eight.
    var outputFrameRate: Int
    /// Ignore anything that is not streak-shaped. On for meteors; off if you also want
    /// flares, satellites glinting and lightning.
    var streaksOnly: Bool

    static let `default` = DetectorSettings(
        preRoll: 1.5,
        postRoll: 1.0,
        frameExposure: 0.25,
        outputFrameRate: 12,
        streaksOnly: true
    )

    var captureFrameRate: Double { 1.0 / max(frameExposure, 0.01) }

    /// How many frames the ring holds.
    var preRollFrames: Int { max(2, Int((preRoll * captureFrameRate).rounded())) }
    var postRollFrames: Int { max(1, Int((postRoll * captureFrameRate).rounded())) }

    /// Length of the finished clip once sped up.
    var clipDuration: TimeInterval {
        Double(preRollFrames + postRollFrames) / Double(max(outputFrameRate, 1))
    }

    var summary: String {
        String(
            format: "%.1fs before + %.1fs after → %.1fs clip at %d fps",
            preRoll, postRoll, clipDuration, outputFrameRate
        )
    }

    var warning: String? {
        if clipDuration < 0.8 {
            return "Clip under a second. Lengthen the windows or lower the output frame rate."
        }
        if frameExposure > 0.5 {
            return "Long frames blur the meteor into the background between exposures."
        }
        return nil
    }
}

/// A saved event, with everything needed to report it later.
///
/// Written alongside the clip from the start, even though nothing consumes it yet: time,
/// place and direction are what turn a nice video into an observation, and they cannot be
/// recovered afterwards.
struct DetectionRecord: Sendable, Codable {
    let date: Date
    let latitude: Double?
    let longitude: Double?
    /// Where the camera was pointed, degrees.
    let azimuth: Double?
    let altitude: Double?
    /// Field of view of the lens used, degrees — needed to turn pixels into angles.
    let fieldOfView: Double
    /// Direction of the streak across the frame, degrees.
    let streakAngle: Double
    let elongation: Double
    let pixelCount: Int
    /// Shower whose radiant was up and best matches, if any.
    let likelyShower: String?
    let clipFilename: String
}
