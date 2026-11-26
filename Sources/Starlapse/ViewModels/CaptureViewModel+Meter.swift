import Foundation
import SkyMeter
import StackKit

/// The framing meter, and what daylight turns Auto into.
///
/// Framing used to run at a fixed 1/8 s and the sensor's top ISO, so a dark horizon shows at
/// night. In daylight that is twelve stops over and the screen is white. The meter brings the
/// scene's median to mid-grey but never gives more light than the night framing, so at night
/// it asks for more than it may and the night framing stays exactly as it was.
extension CaptureViewModel {

    /// Daylight below this much light (shutter-seconds × ISO): 1/100 s at ISO 100, EV ≈ 10.6.
    /// Overcast day and brighter; a lit room or a street at night is well above it.
    static let daylightLight = 1.0
    /// How long to wait after a change before metering again. Frames already in the pipeline
    /// were shot at the old exposure, and metering one corrects the same error twice; three
    /// frames clear it. Under a third of a second in daylight, where waiting shows.
    var meterSettle: Duration {
        .seconds(max(0.3, 3 * activeSettings.frameExposure))
    }

    /// Auto on the Exposure mode in daylight: one frame at the metered exposure, developed
    /// like a photograph rather than stacked for minutes.
    var isDayPhoto: Bool {
        guard isDaylight, autoLight, !isMoonMode, case .still = mode else { return false }
        return true
    }

    /// The settings a day photo is shot with: the framing meter's exposure, one frame.
    var dayPhotoSettings: CaptureSettings {
        var day = settings
        day.stackMode = .smooth
        if let framingExposure {
            day.frameExposure = framingExposure.shutter
            day.iso = framingExposure.iso
        }
        day.totalLightSeconds = day.frameExposure
        return day
    }

    /// Meter four times a second while aiming, the Moon's disc in Moon mode and the whole
    /// scene otherwise. Nothing moves once the shutter is pressed: every setting is locked for
    /// the session, as it always was.
    func startFramingMeter() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                guard self.state == .aiming, !self.isFocusing,
                      let luma = await self.stackEngine?.watchedLuminance() else { continue }
                let changed = self.isMoonMode ? await self.meterMoon(luma) : await self.meterScene(luma)
                if changed { try? await Task.sleep(for: self.meterSettle) }
            }
        }
    }

    /// Returns whether the framing exposure changed.
    private func meterScene(_ luma: LumaImage) async -> Bool {
        let reading = SceneLevel.measure(luma.pixels)
        let night = settings.forFraming(capabilities)
        let nightExposure = Exposure(shutter: night.frameExposure, iso: night.iso)
        let ceiling = max(capabilities.minFrameExposure, min(1.0 / 30, capabilities.maxFrameExposure))
        let limits = ExposureMeter.Limits(shutter: capabilities.minFrameExposure...ceiling, iso: capabilities.isoRange)
        let next = ExposureMeter.next(
            framingExposure ?? nightExposure, reading: reading, target: ExposureMeter.sceneTarget, limits: limits
        )
        // Wanting more light than the meter may give is night: the night framing stays.
        let atCeiling = next.shutter >= limits.shutter.upperBound && next.iso >= limits.iso.upperBound
        let metered: Exposure? = atCeiling || next.light >= nightExposure.light ? nil : next
        guard metered != framingExposure else { return false }
        framingExposure = metered
        updateDaylight()
        await settingsChanged()
        return true
    }

    /// In at `daylightLight`, out at twice it, so dusk does not flicker between the two.
    private func updateDaylight() {
        let light = framingExposure?.light ?? .infinity
        let daylight = light <= Self.daylightLight * (isDaylight ? 2 : 1)
        guard daylight != isDaylight else { return }
        isDaylight = daylight
        stackEngine?.setFramingTone(daylight ? .day : .neutral)
    }

    /// Returns whether the exposure changed.
    func meterMoon(_ luma: LumaImage) async -> Bool {
        let (disc, brightest) = await Task.detached(priority: .userInitiated) {
            (MoonDisc.locate(in: luma.pixels, width: luma.width, height: luma.height), Self.brightest(luma.pixels))
        }.value
        guard isMoonMode, state == .aiming else { return false }
        moonDisc = disc
        // No disc: meter on the brightest thing, and only upward. The opening guess is for a
        // bright full Moon; a dimmer one (haze, a crescent, a screen) stayed under the
        // detector at it, and with nothing found nothing ever changed: a black screen for
        // good (26 Nov 2026, the Moon on a MacBook screen at 1/1000 s).
        let reading = disc.map { LightReading(level: $0.peak, clippedFraction: $0.clippedFraction) }
            ?? LightReading(level: brightest, clippedFraction: 0)
        if disc == nil, brightest >= ExposureMeter.moonTarget { return false }

        let ceiling = max(
            capabilities.minFrameExposure, min(CaptureSettings.longestMoonShutter, capabilities.maxFrameExposure)
        )
        // Searching never climbs past ISO 800: the Moon at 1/60 s is already blown at 100.
        let range = capabilities.isoRange
        let isoLimit = disc == nil ? range.lowerBound...max(range.lowerBound, min(range.upperBound, 800)) : range
        let next = ExposureMeter.next(
            Exposure(shutter: settings.frameExposure, iso: settings.iso),
            reading: reading,
            target: ExposureMeter.moonTarget,
            limits: ExposureMeter.Limits(shutter: capabilities.minFrameExposure...ceiling, iso: isoLimit)
        )
        guard next.shutter != settings.frameExposure || next.iso != settings.iso else { return false }
        settings.frameExposure = next.shutter
        settings.iso = next.iso
        await settingsChanged()
        return true
    }

    /// The level a few hundred pixels reach, so one hot pixel does not count as light.
    nonisolated static func brightest(_ pixels: [Float]) -> Double {
        let sample = stride(from: 0, to: pixels.count, by: 7).map { pixels[$0] }.sorted()
        guard !sample.isEmpty else { return 0 }
        return Double(sample[sample.count - 1 - sample.count / 2000])
    }
}
