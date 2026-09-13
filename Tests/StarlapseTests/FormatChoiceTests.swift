import Testing
@testable import Starlapse

/// The format picker decides two things that can end a session before it starts: how long
/// a single frame may be, and how much memory the stack costs for the rest of the night.
///
/// The second one shipped wrong. A 48 MP format wins every ranking on merit — same 1 s
/// shutter ceiling, six times the pixels — and costs 1.4 GB of GPU buffers, so iOS killed
/// the app during launch on every phone that offers one. It looked like "the app closes
/// when I allow the camera", which is exactly how it arrived: a three-star review.
@Suite("Choosing a sensor format")
struct FormatChoiceTests {

    static func format(megapixels: Double, longest: Double = 1.0, shortest: Double = 1 / 8000) -> FormatFacts {
        FormatFacts(
            pixels: Int(megapixels * 1_000_000),
            longestFrame: longest,
            shortestFrame: shortest,
            isoRange: 55...12288
        )
    }

    @Test("A 48 MP format never wins, however good its shutter looks")
    func rejectsFormatsThatCannotFitInMemory() {
        let facts = [
            Self.format(megapixels: 12),
            Self.format(megapixels: 48),
        ]

        #expect(FormatChoice.longExposure(from: facts) == 0)
    }

    @Test("Within the budget, the longest frame wins — and resolution breaks the tie")
    func picksLongestThenLargest() {
        let facts = [
            Self.format(megapixels: 12, longest: 0.5),
            Self.format(megapixels: 2, longest: 1.0),
            Self.format(megapixels: 8, longest: 1.0),
        ]

        #expect(FormatChoice.longExposure(from: facts) == 2)
    }

    @Test("A format that cannot hold the shutter open loses to one that can")
    func prefersALongShutterOverPixels() {
        let facts = [
            Self.format(megapixels: 12, longest: 1.0 / 30.0),
            Self.format(megapixels: 2, longest: 1.0),
        ]

        #expect(FormatChoice.longExposure(from: facts) == 1)
    }

    @Test("When every format is too big, shoot the smallest rather than nothing")
    func fallsBackToTheSmallestFormat() {
        let facts = [
            Self.format(megapixels: 48),
            Self.format(megapixels: 24),
            Self.format(megapixels: 200),
        ]

        // Being killed at launch is not a better photograph than a small one.
        #expect(FormatChoice.longExposure(from: facts) == 1)
    }

    @Test("No formats at all is the one case with no answer")
    func noFormats() {
        #expect(FormatChoice.longExposure(from: []) == nil)
        #expect(FormatChoice.detector(from: []) == nil)
    }

    @Test("Watching picks the format closest to 1080p that still holds a fifth of a second")
    func detectorPrefersAboutTenEightyP() {
        let facts = [
            Self.format(megapixels: 12, longest: 1.0),
            Self.format(megapixels: 2, longest: 0.25),
            Self.format(megapixels: 0.3, longest: 0.25),
        ]

        #expect(FormatChoice.detector(from: facts) == 1)
    }

    @Test("A short-shutter 1080p format is no use to the detector")
    func detectorIgnoresShortShutterFormats() {
        let facts = [
            Self.format(megapixels: 2, longest: 1.0 / 60.0),
            Self.format(megapixels: 12, longest: 1.0),
        ]

        #expect(FormatChoice.detector(from: facts) == 1)
    }

    @Test("A camera reporting a zero exposure ceiling costs a bad plan, not a trap")
    func zeroExposureDoesNotTrap() {
        var settings = SegmentPlanTests.settings
        settings.frameExposure = 0

        // `Int(totalLight / 0)` is `Int(infinity)`, which traps rather than overflowing.
        #expect(settings.frameCount >= 1)
    }
}
