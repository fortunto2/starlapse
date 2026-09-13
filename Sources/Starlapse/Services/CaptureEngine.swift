import AVFoundation
import CoreMedia
import Foundation
import os

/// The AVFoundation layer, owned by one serial queue.
///
/// `@unchecked Sendable` is a deliberate choice, not a shortcut. `AVCaptureSession` and
/// `AVCaptureDevice` are queue-confined by design and predate actors; wrapping them in an
/// actor would suspend on every blocking `startRunning()` and buy nothing. Instead every
/// mutation runs on `queue`, which is the discipline AVFoundation itself documents.
final class CaptureEngine: @unchecked Sendable {

    private let captureQueue: CaptureQueue
    private var queue: DispatchQueue { captureQueue.dispatch }
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let logger = Logger(subsystem: "co.superduperai.starlapse", category: "capture")

    private var device: AVCaptureDevice?
    private var receiver: FrameReceiver?
    #if DEBUG
    private var stubSky: StubSkySource?
    private var stubTimer: DispatchSourceTimer?
    private var stubFrameIndex = 0
    #endif

    /// Called on the capture queue for every frame. Must consume the buffer synchronously.
    private let onFrame: @Sendable (SensorFrame) -> Void

    /// Which format to ask the sensor for.
    ///
    /// Stacking and watching want opposite things. A stack wants every photon and every
    /// pixel, once a second. Watching wants a few frames a second, for hours, and every
    /// frame gets copied into a ring buffer — at 12 MP that is 48 MB a frame, ~300 MB
    /// resident and 200 MB/s of memcpy for a session meant to run all night.
    enum FormatPreference: Sendable {
        /// Longest possible single exposure, highest resolution that allows it.
        case longExposure
        /// Modest resolution at a usable frame rate, so a ring buffer is affordable.
        case detector
    }

    init(queue: CaptureQueue, onFrame: @escaping @Sendable (SensorFrame) -> Void) {
        self.captureQueue = queue
        self.onFrame = onFrame
    }

    // MARK: - Authorization

    static func requestAuthorization() async -> Bool {
        #if DEBUG
        // The Simulator has no camera to authorise, and the stub sky does not need one.
        if ProcessInfo.processInfo.environment["UITEST_SKY"] == "1" { return true }
        #endif
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    // MARK: - Configuration

    func prepare(lens: LensOption, preference: FormatPreference = .longExposure) async throws {
        try await captureQueue.perform { [self] in
            try configure(lens: lens, preference: preference)
        }
    }

    /// Two steps on purpose, and the split is the whole fix.
    ///
    /// All of this used to happen inside one `beginConfiguration`/`commitConfiguration`
    /// transaction, including the choice of sensor format. That put the one decision that
    /// differs between iPhone models inside the one operation whose refusal cannot be
    /// caught: on an iPhone 17 the commit raised, and an uncaught NSException is the
    /// process dying a fifth of a second after launch. The crash reports named
    /// `-[AVCaptureSession commitConfiguration]` on three devices.
    ///
    /// So the transaction now contains only what every iPhone ever made supports — an
    /// input, an output and a connection — and the format is chosen afterwards, against a
    /// session that is already live, where "no" is an error with a next candidate rather
    /// than a crash.
    private func configure(lens: LensOption, preference: FormatPreference) throws {
        #if DEBUG
        if ProcessInfo.processInfo.environment["UITEST_SKY"] == "1" { return }
        #endif
        guard let device = AVCaptureDevice.default(lens.deviceType, for: .video, position: .back) else {
            throw CameraError.noCameraAvailable
        }

        try buildGraph(around: device)
        self.device = device
        selectFormat(on: device, preference: preference)
    }

    /// The parts of a capture session that are the same on every iPhone.
    private func buildGraph(around device: AVCaptureDevice) throws {
        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()

        // .inputPriority keeps the session from overriding activeFormat back to something
        // convenient for FaceTime. Without it every exposure setting below gets reverted.
        session.sessionPreset = .inputPriority

        for existing in session.inputs { session.removeInput(existing) }
        guard session.canAddInput(input) else {
            Hardware.attempt("commit empty session") { session.commitConfiguration() }
            throw CameraError.configurationFailed("input rejected")
        }
        session.addInput(input)

        if !session.outputs.contains(output) {
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            // Never drop: an hour of stacking is a fixed budget of photons, and a skipped
            // frame is light that does not come back.
            output.alwaysDiscardsLateVideoFrames = false
            guard session.canAddOutput(output) else {
                Hardware.attempt("commit session without output") { session.commitConfiguration() }
                throw CameraError.configurationFailed("output rejected")
            }
            session.addOutput(output)
        }

        let receiver = FrameReceiver(onFrame: onFrame)
        self.receiver = receiver
        output.setSampleBufferDelegate(receiver, queue: queue)

        if let connection = output.connection(with: .video) {
            // Stabilisation warps frames to fight handshake. On a tripod pointed at stars it
            // only fights the star alignment, and it crops the field of view for free.
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .off
            }
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }

        try Hardware.perform("commit capture session") { session.commitConfiguration() }
    }

