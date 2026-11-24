import Foundation
import SuperDuperAnalytics

/// How a session ended, as one event. Before 1.2.2 the only trace of a lost time-lapse was
/// a photo saved where a video should have been, and a session that ended in a crash left
/// no trace at all: `capture_started`, then silence, the same as someone who changed their
/// mind. A failure has to be its own event with its outcome, or it cannot be counted.
extension CaptureViewModel {

    enum SessionOutcome: String {
        /// A still or a detector run with something to review.
        case result
        /// Nothing was stacked: stopped before the first frame landed.
        case empty
        /// Time-lapse with a playable clip.
        case video
        /// Time-lapse that produced frames but no clip: the encoder lost it.
        case noVideo = "no_video"
        /// Found at launch: the previous session never reached review.
        case interrupted
    }

    /// Called once, as a session enters review.
    func reportSessionFinished() {
        let outcome: SessionOutcome
        if mode.isTimelapse {
            if reviewVideoURL != nil {
                outcome = .video
            } else if progress.segmentsCompleted > 0 {
                outcome = .noVideo
            } else {
                outcome = .empty
            }
        } else {
            outcome = progress.framesStacked > 0 || progress.eventsRecorded > 0 ? .result : .empty
        }

        if mode.isTimelapse, outcome != .video {
            lastSavedMessage = outcome == .empty
                ? String(localized: "No video: the session ended before the first time-lapse frame.")
                : String(localized: "The video could not be written. The stacked image is kept instead.")
        }

        Analytics.track(
            "capture_finished",
            props: ["mode": mode.analyticsName, "outcome": outcome.rawValue],
            metrics: [
                "minutes": (Date().timeIntervalSince(sessionStartedAt) / 60).rounded(),
                "frames": Double(progress.framesStacked),
                "segments": Double(progress.segmentsCompleted),
                "encoder_failures": Double(reviewEncoderFailures),
            ]
        )
    }

    /// The previous run left time-lapse files behind: its session never ended. Sent once per
    /// launch that finds them, with how many.
    static func reportInterrupted(clips: Int) {
        guard clips > 0 else { return }
        Analytics.track(
            "capture_finished",
            props: ["mode": "timelapse", "outcome": SessionOutcome.interrupted.rawValue],
            metrics: ["clips": Double(clips)]
        )
    }
}
