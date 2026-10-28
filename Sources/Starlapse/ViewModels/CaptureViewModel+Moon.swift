import Foundation
import SkyKit
import SkyMeter
import StackKit

/// What Moon mode borrows from the night settings, to give back when it is left.
struct MoonReturn: Sendable {
    let stackMode: StackMode
    let lens: LensOption
    let iso: Float
    let frameExposure: Double
    let tone: FrameAccumulator.ToneSettings
}

/// Moon mode: short frames on the longest lens, metered off the disc while framing.
///
/// Split from the main view model to keep it inside the size limit.
extension CaptureViewModel {

    var isMoonMode: Bool { settings.stackMode == .moon }

    /// The Moon is up and inside the frame, by the compass: the cue to offer Moon mode.
    var moonInFrame: Bool {
        guard !isMoonMode, let conditions = plan?.conditions, conditions.isMoonUp, attitude.hasFullFix
        else { return false }
        return attitude.aim.separation(from: conditions.moonPosition) < Double(settings.lens.fieldOfView) / 2
    }

    func enterMoonMode() {
        guard !isMoonMode, !state.isCapturing else { return }
        moonReturn = MoonReturn(
            stackMode: settings.stackMode, lens: settings.lens, iso: settings.iso,
            frameExposure: settings.frameExposure, tone: tone
        )
        mode = .still
        settings.stackMode = .moon
        // The narrowest field makes the biggest disc: the telephoto where there is one.
        if let longest = capabilities.lenses.min(by: { $0.fieldOfView < $1.fieldOfView }) {
            settings.lens = longest
        }
        settings.iso = capabilities.isoRange.lowerBound
        // A starting guess for a bright Moon; the meter corrects it within a second.
        settings.frameExposure = max(capabilities.minFrameExposure, 1.0 / 1000)
        tone = .moon
        moonDisc = nil
        Task { await settingsChanged() }
        startMoonMetering()
    }

    func leaveMoonMode() {
        guard isMoonMode else { return }
        moonMetering?.cancel()
        moonMetering = nil
        moonDisc = nil
        if let saved = moonReturn {
            settings.stackMode = saved.stackMode
            settings.lens = saved.lens
            settings.iso = saved.iso
            settings.frameExposure = saved.frameExposure
            tone = saved.tone
        } else {
            settings.stackMode = .stars
            settings.frameExposure = capabilities.maxFrameExposure
            tone = FrameAccumulator.ToneSettings()
        }
        moonReturn = nil
        Task { await settingsChanged() }
    }

    /// Meter the disc twice a second while aiming. The exposure is locked once the shutter
    /// is pressed, like every other setting here: nothing moves behind the user's back
    /// during a session.
    private func startMoonMetering() {
        moonMetering?.cancel()
        moonMetering = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, self.isMoonMode else { return }
                guard self.state == .aiming, let luma = await self.stackEngine?.watchedLuminance() else { continue }
                if await self.meterMoon(luma) {
                    // Frames already in the pipeline were shot at the old exposure. Metering
                    // one of them corrects the same error twice and the disc swings past
                    // the target, so wait for the new exposure to reach the buffer.
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }

    /// Returns whether the exposure changed.
    private func meterMoon(_ luma: LumaImage) async -> Bool {
        let disc = await Task.detached(priority: .userInitiated) {
            MoonDisc.locate(in: luma.pixels, width: luma.width, height: luma.height)
        }.value
        guard isMoonMode, state == .aiming else { return false }
        moonDisc = disc
        guard let disc else { return false }

        let limits = MoonExposure.Limits(
            shutter: capabilities.minFrameExposure...max(
                capabilities.minFrameExposure, min(CaptureSettings.longestMoonShutter, capabilities.maxFrameExposure)
            ),
            iso: capabilities.isoRange
        )
        let next = MoonExposure.next(
            shutter: settings.frameExposure, iso: settings.iso,
            peak: disc.peak, clippedFraction: disc.clippedFraction, limits: limits
        )
        guard next.shutter != settings.frameExposure || next.iso != settings.iso else { return false }
        settings.frameExposure = next.shutter
        settings.iso = next.iso
        await settingsChanged()
        return true
    }
}
