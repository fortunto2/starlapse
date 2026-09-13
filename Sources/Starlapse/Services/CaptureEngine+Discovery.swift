import AVFoundation
import CoreMedia
import Foundation

/// What this iPhone's cameras can do, read from the hardware before any session exists.
///
/// Split out of `CaptureEngine` because none of it touches the session: it is the question
/// "what could this device do", asked once at launch so the controls can be built with the
/// right ranges. What the hardware will actually *accept* is a different question, settled
/// by `selectFormat(on:preference:)` once there is a session to accept it.
extension CaptureEngine {

    // MARK: - Discovery

    /// Read what the hardware offers instead of assuming a model.
    static func discoverCapabilities() -> CameraCapabilities {
        #if DEBUG
        if ProcessInfo.processInfo.environment["UITEST_SKY"] == "1" {
            return CameraCapabilities(
                lenses: [
                    LensOption(deviceType: .builtInUltraWideCamera, displayName: "Ultra Wide",
                               aperture: 2.2, fieldOfView: 106),
                    LensOption(deviceType: .builtInWideAngleCamera, displayName: "Main",
                               aperture: 1.78, fieldOfView: 73),
                    LensOption(deviceType: .builtInTelephotoCamera, displayName: "Telephoto",
                               aperture: 2.8, fieldOfView: 28),
                ],
                isoRange: 55...12288,
                maxFrameExposure: 1.0,
                minFrameExposure: 1.0 / 8000,
                supportsAppleProRAW: true,
                deviceModel: "iPhone"
            )
        }
        #endif
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
            let format = Self.bestFormat(for: primary) else {
            return .unavailable
        }

        // Read back what the chosen format will really do rather than what it advertises:
        // `maxExposureDuration` ignores the frame-rate floor, and the user's "1 second"
        // slider has to stop where the hardware does.
        let facts = FormatFacts(format)

        return CameraCapabilities(
            lenses: lenses,
            isoRange: facts.isoRange,
            maxFrameExposure: facts.longestFrame,
            minFrameExposure: facts.shortestFrame,
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

    /// The format this device would be asked for first.
    ///
    /// Used to read capabilities before a session exists. What the hardware will actually
    /// accept is settled later, by `selectFormat(on:preference:)` — asking is the only way
    /// to find out, and the answer differs between iPhone models.
    static func bestFormat(
        for device: AVCaptureDevice,
        preference: FormatPreference = .longExposure
    ) -> AVCaptureDevice.Format? {
        let formats = device.formats
        let facts = formats.map(FormatFacts.init)
        let index = switch preference {
        case .longExposure: FormatChoice.longExposure(from: facts)
        case .detector: FormatChoice.detector(from: facts)
        }
        guard let index, formats.indices.contains(index) else { return nil }
        return formats[index]
    }
}