    /// How many formats to try before giving up and letting the camera keep its own.
    private static let formatAttempts = 4

    /// Ask for the best format, and take the next one if the hardware says no.
    ///
    /// Returns whether any candidate was accepted. A false here is not fatal: the session
    /// is already running on whatever format the device chose for itself, so the app shows
    /// a live sky instead of a crash, with the manual controls clamped to that format.
    @discardableResult
    private func selectFormat(on device: AVCaptureDevice, preference: FormatPreference) -> Bool {
        let formats = device.formats
        let facts = formats.map(FormatFacts.init)
        let ranking = switch preference {
        case .longExposure: FormatChoice.longExposureRanking(from: facts)
        case .detector: FormatChoice.detectorRanking(from: facts)
        }

        for index in ranking.prefix(Self.formatAttempts) where formats.indices.contains(index) {
            let format = formats[index]
            do {
                try lockAndDisableAutomatics(device, format: format)
                logger.info("""
                    Configured \(device.localizedName, privacy: .public): \
                    \(facts[index].pixels / 1_000_000)MP, \
                    longest frame \(facts[index].longestFrame, format: .fixed(precision: 2))s, \
                    ISO \(facts[index].isoRange.lowerBound, format: .fixed(precision: 0))–\
                    \(facts[index].isoRange.upperBound, format: .fixed(precision: 0))
                    """)
                return true
            } catch {
                logger.error("""
                    Format \(facts[index].pixels / 1_000_000)MP refused: \
                    \(error.localizedDescription, privacy: .public)
                    """)
            }
        }

        logger.error("No format accepted; keeping the camera's own")
        return false
    }

    /// Turn off every automatic system. Each of these will happily undo a manual setting
    /// mid-session, which is exactly the complaint that started this project.
    private func lockAndDisableAutomatics(_ device: AVCaptureDevice, format: AVCaptureDevice.Format) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        try Hardware.perform("select format") { device.activeFormat = format }

        if device.isSubjectAreaChangeMonitoringEnabled {
            Hardware.attempt("subject-area monitoring") {
                device.isSubjectAreaChangeMonitoringEnabled = false
            }
        }
        if device.automaticallyAdjustsVideoHDREnabled {
            Hardware.attempt("automatic HDR") { device.automaticallyAdjustsVideoHDREnabled = false }
        }
        if device.activeFormat.isVideoHDRSupported {
            Hardware.attempt("HDR") { device.isVideoHDREnabled = false }
        }
        if device.isLowLightBoostSupported {
            Hardware.attempt("low-light boost") {
                device.automaticallyEnablesLowLightBoostWhenAvailable = false
            }
        }

        // 1.0 is not always an available zoom factor. On a device whose minimum is above
        // it — a camera that is itself a crop of a larger sensor — assigning 1.0 raises
        // NSRangeException, and an uncaught NSException is the app closing on launch.
        let zoom = min(max(1.0, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
        Hardware.attempt("zoom \(zoom)") { device.videoZoomFactor = zoom }
    }

    // MARK: - Manual exposure

    func apply(_ settings: CaptureSettings) async throws {
        try await captureQueue.perform { [self] in
            try applyOnQueue(settings)
        }
    }

    private func applyOnQueue(_ settings: CaptureSettings) throws {
        #if DEBUG
        if ProcessInfo.processInfo.environment["UITEST_SKY"] == "1" { return }
        #endif
        guard let device else { throw CameraError.noCameraAvailable }

        // Every value below is clamped to what this format reports, and every call that
        // applies one goes through `Hardware`. AVFoundation answers an out-of-range
        // argument with an NSException, which Swift cannot catch and the user experiences
        // as the app closing the moment it is given camera access.
        let format = device.activeFormat
        let facts = FormatFacts(format)
        let exposure = settings.frameExposure.clamped(to: facts.shortestFrame...facts.longestFrame)
        let iso = settings.iso.clamped(to: facts.isoRange)
        let duration = CMTime(seconds: exposure, preferredTimescale: 1_000_000)

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        // The order of these two is not a detail; it is what killed the app on an iPhone 15.
        //
        // The hardware holds one invariant: the shutter has to fit inside the frame
        // duration. It checks that on *both* setters, and narrowing the frame duration
        // makes AVFoundation re-apply the exposure already in force — into a window that
        // is now too small for it. The answer is an exception thrown out of
        // `setActiveVideoMinFrameDuration`, which is exactly where the crash report
        // pointed, and an uncaught NSException ends the process.
        //
        // So: widen the window before lengthening the shutter, and shorten the shutter
        // before narrowing the window. Every intermediate state is then legal on its own.
        let window = device.activeVideoMaxFrameDuration.seconds
        if FormatChoice.frameWindowFirst(exposure: exposure, currentWindow: window) {
            applyFrameWindow(duration, seconds: exposure, on: device, format: format)
            applyExposure(duration, seconds: exposure, iso: iso, on: device)
        } else {
            applyExposure(duration, seconds: exposure, iso: iso, on: device)
            applyFrameWindow(duration, seconds: exposure, on: device, format: format)
        }

        // Infinity, held. Autofocus in the dark hunts forever and lands on nothing.
        // A fixed-focus lens reports `.locked` as supported while refusing a custom lens
        // position — the ultra-wide on several iPhones is exactly that.
        if device.isFocusModeSupported(.locked) {
            let position = settings.focusPosition.clamped(to: 0...1)
            if device.isLockingFocusWithCustomLensPositionSupported {
                Hardware.attempt("focus at \(position)") {
                    device.setFocusModeLocked(lensPosition: position)
                }
            } else {
                Hardware.attempt("focus lock") { device.focusMode = .locked }
            }
        }

        if device.isWhiteBalanceModeSupported(.locked),
           device.isLockingWhiteBalanceWithCustomDeviceGainsSupported {
            let temperature = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                temperature: settings.whiteBalanceKelvin, tint: 0
            )
            var gains = device.deviceWhiteBalanceGains(for: temperature)
            let ceiling = max(1, device.maxWhiteBalanceGain)
            gains.redGain = gains.redGain.clamped(to: 1...ceiling)
            gains.greenGain = gains.greenGain.clamped(to: 1...ceiling)
            gains.blueGain = gains.blueGain.clamped(to: 1...ceiling)
            Hardware.attempt("white balance \(settings.whiteBalanceKelvin)K") {
                device.setWhiteBalanceModeLocked(with: gains)
            }
        }
    }

