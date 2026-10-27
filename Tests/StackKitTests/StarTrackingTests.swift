import Testing
@testable import StackKit

/// Field data, 1.1.0: 10 of 28 saved stills reported zero stacked frames. Every frame of a
/// starless sky (city glow, cloud, a room) was dropped as "tracking lost", nothing reached
/// the accumulator, and Save wrote the last framing frame under the session's name.
@Suite("Star tracking")
struct StarTrackingTests {

    @Test("A sky with no stars yet is stacked in place, not thrown away")
    func starlessSkyStacksInPlace() {
        #expect(StarTracking.decide(starCount: 0, hasReference: false) == .stackInPlace)
        #expect(StarTracking.decide(starCount: 5, hasReference: false) == .stackInPlace)
    }

    @Test("The first frame with enough stars becomes the reference")
    func firstStarryFrameIsReference() {
        #expect(StarTracking.decide(starCount: 6, hasReference: false) == .reference)
    }

    @Test("Once tracking has started, losing the stars drops the frame")
    func lostTrackingDrops() {
        #expect(StarTracking.decide(starCount: 2, hasReference: true) == .drop)
    }

    @Test("Stars and a reference: align")
    func aligns() {
        #expect(StarTracking.decide(starCount: 40, hasReference: true) == .align)
    }
}
