import AVFoundation
import Foundation
import Metal
import os
import Photos
import SkyKit
import SwiftUI

@MainActor
@Observable
final class CaptureViewModel {

    enum SessionState: Equatable {
        case idle
        case preparing
        /// Live view for framing and focus, before committing to a session.
        case aiming
        case capturing
        /// Capture finished; the result is on screen and still adjustable.
        case reviewing
        case failed(String)

        var isCapturing: Bool { self == .capturing }
        var isReviewing: Bool { self == .reviewing }
    }

    // MARK: - User-facing state

    var settings: CaptureSettings
    var mode: CaptureMode = .still
    var tone = FrameAccumulator.ToneSettings()
    var timelapse = TimelapseSettings.default
    /// Dim the screen while capturing. On by default for battery and dark adaptation,
    /// off for anyone who wants to watch the stack build.
    var dimsScreenDuringCapture = true

    private(set) var state: SessionState = .idle
    private(set) var progress = StackProgress()
    private(set) var previewFrame: PreviewFrame?
    private(set) var capabilities: CameraCapabilities
    private(set) var plan: SkyDirector.Plan?
    private(set) var lastSavedMessage: String?
    /// Curve applied to the finished capture while reviewing it. Starts from what the
    /// session used; every change re-develops from the accumulated float32 buffer, so it
    /// costs nothing in quality no matter how far it is pushed.
    var reviewTone = FrameAccumulator.ToneSettings()
    /// Finished time-lapse awaiting a decision. Video cannot be re-toned — the frames are
    /// already encoded — so review is watch-and-keep.
    private(set) var reviewVideoURL: URL?
    /// Clips saved this session, newest first. Detector mode never interrupts to ask —
    /// it keeps watching, and these pile up until the session is stopped.
    private(set) var events: [RecordedEvent] = []

    struct RecordedEvent: Identifiable, Sendable {
        let id = UUID()
        let url: URL
        let date: Date
        let isStreak: Bool
        let angle: Double
    }

    let attitude = AttitudeProvider()

    // MARK: - Machinery

    private let captureQueue = CaptureQueue()
    private var captureEngine: CaptureEngine?
    private var stackEngine: StackEngine?
    private var accumulator: FrameAccumulator?
    private var timelapseWriter: TimelapseWriter?
    private var skyTimer: Timer?
    private var previousBrightness: CGFloat = UIScreen.main.brightness
    /// Last lens actually handed to the hardware, so a lens change can be told apart
    /// from an exposure change — the former needs a full session reconfigure.
    private var appliedLens: LensOption?
    private let logger = Logger(subsystem: "co.superduperai.starlapse", category: "session")

    init() {
        let capabilities = CaptureEngine.discoverCapabilities()
        self.capabilities = capabilities
        let lens = capabilities.fastestLens ?? LensOption(
            deviceType: .builtInWideAngleCamera,
            displayName: "Main",
            aperture: 1.78,
            fieldOfView: 70
        )
        self.settings = .default(for: lens, capabilities: capabilities)
    }

    // MARK: - Sky guidance

