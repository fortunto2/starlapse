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

/// Moon mode: short frames on the longest lens, metered off the disc while framing (the
/// meter itself is in `CaptureViewModel+Meter.swift`).
///
/// Split from the main view model to keep it inside the size limit.
extension CaptureViewModel {

    var isMoonMode: Bool { settings.stackMode == .moon }

    /// What to focus on, for the hint in the top bar. In Moon mode that is the Moon, which
    /// the night hint skips on purpose: at a star exposure it is a blown-out blob.
    var focusTargetName: String? {
        if isMoonMode { return String(localized: "THE MOON") }
        return plan?.focusTarget?.name.uppercased()
    }

    // The keys are the existing translated strings, so they cannot be wrapped.
    // swiftlint:disable line_length
    /// What the focus sweep says while it runs: stars measure by size, the Moon by its edge.
    var focusingCaption: (title: String, detail: String) {
        isMoonMode
            ? (String(localized: "FOCUSING ON THE MOON"),
               String(localized: "Stepping the lens and measuring the Moon's edge.\nHold still — the tripod must not move."))
            : (String(localized: "FOCUSING ON STARS"),
               String(localized: "Stepping the lens and measuring star size.\nHold still — the tripod must not move."))
    }
    // swiftlint:enable line_length

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
        aimChoice = nil
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
    }

    func leaveMoonMode() {
        guard isMoonMode else { return }
        moonDisc = nil
        aimChoice = nil
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
}
