import CoreLocation
import CoreMotion
import Foundation
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
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            authorizationDenied = true
        default:
            locationManager.startUpdatingLocation()
        }

        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = Cadence.interactive.interval
        motion.startDeviceMotionUpdates(
            using: .xTrueNorthZVertical,
            to: .main
        ) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.update(from: motion)
        }
        isHeadingAvailable = true
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        locationManager.stopUpdatingLocation()
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
            case .denied, .restricted:
                self.authorizationDenied = true
            default:
                break
            }
        }
    }
}
