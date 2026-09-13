import CoreVideo
import Testing
@testable import Starlapse

/// The ring holds the seconds *before* a meteor, which is the only reason a meteor can be
/// filmed at all. It is also the second place in this app where a frame size decided by the
/// hardware turns into hundreds of megabytes without anyone asking — the first one closed
/// the app on launch for a reviewer who granted camera access.
@Suite("The detector's ring buffer")
struct FrameRingBufferTests {

    static func frame(width: Int, height: Int) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferMetalCompatibilityKey as String: true] as CFDictionary,
            &buffer
        )
        return buffer!   // swiftlint:disable:this force_unwrapping
    }

    @Test("At the resolution the detector asks for, it holds what it was asked for")
    func keepsTheRequestedWindowAtDetectorResolution() {
        let ring = FrameRingBuffer(frames: 10)
        ring.append(Self.frame(width: 1920, height: 1080), timestamp: 0)

        #expect(ring.frameCapacity == 10)
    }

    @Test("A full-resolution frame shortens the ring rather than the session")
    func shrinksTheRingWhenFramesAreHuge() {
        let ring = FrameRingBuffer(frames: 10)
        ring.append(Self.frame(width: 4032, height: 3024), timestamp: 0)

        #expect(ring.frameCapacity < 10)
        #expect(ring.frameCapacity >= 2)
        #expect(ring.frameCapacity * 4032 * 3024 * 4 <= FrameRingBuffer.byteBudget)
    }

    @Test("Older frames fall off the end; the ring never grows past its capacity")
    func evictsRatherThanGrows() {
        let ring = FrameRingBuffer(frames: 4)
        for index in 0..<12 {
            ring.append(Self.frame(width: 320, height: 240), timestamp: Double(index))
        }

        let history = ring.history()
        #expect(history.count == 4)
        #expect(history.map(\.timestamp) == [8, 9, 10, 11])
    }
}
