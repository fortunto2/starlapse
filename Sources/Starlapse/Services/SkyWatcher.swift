import CoreVideo
import Foundation
import os
import StackKit

/// Watches for things crossing the sky and films them.
///
/// Split out of `StackEngine` because it is a different machine wearing the same name:
/// stacking builds one picture out of many frames, watching keeps a rolling window and
/// throws almost all of it away. They shared a class and a set of mutually exclusive
/// fields, which is how the stacking path's tone and stack mode ended up silently ignored
/// on watching plans.
///
/// Deliberately knows nothing about Metal. It is handed a luminance buffer and a pixel
/// buffer, and it answers what to do — which is also what makes the decision logic
/// testable without a GPU.
final class SkyWatcher: @unchecked Sendable {

    /// What the watcher concluded about this frame.
    enum Step {
        /// Nothing to do.
        case waiting
        /// A clip was written.
        case recorded(URL, Transient)
        /// A trigger turned out to be an aircraft or satellite; nothing was written.
        case discarded
    }

    private enum State {
        /// Ready for something to happen.
        case armed
        /// Filming: gathering the post-roll before writing the clip.
        case recording(Transient, framesLeft: Int, recurrences: Int)
        /// Just wrote something; ignoring the afterglow.
        case cooling(framesLeft: Int)
    }

    private let settings: DetectorSettings
    private let detector = TransientDetector()
    private let ring: FrameRingBuffer
    private let logger = Logger(subsystem: "co.superduperai.starlapse", category: "watch")

    private var state = State.armed
    private var previousLuminance: [Float]?
    private var clipsWritten = 0

    /// Frames after a bright event that may still carry its afterglow.
    private static let cooldownFrames = 2
    /// Recurrences during the post-roll that mean "still up there and moving".
    private static let persistenceThreshold = 2

    init(settings: DetectorSettings) {
        self.settings = settings
        ring = FrameRingBuffer(frames: settings.ringFrames)
    }

    var eventsRecorded: Int { clipsWritten }

    /// Take one frame. Returns what happened, so the caller can report it.
    func consume(
        _ frame: SensorFrame,
        luminance: [Float],
        width: Int,
        height: Int
    ) -> Step {
        // Always buffering. The clip has to start before the trigger, because by the time
        // anything has noticed a meteor it is already over.
        ring.append(frame.pixelBuffer, timestamp: frame.timestamp)

        let event = currentTransient(luminance: luminance, width: width, height: height)
        previousLuminance = luminance

        switch state {
        case .cooling(let framesLeft):
            state = framesLeft <= 1 ? .armed : .cooling(framesLeft: framesLeft - 1)
            return .waiting

        case .recording(let pending, let framesLeft, let recurrences):
            // Keep looking during the post-roll: something still crossing the frame is not
            // a meteor. The post-roll is already a wait-and-see period, so this costs
            // nothing extra.
            let seen = recurrences + (event != nil ? 1 : 0)

            guard framesLeft <= 1 else {
                state = .recording(pending, framesLeft: framesLeft - 1, recurrences: seen)
                return .waiting
            }

            state = .cooling(framesLeft: Self.cooldownFrames)

            // One recurrence can be afterglow from a bright meteor. Two means it is an
            // aircraft or a satellite — without this, one plane came back as twenty
            // near-identical clips, which on a real night is most of the output.
            if seen >= Self.persistenceThreshold {
                logger.info("Discarded a persistent streak — aircraft or satellite")
                return .discarded
            }
            guard let url = writeClip() else { return .waiting }
            return .recorded(url, pending)

        case .armed:
            guard let event else { return .waiting }
            state = .recording(event, framesLeft: settings.postRollFrames, recurrences: 0)
            return .waiting
        }
    }

    /// Whether this frame shows something worth reacting to.
    private func currentTransient(luminance: [Float], width: Int, height: Int) -> Transient? {
        guard let previous = previousLuminance else { return nil }
        guard let event = detector.detect(
            current: luminance, previous: previous, width: width, height: height
        ) else { return nil }

        // Streak-only rejects lens flares and distant lamps switching on; turning it off
        // keeps those, along with satellite glints and lightning.
        guard !settings.streaksOnly || event.isStreak else { return nil }
        return event
    }

    private func writeClip() -> URL? {
        let frames = ring.history()
        guard let first = frames.first else { return nil }

        let url = ClipWriter.clipURL(index: clipsWritten, timestamp: first.timestamp)
        guard let written = ClipWriter.write(
            frames: frames, frameRate: settings.outputFrameRate, to: url
        ) else {
            logger.error("Failed to write event clip")
            return nil
        }

        clipsWritten += 1
        logger.info("Recorded event \(self.clipsWritten): \(frames.count) frames")
        return written
    }
}
