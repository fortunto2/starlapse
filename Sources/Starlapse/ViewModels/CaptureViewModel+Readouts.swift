import Foundation

/// Read-only readouts derived from settings and hardware.
///
/// Split from the main view model to keep it inside the size limit. Nothing here holds
/// state — these are the sentences the interface puts in front of the user, and they are
/// where the app's central honesty lives: that a "10 minute exposure" is 600 frames of one
/// second, because the sensor cannot do anything else.
extension CaptureViewModel {

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

    /// Now, except in screenshot mode, where it is the middle of a Perseid night.
    ///
    /// Screenshots get taken in the afternoon, and an astrophotography app photographed in
    /// daylight honestly reports "wait for full darkness" — accurate, and useless as a
    /// picture of what the app is for. The sky positions are still computed for real from
    /// this instant; only the instant is chosen.
    var planDate: Date {
        #if DEBUG
        if ProcessInfo.processInfo.environment["UITEST_SKY"] == "1" {
            var components = DateComponents()
            components.year = 2026
            components.month = 8
            components.day = 12
            components.hour = 1
            components.minute = 20
            if let night = Calendar.gregorianUTC.date(from: components) {
                return night
            }
        }
        #endif
        return Date()
    }
}
