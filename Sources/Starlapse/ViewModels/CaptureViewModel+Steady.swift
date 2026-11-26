import Foundation
import StackKit

/// What the camera does now, and how a session adapts to a phone held in the hand.
///
/// A one-second frame from a hand is a smear, and stacking cannot undo blur inside a frame
/// (dataset, Nov 2026: handheld frames were the soft ones). So the shutter press reads the
/// gyroscope: a steady phone gets the frame length dialled in, a shaking one gets the
/// longest frame it can hold sharp, with the gain raised to keep the brightness.
extension CaptureViewModel {

    /// What the camera should be doing right now, derived from state rather than pushed at
    /// transition points. Framing gets short, high-gain frames; a session gets exactly what
    /// the user dialled in.
    var activeSettings: CaptureSettings {
        guard state.isCapturing else { return settings.forFraming(capabilities, metered: framingExposure) }
        if sessionIsDayPhoto { return dayPhotoSettings }
        // Watching needs short frames at a usable rate — an exposure long enough for a deep
        // stack would smear the meteor into the background and give three frames a second.
        if case .detector(let detector) = mode {
            var watching = settings
            watching.frameExposure = detector.frameExposure
            return watching
        }
        return handheldAdapted(settings)
    }

    /// A still star stack shot from the hand: shorter frames, more gain, and in Auto a
    /// length a person can hold. Everything else (tripod, time-lapse, Moon, day) is untouched.
    func handheldAdapted(_ settings: CaptureSettings) -> CaptureSettings {
        guard case .still = mode, settings.stackMode.alignsStars else { return settings }
        let exposure = Steadiness.handheldExposure(rate: sessionHoldRate, longest: settings.frameExposure)
        guard exposure < settings.frameExposure else { return settings }
        var adapted = settings
        adapted.iso = Steadiness.compensatedISO(
            settings.iso, from: settings.frameExposure, to: exposure, ceiling: capabilities.isoRange.upperBound
        )
        adapted.frameExposure = exposure
        if autoLight { adapted.totalLightSeconds = min(settings.totalLightSeconds, Self.handheldAutoSeconds) }
        return adapted
    }

    /// What the shutter press would do with the phone held as it is now, for the hint under
    /// the light picker. Nil where holding does not matter (no gyroscope, Moon, day).
    var holdAdvice: String? {
        guard case .still = mode, settings.stackMode.alignsStars, !isDayPhoto else { return nil }
        switch attitude.hold {
        case .unknown:
            return nil
        case .steady:
            return String(format: String(localized: "STEADY · %@ FRAMES"), Self.shutterText(settings.frameExposure))
        case .braced, .handheld:
            let exposure = Steadiness.handheldExposure(
                rate: attitude.shakeLog.recentRate(), longest: settings.frameExposure
            )
            return String(
                format: String(localized: "IN THE HAND · %@ FRAMES · REST THE PHONE FOR %@"),
                Self.shutterText(exposure), Self.shutterText(settings.frameExposure)
            )
        }
    }

    /// 1/15 s under half a second, 0.6 s above it: how photographers read a shutter.
    static func shutterText(_ seconds: Double) -> String {
        seconds < 0.5
            ? String(format: "1/%.0f s", (1 / max(seconds, 1e-4)).rounded())
            : String(format: "%.1f s", seconds)
    }

    /// Auto's length in the hand: the median person saved after 51 s (Nov 2026), and arms
    /// shake more the longer they are held up.
    static let handheldAutoSeconds: Double = 30
}