    /// The aiming advice, refreshed as the sky turns. Ten seconds is far more often than
    /// the sky needs, and far cheaper than the camera pipeline running beside it.
    func startSkyUpdates() {
        attitude.start()
        refreshPlan()
        skyTimer?.invalidate()
        skyTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPlan() }
        }
    }

    func stopSkyUpdates() {
        skyTimer?.invalidate()
        skyTimer = nil
        attitude.stop()
    }

    private func refreshPlan() {
        guard let location = attitude.location else { return }
        plan = SkyDirector.plan(at: location, date: Date())
    }

    /// How far, and which way, to swing the phone to hit the recommended target.
    var aimGuidance: AimGuidance? {
        guard let plan, attitude.hasFullFix else { return nil }
        return AimGuidance(from: attitude.aim, to: plan.aim.direction)
    }

    // MARK: - Camera lifecycle

    func prepare() async {
        state = .preparing

        guard await CaptureEngine.requestAuthorization() else {
            state = .failed(CameraError.authorizationDenied.localizedDescription)
            return
        }

        do {
            let accumulator = try FrameAccumulator()
            let stack = StackEngine(accumulator: accumulator, queue: captureQueue)
            let capture = CaptureEngine(queue: captureQueue) { [weak stack] frame in
                stack?.consume(frame)
            }

            wire(stack)

            self.accumulator = accumulator
            self.stackEngine = stack
            self.captureEngine = capture

            try await capture.prepare(lens: settings.lens)
            appliedLens = settings.lens
            try await capture.apply(activeSettings)

            // Framing happens before the session starts, so the sensor runs short and hot:
            // useless for stars, but it shows the horizon, trees and focus well enough to
            // compose — which a one-second frame at low ISO would not. The engine has to
            // be told to display these frames, or it drops them and the screen stays black.
            stack.begin(.framing)
            await capture.start()
            state = .aiming
        } catch {
            logger.error("Prepare failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    /// What the camera should be doing right now, derived from state rather than pushed at
    /// transition points. Framing gets short, high-gain frames; a session gets exactly what
    /// the user dialled in.
    private var activeSettings: CaptureSettings {
        guard state.isCapturing else { return settings.forFraming(capabilities) }
        // Watching needs short frames at a usable rate — an exposure long enough for a deep
        // stack would smear the meteor into the background and give three frames a second.
        if case .detector(let detector) = mode {
            var watching = settings
            watching.frameExposure = detector.frameExposure
            return watching
        }
        return settings
    }

    var detectorSettings: DetectorSettings {
        get {
            if case .detector(let settings) = mode { return settings }
            return .default
        }
        set { mode = .detector(newValue) }
    }

    /// Save every clip the detector caught.
    func saveAllEvents() async {
        guard await PhotoLibraryWriter.requestAccess() else {
            lastSavedMessage = PhotoLibraryWriter.WriteError.accessDenied.localizedDescription
            return
        }
        let saved = await PhotoLibraryWriter.write(videosAt: events.map(\.url))
        lastSavedMessage = saved == events.count
            ? "Saved \(saved) clips to Photos."
            : "Saved \(saved) of \(events.count) clips."
    }

    func clearEvents() {
        for event in events {
            try? FileManager.default.removeItem(at: event.url)
        }
        events = []
    }

    /// Push the current settings to the sensor.
    ///
    /// Called on every settings edit, not only on state transitions. Without this the lens
    /// picker was inert for the whole app lifetime — `settings.lens` was bound to a control
    /// but only ever reached the hardware inside `prepare()`.
    func settingsChanged() async {
        guard let captureEngine, state == .aiming || state.isCapturing else { return }

        if settings.lens != appliedLens {
            appliedLens = settings.lens
            try? await captureEngine.prepare(lens: settings.lens)
            stackEngine?.begin(.framing)
        }
        try? await captureEngine.apply(activeSettings)
    }

    private func wire(_ stack: StackEngine) {
        stack.onProgress = { [weak self] progress in
            Task { @MainActor in
                self?.progress = progress
            }
        }

        // Frames are pushed as they are rendered. The main actor never reaches into the
        // GPU pipeline to pull one — doing that raced with the capture queue and crashed
        // at the end of a session.
        stack.onPreviewReady = { [weak self] frame in
            Task { @MainActor in
                guard let self else {
                    // Nobody left to display it — hand the texture straight back.
                    frame.release()
                    return
                }
                self.previewFrame = frame
            }
        }

        stack.onEventRecorded = { [weak self] url, event in
            Task { @MainActor in
                guard let self else { return }
                self.events.insert(
                    RecordedEvent(url: url, date: Date(), isStreak: event.isStreak, angle: event.angle),
                    at: 0
                )
            }
        }

        stack.onFinished = { [weak self] in
            Task { @MainActor in
                await self?.enterReview()
            }
        }
    }

    // MARK: - Session

    func start() async {
        guard let captureEngine, let stackEngine else { return }

        do {
            try await captureEngine.apply(settings)
        } catch {
            state = .failed(error.localizedDescription)
            return
        }

        if case .timelapse(let timelapseSettings) = mode {
            let writer = try? TimelapseWriter(
                width: accumulator?.width ?? 1920,
                height: accumulator?.height ?? 1080,
                frameRate: timelapseSettings.outputFrameRate
            )
            timelapseWriter = writer

            // Encode inline on the capture queue that produced the texture. The writer is
            // its own queue-safe object, so the frame lands in the file before the
            // accumulator is cleared for the next segment.
            stackEngine.onSegmentReady = { texture, index in
                writer?.append(texture, frameIndex: index)
            }
        } else {
            stackEngine.onSegmentReady = nil
        }

        lastSavedMessage = nil
        let plan: SegmentPlan = switch mode {
        case .still: .still(settings, tone: tone)
        case .timelapse(let timelapseSettings): .timelapse(settings, timelapse: timelapseSettings, tone: tone)
        case .detector(let detectorSettings): .watching(detectorSettings)
        }
        stackEngine.begin(plan)
        state = .capturing

        // The screen stays on — iOS force-stops capture in the background, so there is no
        // such thing as a background astro session. Dimming is the honest substitute: the
        // session survives and the battery lasts.
        //
        // Not to 0.05, which is where this started. That was dark enough that the progress
        // readout could not be read outdoors, and a session you cannot monitor is a session
        // you cannot trust. 0.2 still saves most of the power and stays legible.
        previousBrightness = UIScreen.main.brightness
        UIApplication.shared.isIdleTimerDisabled = true
        if dimsScreenDuringCapture {
            UIScreen.main.brightness = 0.2
        }
    }

    func cancel() async {
        // The engine finishes on its own queue and calls back into `finishSession`.
        stackEngine?.cancel()
    }

    /// Capture is over. Show the result and let it be judged before anything is saved.
    ///
    /// Nothing is written to Photos automatically. An hour of sky deserves a look first,
    /// and — for a stack — the curve is still fully adjustable at this point, because the
    /// accumulator holds the summed frames rather than a developed image.
    private func enterReview() async {
        guard state == .capturing else { return }

        restoreScreen()
        lastSavedMessage = nil
        reviewTone = tone

        if mode.isTimelapse, let writer = timelapseWriter {
            reviewVideoURL = await writer.finish()
            timelapseWriter = nil
        } else {
            reviewVideoURL = nil
        }

        state = .reviewing
    }

    /// Re-develop the result with the review curve. Free and lossless — same render the
    /// session would have produced with these settings.
    func reviewToneChanged() {
        guard state.isReviewing, !mode.isTimelapse else { return }
        stackEngine?.rerender(tone: reviewTone)
    }

    /// Keep the result.
    func saveResult() async {
        guard state.isReviewing else { return }

        if let url = reviewVideoURL {
            await save(videoAt: url)
        } else if let rendered = await stackEngine?.exportResult() {
            await save(image: rendered)
        } else {
            lastSavedMessage = "Nothing to save."
        }
    }

    /// Throw it away and go back to composing.
    func dismissReview() async {
        guard state.isReviewing else { return }
        reviewVideoURL = nil
        stackEngine?.resumeFraming()
        try? await captureEngine?.apply(settings.forFraming(capabilities))
        state = .aiming
    }

    private func restoreScreen() {
        UIApplication.shared.isIdleTimerDisabled = false
        UIScreen.main.brightness = previousBrightness
    }

    // MARK: - Saving

    private func save(image rendered: RenderedImage) async {
        guard await PhotoLibraryWriter.requestAccess() else {
            lastSavedMessage = PhotoLibraryWriter.WriteError.accessDenied.localizedDescription
            return
        }
        do {
            try await PhotoLibraryWriter.write(rendered)
            lastSavedMessage = "Saved \(progress.framesStacked) frames to Photos."
        } catch {
            lastSavedMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    private func save(videoAt url: URL) async {
        guard await PhotoLibraryWriter.requestAccess() else {
            lastSavedMessage = PhotoLibraryWriter.WriteError.accessDenied.localizedDescription
            return
        }
        do {
            try await PhotoLibraryWriter.write(videoAt: url)
            lastSavedMessage = "Saved \(progress.segmentsCompleted)-frame time-lapse to Photos."
        } catch {
            lastSavedMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Derived readouts

    /// The honest translation of the requested exposure into what the hardware will do.
    var exposureExplanation: String {
        let frames = settings.frameCount
        let total = settings.totalLightSeconds
        let minutes = total / 60
        let duration = minutes >= 1
            ? String(format: "%.0f min", minutes)
            : String(format: "%.0f s", total)
        return "\(duration) of light = \(frames) × "
            + String(format: "%.2fs", settings.frameExposure)
    }

    var hardwareCeilingNote: String {
        String(
            format: "This sensor caps a single frame at %.2fs — longer exposures are stacked, not held.",
            capabilities.maxFrameExposure
        )
    }
}
