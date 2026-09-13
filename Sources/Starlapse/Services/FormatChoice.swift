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

    /// Index of the format that allows the longest single frame, breaking ties by
    /// resolution. This ordering is the entire game: frame length decides how many frames
    /// a given hour of sky costs, and every frame is a fresh helping of read noise.
    static func longExposure(from facts: [FormatFacts]) -> Int? {
        rank(affordable(in: facts)) { left, right in
            if abs(left.fact.longestFrame - right.fact.longestFrame) > 0.01 {
                return left.fact.longestFrame < right.fact.longestFrame
            }
            return left.fact.pixels < right.fact.pixels
        }
    }

    /// Index of the format to watch the sky with: around 1080p, still able to hold the
    /// shutter open a fifth of a second.
    ///
    /// Resolution is the thing to give up here. A meteor is a bright streak tens of pixels
    /// long, perfectly visible at 1080p, and dropping from 12 MP cuts the detector's ring
    /// buffer and its per-frame copy by roughly 6×.
    static func detector(from facts: [FormatFacts]) -> Int? {
        let target = 1920 * 1080
        let usable = affordable(in: facts).filter { $0.fact.longestFrame >= 0.2 }
        guard !usable.isEmpty else { return longExposure(from: facts) }

        return rank(usable) { left, right in
            abs(left.fact.pixels - target) > abs(right.fact.pixels - target)
        }
    }

    /// Everything inside the memory budget — or, if nothing is, the smallest format there
    /// is. Shooting small beats being killed at launch, and on a device where every format
    /// is enormous that is the only choice left.
    private static func affordable(in facts: [FormatFacts]) -> [(index: Int, fact: FormatFacts)] {
        let all = facts.enumerated().map { (index: $0.offset, fact: $0.element) }
        let withinBudget = all.filter { $0.fact.pixels <= pixelBudget }
        guard withinBudget.isEmpty else { return withinBudget }
        guard let smallest = all.min(by: { $0.fact.pixels < $1.fact.pixels }) else { return [] }
        return [smallest]
    }

    private static func rank(
        _ candidates: [(index: Int, fact: FormatFacts)],
        by isBetter: ((index: Int, fact: FormatFacts), (index: Int, fact: FormatFacts)) -> Bool
    ) -> Int? {
        candidates.max(by: isBetter)?.index
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
    }
}
