import AVFoundation
import CoreMedia
import Foundation

/// What matters about one sensor format, lifted out of AVFoundation.
///
/// Both numbers here decide whether the app works at all, and neither could be tested
/// while they lived inside an `AVCaptureDevice.Format` that only a phone can hand out.
struct FormatFacts: Sendable, Equatable {
    let pixels: Int
    /// Longest frame this format can really deliver: the shorter of the shutter ceiling
    /// and the frame-rate floor. They disagree more often than you would think — a format
    /// advertising `maxExposureDuration` of 1 s while refusing to drop below 1.5 fps
    /// delivers 0.667 s, and asking it for the full second is what raises an exception.
    let longestFrame: Double
    let shortestFrame: Double
    let isoRange: ClosedRange<Float>
    /// Plain 8-bit 4:2:0 video (`420v`/`420f`) — the only kind the BGRA output is known to
    /// convert on every iPhone. Newer phones list 10-bit, Apple Log and ProRes variants at
    /// the same size and frame rate, so without this they tie with the safe one and can win.
    var isEightBitVideo = true
    /// Stable name for this format on this device, for the crash quarantine.
    var key = ""
}

/// Which format to shoot with. Pure arithmetic over `FormatFacts`, so the rules are
/// testable without a camera.
enum FormatChoice {

    /// How many pixels the stack can afford.
    ///
    /// Every pixel of the chosen format costs ~28 bytes of GPU memory for the whole
    /// session: 16 for the RGBA32Float accumulator, 12 for three BGRA display buffers,
    /// plus the luminance copy. At 12 MP that is ~345 MB, which is what shipped and works.
    /// A 48 MP format — and every iPhone since the 14 Pro offers one, with a 1 s shutter
    /// ceiling and a 1 fps floor, so it wins every ranking below on merit — costs 1.4 GB
    /// before a single camera buffer, and iOS kills the app for it during launch.
    ///
    /// This is the difference between "the app closes when I allow the camera" and a
    /// photograph. The resolution given up is nothing: the stack is noise-limited, not
    /// detail-limited, and no one has ever wanted a 48 MP picture of star noise.
    static let pixelBudget = 16_000_000

    /// Every format worth trying for a long exposure, best first.
    ///
    /// A ranking rather than a single answer, because the camera gets a veto. A format can
    /// be listed by the device and still be refused when the session is asked to use it,
    /// and on an iPhone 17 that refusal arrived as an exception out of
    /// `commitConfiguration` — fatal, with no second choice to fall back to. The engine
    /// now walks this list until one is accepted.
    ///
    /// Longest frame first, ties broken by resolution: frame length decides how many
    /// frames a given hour of sky costs, and every frame is a fresh helping of read noise.
    static func longExposureRanking(from facts: [FormatFacts], excluding quarantined: Set<String> = []) -> [Int] {
        let (affordable, tooBig) = split(facts, excluding: quarantined)
        let best = affordable.sorted { left, right in
            if abs(left.fact.longestFrame - right.fact.longestFrame) > 0.01 {
                return left.fact.longestFrame > right.fact.longestFrame
            }
            return left.fact.pixels > right.fact.pixels
        }
        return (best + tooBig).map(\.index)
    }

    /// The best long-exposure format, or nil when there are no formats at all.
    static func longExposure(from facts: [FormatFacts]) -> Int? {
        longExposureRanking(from: facts).first
    }

    /// Every format worth trying for watching the sky, best first: around 1080p, still
    /// able to hold the shutter open a fifth of a second.
    ///
    /// Resolution is the thing to give up here. A meteor is a bright streak tens of pixels
    /// long, perfectly visible at 1080p, and dropping from 12 MP cuts the detector's ring
    /// buffer and its per-frame copy by roughly 6×.
    static func detectorRanking(from facts: [FormatFacts], excluding quarantined: Set<String> = []) -> [Int] {
        let target = 1920 * 1080
        let (affordable, tooBig) = split(facts, excluding: quarantined)
        let usable = affordable.filter { $0.fact.longestFrame >= 0.2 }
        guard !usable.isEmpty else { return longExposureRanking(from: facts, excluding: quarantined) }

        let best = usable.sorted { abs($0.fact.pixels - target) < abs($1.fact.pixels - target) }
        let rest = affordable.filter { $0.fact.longestFrame < 0.2 }
            .sorted { $0.fact.longestFrame > $1.fact.longestFrame }
        return (best + rest + tooBig).map(\.index)
    }

