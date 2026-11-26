import Testing
@testable import StackKit

@Suite("A frame shot while the phone moved is not stacked")
struct SteadinessTests {

    static func samples(rate: Double, from start: Double = 0, to end: Double = 3) -> [MotionSample] {
        stride(from: start, through: end, by: 1.0 / 30).map { MotionSample(time: $0, rate: rate) }
    }

    @Test("Tripod gyro noise never rejects a one-second frame")
    func tripodKeeps() {
        #expect(!Steadiness.moved(Self.samples(rate: 0.001), frameTime: 1.5, exposure: 1))
    }

    @Test("A hand-held one-second frame is rejected")
    func handheldRejects() {
        #expect(Steadiness.moved(Self.samples(rate: 0.03), frameTime: 1.5, exposure: 1))
    }

    @Test("The same hand passes at a Moon shutter, where the blur is a fraction of a pixel")
    func shortShutterKeeps() {
        #expect(!Steadiness.moved(Self.samples(rate: 0.03), frameTime: 1.5, exposure: 0.001))
    }

    @Test("No gyroscope samples for the frame means no verdict, so the frame is kept")
    func noSamplesKeeps() {
        #expect(!Steadiness.moved(Self.samples(rate: 0.5, from: 10, to: 12), frameTime: 1.5, exposure: 1))
        #expect(Steadiness.meanRate([], from: 0, to: 1) == nil)
    }

    @Test("A bump in the middle of the exposure is enough")
    func bumpRejects() {
        let still = Self.samples(rate: 0.001)
        let bump = stride(from: 1.4, through: 1.8, by: 1.0 / 30).map { MotionSample(time: $0, rate: 0.1) }
        #expect(Steadiness.moved((still + bump).sorted { $0.time < $1.time }, frameTime: 1.5, exposure: 1))
    }

    @Test("A steady phone keeps the full second; a hand gets a frame it can hold sharp")
    func handheldShutter() {
        #expect(Steadiness.handheldExposure(rate: 0.001, longest: 1) == 1)
        #expect(Steadiness.handheldExposure(rate: nil, longest: 1) == 1)
        let hand = Steadiness.handheldExposure(rate: 0.03, longest: 1)
        #expect(hand < 0.1 && hand > 1.0 / 30)
        // The gate must keep what the shutter shoots at the rate it was chosen for.
        #expect(!Steadiness.moved(Self.samples(rate: 0.03), frameTime: 1.5, exposure: hand))
        #expect(Steadiness.handheldExposure(rate: 5, longest: 1) == 1.0 / 30)
        #expect(Steadiness.handheldExposure(rate: 0.03, longest: 0.01) == 0.01)
    }

    @Test("A shorter frame gets the gain back, up to the sensor's ceiling")
    func gainCompensation() {
        #expect(Steadiness.compensatedISO(400, from: 1, to: 0.25, ceiling: 6400) == 1600)
        #expect(Steadiness.compensatedISO(1600, from: 1, to: 0.1, ceiling: 3200) == 3200)
        #expect(Steadiness.compensatedISO(800, from: 1, to: 1, ceiling: 3200) == 800)
    }
}
