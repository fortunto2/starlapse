import CoreLocation
import CoreMotion
import Foundation
import os
import SkyKit

/// Where the camera is pointing, and where on Earth it stands.
///
/// Notably **not** ARKit. ARKit's world tracking is visual-inertial: it needs the camera to
/// see textured surfaces to hold its bearing. Pointed at a black sky it drops to
/// `.limited(.insufficientFeatures)` within seconds and the heading drifts away. Device
/// motion with a true-north reference uses only the gyroscope, accelerometer and
/// magnetometer, so it works in total darkness, costs a fraction of the battery, and does
/// not fight the camera for the sensor.
@MainActor
@Observable
final class AttitudeProvider: NSObject {

    private let motion = CMMotionManager()
    private let locationManager = CLLocationManager()
    private let logger = Logger(subsystem: "co.superduperai.starlapse", category: "attitude")

    /// The reference frame the sensor fusion is running in, once a sample has arrived.
    private(set) var referenceFrame: CMAttitudeReferenceFrame?
    private var watchdog: Task<Void, Never>?
    private var sampleCount = 0

    /// Direction the rear camera is currently aimed.
    private(set) var aim = HorizontalCoordinates(azimuth: 0, altitude: 0)
    /// Rotation of the device about the view axis, radians — used to keep overlay labels
    /// upright when the phone is on its side.
    private(set) var roll: Double = 0
    private(set) var location: GeographicCoordinates?
    private(set) var isHeadingAvailable = false
    private(set) var authorizationDenied = false

    /// True north needs magnetic declination, which needs a rough position. Without
    /// location we can still show altitude, but azimuth would be magnetic, not true.
    var hasFullFix: Bool { location != nil && isHeadingAvailable }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Aiming needs a responsive readout; an unattended session does not.
    ///
    /// At 30 Hz every sample invalidates the SwiftUI body that reads `aim`, so the whole
    /// interface re-evaluates thirty times a second for hours while the phone sits still on
    /// a tripod with the screen dimmed. Two hertz keeps the overlay honest for free.
    enum Cadence: Sendable {
        case interactive
        case idle

        var interval: TimeInterval {
            switch self {
            case .interactive: 1.0 / 30.0
            case .idle: 1.0 / 2.0
            }
        }
    }

    func setCadence(_ cadence: Cadence) {
        guard motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = cadence.interval
    }

    func start() {
        #if DEBUG
        // Screenshot mode: the Simulator has no GPS and no magnetometer, so the sky overlay
        // would be empty and a permission dialog would sit over the shot. Stand in for both.
        // The positions are still computed for real — this only supplies where and which way.
        if ProcessInfo.processInfo.environment["UITEST_SKY"] == "1" {
            location = GeographicCoordinates(latitude: 28.754, longitude: -17.885)
            aim = HorizontalCoordinates(azimuth: 96, altitude: 44)
            isHeadingAvailable = true
            return
        }
        #endif

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            authorizationDenied = true
        default:
            locationManager.startUpdatingLocation()
        }