    /// Pin the frame rate to the exposure, so the sensor is not asked for more frames a
    /// second than the shutter can deliver.
    ///
    /// `exposure` is already inside the format's frame-duration window — that is what
    /// `FormatFacts.longestFrame` means — so this only has to survive a format that
    /// reports no window at all.
    private func applyFrameWindow(
        _ duration: CMTime,
        seconds: Double,
        on device: AVCaptureDevice,
        format: AVCaptureDevice.Format
    ) {
        guard FormatChoice.frameDurationBounds(format.videoSupportedFrameRateRanges) != nil else { return }
        Hardware.attempt("frame duration \(seconds)s") {
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
        }
    }

    /// The one call that actually pins both shutter and gain. Everything else on this
    /// device is now forbidden from touching them.
    private func applyExposure(
        _ duration: CMTime,
        seconds: Double,
        iso: Float,
        on device: AVCaptureDevice
    ) {
        guard device.isExposureModeSupported(.custom) else { return }
        Hardware.attempt("exposure \(seconds)s at ISO \(iso)") {
            device.setExposureModeCustom(duration: duration, iso: iso)
        }
    }

    // MARK: - Running

    func start() async {
        // The Simulator has no camera. Rather than showing a black rectangle, feed the
        // pipeline a synthesised sky — see StubSkySource. DEBUG only, opt-in by env var,
        // and it goes through exactly the same code path a real frame would.
        #if DEBUG
        if ProcessInfo.processInfo.environment["UITEST_SKY"] == "1" {
            startStubSky()
            return
        }
        #endif

        await captureQueue.perform { [self] in
            if !session.isRunning { session.startRunning() }
        }
    }

    #if DEBUG
    private func startStubSky() {
        let source = StubSkySource()
        stubSky = source
        stubTimer = DispatchSource.makeTimerSource(queue: captureQueue.dispatch)
        stubTimer?.schedule(deadline: .now(), repeating: 0.35)
        stubTimer?.setEventHandler { [weak self] in
            guard let self, let buffer = source.nextFrame() else { return }
            stubFrameIndex += 1
            onFrame(SensorFrame(
                pixelBuffer: buffer,
                timestamp: Double(stubFrameIndex) * 0.35,
                index: stubFrameIndex
            ))
        }
        stubTimer?.resume()
        logger.info("Stub sky running — Simulator screenshots")
    }
    #endif

    func stop() async {
        #if DEBUG
        stubTimer?.cancel()
        stubTimer = nil
        stubSky = nil
        #endif
        await captureQueue.perform { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }
}

// MARK: - Frame delivery

/// Bridges the Objective-C delegate callback into a closure.
///
/// Separate from `CaptureEngine` so the delegate conformance stays `nonisolated` without
/// dragging the engine's queue discipline into the type system.
private final class FrameReceiver: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    private let onFrame: @Sendable (SensorFrame) -> Void
    private var index = 0

    init(onFrame: @escaping @Sendable (SensorFrame) -> Void) {
        self.onFrame = onFrame
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        onFrame(SensorFrame(pixelBuffer: pixelBuffer, timestamp: timestamp, index: index))
        index += 1
    }
}

// MARK: - Clamping

extension Double {
    fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension Float {
    fileprivate func clamped(to range: ClosedRange<Float>) -> Float {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
