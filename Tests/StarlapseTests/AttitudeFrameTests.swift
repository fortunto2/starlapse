import CoreMotion
import Testing
@testable import Starlapse

/// Which reference frame to ask CoreMotion for. True north asked for before location was
/// authorised delivered nothing on an iPhone 17 Pro: markers drawn once, never moved.
@Suite("Choosing an attitude reference frame")
struct AttitudeFrameTests {

    static let all: CMAttitudeReferenceFrame = [
        .xArbitraryZVertical, .xArbitraryCorrectedZVertical, .xMagneticNorthZVertical, .xTrueNorthZVertical,
    ]

    @Test("True north only once location is authorised")
    func trueNorthNeedsLocation() {
        let withLocation = AttitudeProvider.preferredFrame(available: Self.all, locationAuthorized: true)
        let without = AttitudeProvider.preferredFrame(available: Self.all, locationAuthorized: false)
        #expect(withLocation == .xTrueNorthZVertical)
        #expect(without == .xMagneticNorthZVertical)
    }

    @Test("No magnetometer still gives a level horizon")
    func noMagnetometer() {
        let frame = AttitudeProvider.preferredFrame(
            available: [.xArbitraryZVertical, .xArbitraryCorrectedZVertical], locationAuthorized: true
        )
        #expect(frame == .xArbitraryCorrectedZVertical)
    }

    @Test("Fallbacks step down and stop")
    func fallbackChain() {
        #expect(AttitudeProvider.fallback(after: .xTrueNorthZVertical) == .xMagneticNorthZVertical)
        #expect(AttitudeProvider.fallback(after: .xMagneticNorthZVertical) == .xArbitraryCorrectedZVertical)
        #expect(AttitudeProvider.fallback(after: .xArbitraryCorrectedZVertical) == nil)
    }
}