        startMotion(using: Self.preferredFrame(
            available: CMMotionManager.availableAttitudeReferenceFrames(),
            locationAuthorized: locationManager.authorizationStatus.isAuthorized
        ))
    }

    func stop() {
        watchdog?.cancel()
        motion.stopDeviceMotionUpdates()
        locationManager.stopUpdatingLocation()
    }

    /// The best frame this phone can give right now.
    ///
    /// True north needs the magnetometer and a position for declination. Asked for before
    /// location is authorised, CoreMotion delivered nothing on an iPhone 17 Pro (iOS 27):
    /// the overlay drew its markers once and they never moved. Magnetic north works with no
    /// location at all, and `.xArbitraryCorrectedZVertical` works with no magnetometer —
    /// altitude is still right, and a wrong azimuth is better than a frozen one.
    nonisolated static func preferredFrame(
        available: CMAttitudeReferenceFrame, locationAuthorized: Bool
    ) -> CMAttitudeReferenceFrame {
        if locationAuthorized, available.contains(.xTrueNorthZVertical) { return .xTrueNorthZVertical }
        if available.contains(.xMagneticNorthZVertical) { return .xMagneticNorthZVertical }
        return .xArbitraryCorrectedZVertical
    }

    /// What to fall back to when a frame yields no samples.
    nonisolated static func fallback(after frame: CMAttitudeReferenceFrame) -> CMAttitudeReferenceFrame? {
        switch frame {
        case .xTrueNorthZVertical: .xMagneticNorthZVertical
        case .xMagneticNorthZVertical: .xArbitraryCorrectedZVertical
        default: nil
        }
    }

    private func startMotion(using frame: CMAttitudeReferenceFrame) {
        guard motion.isDeviceMotionAvailable else {
            logger.error("Device motion unavailable")
            return
        }
        watchdog?.cancel()
        motion.stopDeviceMotionUpdates()
        sampleCount = 0
        isHeadingAvailable = false
        motion.deviceMotionUpdateInterval = Cadence.interactive.interval
        motion.startDeviceMotionUpdates(using: frame, to: .main) { [weak self] motion, error in
            guard let self else { return }
            if let error { self.logger.error("Motion: \(error.localizedDescription, privacy: .public)") }
            guard let motion else { return }
            self.sampleCount += 1
            if self.sampleCount == 1 {
                self.referenceFrame = frame
                self.isHeadingAvailable = true
                self.logger.info("Attitude running in frame \(frame.rawValue)")
            }
            self.update(from: motion)
        }

        // A frame the phone lists but cannot actually serve yields no samples and no error.
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled, sampleCount == 0 else { return }
            logger.error("No motion samples in frame \(frame.rawValue) after 2 s")
            if let next = Self.fallback(after: frame) { startMotion(using: next) }
        }
    }

    /// Convert device attitude into a direction on the sky.
    ///
    /// In the `.xTrueNorthZVertical` frame X points to true north and Z points up, making
    /// Y point west. The rear camera looks along the device's −Z axis, so rotating that
    /// vector into the reference frame gives the aim directly.
    private func update(from motion: CMDeviceMotion) {
        let rotation = motion.attitude.rotationMatrix

        // rotationMatrix maps reference → body, so its transpose maps body → reference.
        // Rotating (0, 0, −1) by the transpose is just the negated third row.
        let north = -rotation.m31
        let west = -rotation.m32
        let up = -rotation.m33

        let east = -west
        let azimuth = atan2(east, north).degrees
        let altitude = asin(up.clamped(to: -1 ... 1)).degrees

        aim = HorizontalCoordinates(azimuth: azimuth, altitude: altitude)
        roll = motion.attitude.roll
    }
}

extension AttitudeProvider: CLLocationManagerDelegate {

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let latest = locations.last else { return }
        let coordinate = latest.coordinate
        Task { @MainActor in
            self.location = GeographicCoordinates(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Read the status here, then hop over with just that value. `CLLocationManager`
        // itself is not Sendable, so the manager must not cross into the Task — we already
        // hold the same instance on the main actor.
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.authorizationDenied = false
                self.locationManager.startUpdatingLocation()
                // Now true north can be served; move to it if we started on something less.
                let wanted = Self.preferredFrame(
                    available: CMMotionManager.availableAttitudeReferenceFrames(),
                    locationAuthorized: true
                )
                let running = self.motion.isDeviceMotionActive
                if running, self.referenceFrame != wanted, self.sampleCount > 0 || self.referenceFrame == nil {
                    self.startMotion(using: wanted)
                }
            case .denied, .restricted:
                self.authorizationDenied = true
            default:
                break
            }
        }
    }
}

extension CLAuthorizationStatus {
    var isAuthorized: Bool { self == .authorizedWhenInUse || self == .authorizedAlways }
}
