import Foundation
import os
import StackKit

/// The last few seconds of gyroscope readings, shared between the main actor that receives
/// them and the capture queue that judges each frame by them.
///
/// Times are seconds on the host clock: `CMDeviceMotion.timestamp` and the camera's
/// presentation timestamps both count from the same boot-time clock, so a frame and the
/// readings taken while it was exposed can be matched directly.
final class ShakeLog: Sendable {

    /// Twenty seconds at 30 Hz: longer than any frame, short enough to copy per frame.
    private static let capacity = 600

    private let samples = OSAllocatedUnfairLock(initialState: [MotionSample]())

    func record(time: Double, rate: Double) {
        samples.withLock { buffer in
            buffer.append(MotionSample(time: time, rate: rate))
            if buffer.count > Self.capacity { buffer.removeFirst(buffer.count - Self.capacity) }
        }
    }

    func moved(frameTime: Double, exposure: Double) -> Bool {
        // Only the readings that can matter are copied out of the lock.
        let window = samples.withLock { buffer in
            buffer.filter { abs($0.time - frameTime) <= exposure + 0.1 }
        }
        return Steadiness.moved(window, frameTime: frameTime, exposure: exposure)
    }

    /// Mean rate over the last `seconds`, or nil with no readings in that span.
    func recentRate(over seconds: Double = 1) -> Double? {
        samples.withLock { buffer in
            guard let last = buffer.last else { return nil }
            return Steadiness.meanRate(buffer, from: last.time - seconds, to: last.time)
        }
    }
}
