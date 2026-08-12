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

    /// Called on the capture queue for every frame. Must consume the buffer synchronously.
    private let onFrame: @Sendable (SensorFrame) -> Void

    init(queue: CaptureQueue, onFrame: @escaping @Sendable (SensorFrame) -> Void) {
        self.captureQueue = queue
        self.onFrame = onFrame
    }

    // MARK: - Authorization

    static func requestAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    // MARK: - Discovery

    /// Read what the hardware offers instead of assuming a model.
    static func discoverCapabilities() -> CameraCapabilities {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera],
            mediaType: .video,
            position: .back
        )

        let lenses: [LensOption] = discovery.devices.map { device in
            LensOption(
                deviceType: device.deviceType,
                displayName: Self.friendlyName(for: device.deviceType),
                aperture: device.lensAperture,
                fieldOfView: device.activeFormat.videoFieldOfView
            )
        }

        guard let primary = discovery.devices.first(where: { $0.deviceType == .builtInWideAngleCamera })
            ?? discovery.devices.first,
            let format = Self.bestLongExposureFormat(for: primary) else {
            return .unavailable
        }

        return CameraCapabilities(
            lenses: lenses,
            isoRange: format.minISO...format.maxISO,
            maxFrameExposure: format.maxExposureDuration.seconds,
            minFrameExposure: format.minExposureDuration.seconds,
            supportsAppleProRAW: discovery.devices.count >= 3,
            deviceModel: primary.localizedName
        )
    }

    private static func friendlyName(for type: AVCaptureDevice.DeviceType) -> String {
        switch type {
        case .builtInUltraWideCamera: "Ultra Wide"
        case .builtInTelephotoCamera: "Telephoto"
        default: "Main"
        }
    }

    /// Pick the format that allows the longest single frame, breaking ties by resolution.
    ///
    /// This ordering is the entire game. iPhone formats differ in exposure ceiling, and the
    /// binned low-resolution ones usually win — a shorter ceiling would force more, noisier
    /// frames for the same total light.
    private static func bestLongExposureFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        device.formats
            .filter { format in
                // The frame rate floor has to be low enough to actually hold the shutter
                // open that long — a format capped at 30 fps minimum cannot do 1 s frames.
                format.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= 1.5 }
            }
            .max { left, right in
                let leftExposure = left.maxExposureDuration.seconds
                let rightExposure = right.maxExposureDuration.seconds
                if abs(leftExposure - rightExposure) > 0.01 {
                    return leftExposure < rightExposure
                }
                return Self.pixelCount(left) < Self.pixelCount(right)
            }
    }

    private static func pixelCount(_ format: AVCaptureDevice.Format) -> Int {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return Int(dimensions.width) * Int(dimensions.height)
    }

    // MARK: - Configuration

    func prepare(lens: LensOption) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    try configure(lens: lens)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func configure(lens: LensOption) throws {
        guard let device = AVCaptureDevice.default(lens.deviceType, for: .video, position: .back) else {
            throw CameraError.noCameraAvailable
        }
        guard let format = Self.bestLongExposureFormat(for: device) else {
            throw CameraError.noUsableFormat
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // .inputPriority keeps the session from overriding activeFormat back to something
        // convenient for FaceTime. Without it every exposure setting below gets reverted.
        session.sessionPreset = .inputPriority

        for input in session.inputs { session.removeInput(input) }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
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

        try device.lockForConfiguration()
        device.activeFormat = format
        // Kill every automatic system. Each of these will happily undo a manual setting
        // mid-session, which is exactly the complaint that started this project.
        if device.isSubjectAreaChangeMonitoringEnabled {
            device.isSubjectAreaChangeMonitoringEnabled = false
        }
        if device.automaticallyAdjustsVideoHDREnabled {
            device.automaticallyAdjustsVideoHDREnabled = false
        }
        if device.activeFormat.isVideoHDRSupported {
            device.isVideoHDREnabled = false
        }
        if device.isLowLightBoostSupported {
            device.automaticallyEnablesLowLightBoostWhenAvailable = false
        }
        device.videoZoomFactor = 1.0
        device.unlockForConfiguration()

        self.device = device
        logger.info("""
            Configured \(device.localizedName, privacy: .public): \
            max exposure \(format.maxExposureDuration.seconds, format: .fixed(precision: 2))s, \
            ISO \(format.minISO, format: .fixed(precision: 0))–\(format.maxISO, format: .fixed(precision: 0))
            """)
    }

    // MARK: - Manual exposure

    func apply(_ settings: CaptureSettings) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    try applyOnQueue(settings)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func applyOnQueue(_ settings: CaptureSettings) throws {
        guard let device else { throw CameraError.noCameraAvailable }

        let format = device.activeFormat
        let exposure = settings.frameExposure.clamped(
            to: format.minExposureDuration.seconds ... format.maxExposureDuration.seconds
        )
        let iso = settings.iso.clamped(to: format.minISO ... format.maxISO)
        let duration = CMTime(seconds: exposure, preferredTimescale: 1_000_000)

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        // Frame duration has to leave room for the shutter, or the requested exposure is
        // silently truncated to fit the frame rate.
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration

        // The one call that actually pins both shutter and gain. Everything else on this
        // device is now forbidden from touching them.
        device.setExposureModeCustom(duration: duration, iso: iso)

        if device.isFocusModeSupported(.locked) {
            // Infinity, held. Autofocus in the dark hunts forever and lands on nothing.
            device.setFocusModeLocked(lensPosition: settings.focusPosition.clamped(to: 0...1))
        }

        if device.isWhiteBalanceModeSupported(.locked) {
            let temperature = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                temperature: settings.whiteBalanceKelvin, tint: 0
            )
            var gains = device.deviceWhiteBalanceGains(for: temperature)
            let ceiling = device.maxWhiteBalanceGain
            gains.redGain = gains.redGain.clamped(to: 1...ceiling)
            gains.greenGain = gains.greenGain.clamped(to: 1...ceiling)
            gains.blueGain = gains.blueGain.clamped(to: 1...ceiling)
            device.setWhiteBalanceModeLocked(with: gains)
        }
    }

    // MARK: - Running

    func start() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                if !session.isRunning { session.startRunning() }
                continuation.resume()
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                if session.isRunning { session.stopRunning() }
                continuation.resume()
            }
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
