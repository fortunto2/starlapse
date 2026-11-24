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
        if isDayPhoto {
            let day = dayPhotoSettings
            return String(
                format: String(localized: "Day photo · 1/%.0f s · ISO %.0f"),
                1 / max(day.frameExposure, 1e-6), day.iso
            )
        }
        if isMoonMode {
            return String(
                format: String(localized: "Steadiest %d frames × 1/%.0f s"),
                CaptureSettings.moonFrames, 1 / max(settings.frameExposure, 1e-6)
            )
        }
        let frames = settings.frameCount
        let total = settings.totalLightSeconds
        let minutes = total / 60
        let duration = minutes >= 1
            ? String(format: "%.0f min", minutes)
            : String(format: "%.0f s", total)
        return String(
            format: String(localized: "%@ of light = %d × %.2fs"), duration, frames, settings.frameExposure
        )
    }

    /// The one line under the shutter: what the current mode will actually do. Time-lapse
    /// and Detector have their own arithmetic; the still stack's "N min of light" does not
    /// apply to them and read like the length of the session (a 1.2.1 user's screenshot).
    var modeSummary: String {
        switch mode {
        case .timelapse: timelapse.summary
        case .detector(let detector): detector.summary
        case .still: exposureExplanation
        }
    }

    /// Averaging gain worth showing. Star Trails keeps the brightest value, not the mean,
    /// so it has none, and "−0.0 stops" only confused.
    var showsNoiseReduction: Bool {
        settings.stackMode != .trails && settings.noiseReductionStops > 0
    }

    var hardwareCeilingNote: String {
        String(
            format: String(
                localized: "This sensor caps a single frame at %.2fs — longer exposures are stacked, not held."
            ),
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
