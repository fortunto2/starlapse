import Foundation
import simd
import Testing
@testable import StackKit

@Suite("Camera turn")
struct CameraTurnTests {

    static func degrees(_ value: Double) -> Double { value * .pi / 180 }
    static func turn(_ degrees: Double, _ axis: SIMD3<Double>) -> simd_quatd {
        simd_quatd(angle: Self.degrees(degrees), axis: axis)
    }

    @Test("A roll about the camera's axis is read whole, a tilt is not read as a roll")
    func twistIsTheRollOnly() {
        let held = Self.turn(20, [1, 0, 0])
        let rolled = held * Self.turn(10, [0, 0, 1])
        #expect(abs(CameraTurn.twist(from: held, to: rolled) - Self.degrees(10)) < 1e-9)
        let tilted = held * Self.turn(3, [1, 0, 0]) * Self.turn(2, [0, 1, 0])
        #expect(CameraTurn.twist(from: held, to: tilted) < Self.degrees(0.1))
    }

    @Test("A hand that rolled half a degree cannot carry a frame turned twenty")
    func bathroomFrameIsRefused() {
        let allowed = CameraTurn.allowance(gyroTwist: Self.degrees(0.5), elapsed: 30)
        #expect(allowed < Self.degrees(2))
        #expect(Self.degrees(20) > allowed)
    }

    @Test("An hour on a tripod still follows the sky's turn")
    func skyTurnIsAllowed() {
        #expect(CameraTurn.allowance(gyroTwist: 0, elapsed: 3600) > Self.degrees(15))
        #expect(CameraTurn.allowance(gyroTwist: nil, elapsed: 0) == CameraTurn.blindLimit)
    }
}