    /// The best detector format, or nil when there are no formats at all.
    static func detector(from facts: [FormatFacts]) -> Int? {
        detectorRanking(from: facts).first
    }

    /// Inside the memory budget, outside it, and not to be trusted.
    ///
    /// Over-budget formats stay in the ranking, last and smallest first: a device where
    /// every format is enormous should still take a photograph. Shooting big beats not
    /// shooting, and being killed at launch beats neither.
    ///
    /// Formats that are not plain 8-bit video come after all of those: build 8 died in
    /// `startRunning` on an iPhone 17 Pro Max, and a 10-bit or Log variant handed to a BGRA
    /// output is the likeliest refusal. Quarantined formats — ones that already killed the
    /// process once on this phone — are not listed at all.
    private static func split(
        _ facts: [FormatFacts], excluding quarantined: Set<String>
    ) -> (affordable: [(index: Int, fact: FormatFacts)], tooBig: [(index: Int, fact: FormatFacts)]) {
        let all = facts.enumerated()
            .map { (index: $0.offset, fact: $0.element) }
            .filter { $0.fact.key.isEmpty || !quarantined.contains($0.fact.key) }
        let safe = all.filter(\.fact.isEightBitVideo)
        let risky = all.filter { !$0.fact.isEightBitVideo }.sorted { $0.fact.pixels < $1.fact.pixels }
        return (
            safe.filter { $0.fact.pixels <= pixelBudget },
            safe.filter { $0.fact.pixels > pixelBudget }.sorted { $0.fact.pixels < $1.fact.pixels } + risky
        )
    }

    /// Whether the frame-duration window has to be applied before the exposure.
    ///
    /// The camera requires the shutter to fit inside the frame duration, and enforces it
    /// on both setters: narrowing the window re-applies the exposure already in force, and
    /// if that no longer fits, AVFoundation raises. Widen before lengthening, shorten
    /// before narrowing, and no intermediate state is ever illegal.
    ///
    /// An unknown window counts as widening: that is the first call after a format change,
    /// where the exposure in force is whatever the camera picked for itself. An unbounded
    /// one does not, because any shutter already fits inside it.
    static func frameWindowFirst(exposure: Double, currentWindow: Double) -> Bool {
        currentWindow.isNaN || exposure > currentWindow
    }

    /// The frame durations a format will accept, in seconds.
    ///
    /// Handing `activeVideoMinFrameDuration` a value outside this window raises
    /// `NSInvalidArgumentException`, which is a process death rather than an error.
    static func frameDurationBounds(_ ranges: [AVFrameRateRange]) -> ClosedRange<Double>? {
        guard let shortest = ranges.map(\.minFrameDuration.seconds).min(),
              let longest = ranges.map(\.maxFrameDuration.seconds).max(),
              shortest.isFinite, longest.isFinite, shortest > 0, shortest <= longest
        else { return nil }
        return shortest...longest
    }
}

extension FormatFacts {

    /// Read the facts off a real format.
    init(_ format: AVCaptureDevice.Format) {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let bounds = FormatChoice.frameDurationBounds(format.videoSupportedFrameRateRanges)

        let ceiling = min(format.maxExposureDuration.seconds, bounds?.upperBound ?? .infinity)
        let floor = max(format.minExposureDuration.seconds, bounds?.lowerBound ?? 0)

        pixels = Int(dimensions.width) * Int(dimensions.height)
        // Ordered rather than assigned: these come from two independent limits, and a
        // format where they cross would otherwise build a ClosedRange that traps.
        longestFrame = max(ceiling, floor)
        shortestFrame = min(ceiling, floor)
        isoRange = min(format.minISO, format.maxISO)...max(format.minISO, format.maxISO)

        let subtype = CMFormatDescriptionGetMediaSubType(format.formatDescription)
        isEightBitVideo = subtype == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            || subtype == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        let fps = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
        key = "\(dimensions.width)x\(dimensions.height)-\(FormatFacts.fourCC(subtype))-\(Int(fps))fps"
            + (format.isVideoBinned ? "-binned" : "")
    }

    /// `420v`, `x420` and friends, readable in a log line and a defaults key.
    static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        let printable = bytes.allSatisfy { (0x20...0x7E).contains($0) }
        return printable ? String(bytes: bytes, encoding: .ascii) ?? String(code) : String(code)
    }
}
