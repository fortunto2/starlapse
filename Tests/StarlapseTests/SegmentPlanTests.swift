import Testing
@testable import Starlapse

/// These exist because the same mistake happened twice: a plan's purpose was inferred from
/// a combination of its other fields, and then a new plan arrived with the same combination.
///
/// The second time cost a stop button that did nothing — `isFraming` meant "has no segment
/// count", watching also has no segment count, so `cancel()` decided a running detector was
/// the viewfinder and returned silently. Nothing crashed, nothing logged; it just sat there.
@Suite("Segment plans")
struct SegmentPlanTests {

    static let capabilities = CameraCapabilities(
        lenses: [],
        isoRange: 50...3200,
        maxFrameExposure: 1.0,
        minFrameExposure: 1.0 / 1000,
        supportsAppleProRAW: true,
        deviceModel: "Test"
    )

    static var settings: CaptureSettings {
        CaptureSettings(
            lens: LensOption(
                deviceType: .builtInWideAngleCamera,
                displayName: "Main",
                aperture: 1.78,
                fieldOfView: 70
            ),
            iso: 1600,
            frameExposure: 1.0,
            focusPosition: 1.0,
            whiteBalanceKelvin: 3900,
            stackMode: .stars,
            totalLightSeconds: 300
        )
    }

    @Test("Everything except the viewfinder can be stopped")
    func onlyFramingIsUnstoppable() {
        #expect(!SegmentPlan.framing.isStoppable)
        #expect(SegmentPlan.watching(.default).isStoppable)
        #expect(SegmentPlan.still(Self.settings, tone: .init()).isStoppable)
        #expect(
            SegmentPlan.timelapse(Self.settings, timelapse: .default, tone: .init()).isStoppable
        )
    }

    @Test("Framing and watching are distinguishable despite matching field values")
    func framingAndWatchingDiffer() {
        let framing = SegmentPlan.framing
        let watching = SegmentPlan.watching(.default)

        // Identical in every derived quantity — this is exactly why `kind` has to be stored.
        #expect(framing.segments == watching.segments)
        #expect(framing.framesPerSegment == watching.framesPerSegment)
        #expect(framing.totalFrames == watching.totalFrames)

        #expect(framing.isFraming)
        #expect(!watching.isFraming)
        #expect(watching.isWatching)
        #expect(!framing.isWatching)
    }

    @Test("A capture plan knows how many frames it wants")
    func captureCountsFrames() {
        let still = SegmentPlan.still(Self.settings, tone: .init())
        #expect(still.segments == 1)
        #expect(still.framesPerSegment == Self.settings.frameCount)
        #expect(still.totalFrames == Self.settings.frameCount)
        #expect(still.aligns)

        let lapse = SegmentPlan.timelapse(Self.settings, timelapse: .default, tone: .init())
        #expect(lapse.segments == TimelapseSettings.default.frameCount)
        #expect((lapse.totalFrames ?? 0) > lapse.framesPerSegment)
    }

    @Test("Framing never aligns or accumulates")
    func framingIsDegenerate() {
        #expect(SegmentPlan.framing.framesPerSegment == 1)
        #expect(!SegmentPlan.framing.aligns)
        #expect(SegmentPlan.framing.totalFrames == nil)
        #expect(SegmentPlan.framing.detector == nil)
    }

    @Test("Detector windows convert to whole frames")
    func detectorWindows() {
        let settings = DetectorSettings.default
        // A quarter-second exposure is four frames a second.
        #expect(settings.captureFrameRate == 4)
        #expect(settings.preRollFrames == 6)
        #expect(settings.postRollFrames == 4)
        #expect(settings.clipDuration > 0.8)
        #expect(settings.warning == nil)
    }
}
