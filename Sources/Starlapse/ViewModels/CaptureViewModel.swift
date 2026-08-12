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
        case finishing
        case failed(String)

        var isCapturing: Bool { self == .capturing }
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
    private(set) var previewTexture: MTLTexture?
    private(set) var capabilities: CameraCapabilities
    private(set) var plan: SkyDirector.Plan?
    private(set) var lastSavedMessage: String?

    let attitude = AttitudeProvider()

    // MARK: - Machinery

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
            let stack = StackEngine(accumulator: accumulator)
            let capture = CaptureEngine { [weak stack] frame in
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
            stack.beginLivePreview(settings: activeSettings, tone: .neutral)
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
        state.isCapturing ? settings : settings.forFraming(capabilities)
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
            stackEngine?.beginLivePreview(settings: activeSettings, tone: .neutral)
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
                self?.previewTexture = frame.texture
            }
        }

        stack.onFinished = { [weak self] image in
            Task { @MainActor in
                await self?.finishSession(final: image)
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
        stackEngine.begin(settings: settings, mode: mode, tone: tone)
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

    private func finishSession(final: RenderedImage?) async {
        guard state == .capturing else { return }
        state = .finishing

        restoreScreen()

        if mode.isTimelapse, let writer = timelapseWriter {
            if let url = await writer.finish() {
                await save(videoAt: url)
            }
            timelapseWriter = nil
        } else if let final {
            await save(image: final)
        }

        // Back to framing so the next shot can be composed straight away.
        let framing = activeSettings
        try? await captureEngine?.apply(framing)
        stackEngine?.beginLivePreview(settings: framing, tone: .neutral)
        state = .aiming
    }

    private func restoreScreen() {
        UIApplication.shared.isIdleTimerDisabled = false
        UIScreen.main.brightness = previousBrightness
    }

    // MARK: - Saving

    private func save(image rendered: RenderedImage) async {
        guard let image = rendered.makeUIImage() else {
            lastSavedMessage = "Could not render the stack."
            return
        }
        guard await requestPhotoAccess() else {
            lastSavedMessage = "Photo library access denied."
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            lastSavedMessage = "Saved \(progress.framesStacked) frames to Photos."
        } catch {
            lastSavedMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    private func save(videoAt url: URL) async {
        guard await requestPhotoAccess() else {
            lastSavedMessage = "Photo library access denied."
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            lastSavedMessage = "Saved \(progress.segmentsCompleted)-frame time-lapse to Photos."
        } catch {
            lastSavedMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    private func requestPhotoAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return status == .authorized || status == .limited
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
