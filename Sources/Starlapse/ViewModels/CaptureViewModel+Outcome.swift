import Foundation
import SuperDuperAnalytics

/// How a session ended, as one event. Before 1.2.2 the only trace of a lost time-lapse was
/// a photo saved where a video should have been, and a session that ended in a crash left
/// no trace at all: `capture_started`, then silence, the same as someone who changed their
/// mind. A failure has to be its own event with its outcome, or it cannot be counted.
extension CaptureViewModel {

    enum ReviewResult { case saved, failed }

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
        /// Second row of a `result`/`video` session: review closed without a save.
        case discarded
        /// Second row: Save was tapped and Photos refused or failed. `why` says which.
        case saveFailed = "save_failed"
    }

    /// Called once, as a session enters review.
    func reportSessionFinished() {
        reviewResult = nil
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

        track(outcome)
    }

    /// How the review ended when it did not end in Photos. Not a new session: count sessions
    /// by the outcomes above and read these as what became of a `result` or `video`.
    func reportReviewEnded(_ outcome: SessionOutcome, why: String? = nil) {
        // Saved, or a failed save already reported: the dismiss that follows is not a second row.
        if outcome == .discarded, reviewResult != nil { return }
        if outcome == .saveFailed { reviewResult = .failed }
        track(outcome, why: why)
    }

    private func track(_ outcome: SessionOutcome, why: String? = nil) {
        var props = ["mode": mode.analyticsName, "outcome": outcome.rawValue]
        if let why { props["why"] = why }
        Analytics.track(
            "capture_finished",
            props: props,
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
