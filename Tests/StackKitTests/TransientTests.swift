import CoreGraphics
import Foundation
import Testing
@testable import StackKit

/// A meteor detector cannot be tested by pointing a phone at the sky and waiting — the
/// events are rare, unrepeatable, and you find out it was broken hours later. So the sky is
/// synthesised: a star field that stays put, and the things that actually happen over it.
@Suite("Transient detection")
struct TransientTests {

    static let width = 320
    static let height = 240

    /// A static star field, the same in both frames — this is what registration guarantees.
    static func baseFrame(seed: UInt64 = 5) -> [Float] {
        let stars = StackingTests.starField(count: 40, width: width, height: height, seed: seed)
        return StackingTests.renderField(stars: stars, width: width, height: height)
    }

    /// Draw a streak, the way a meteor lands on a long exposure.
    static func drawStreak(
        into buffer: inout [Float],
        from start: CGPoint,
        to end: CGPoint,
        brightness: Float = 0.8,
        thickness: Double = 1.4
    ) {
        let steps = Int(max(abs(end.x - start.x), abs(end.y - start.y)) * 2)
        guard steps > 0 else { return }
        let radius = Int(thickness.rounded(.up))

        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let px = start.x + (end.x - start.x) * t
            let py = start.y + (end.y - start.y) * t

            for dy in -radius...radius {
                for dx in -radius...radius {
                    let x = Int(px) + dx
                    let y = Int(py) + dy
                    guard x >= 0, x < width, y >= 0, y < height else { continue }
                    let distance = ((Double(x) - px) * (Double(x) - px)
                        + (Double(y) - py) * (Double(y) - py)).squareRoot()
                    let falloff = exp(-(distance * distance) / (2 * thickness * thickness))
                    buffer[y * width + x] += brightness * Float(falloff)
                }
            }
        }
    }

    // MARK: - What it must catch

    @Test("A meteor streak is detected and identified as a streak")
    func detectsMeteor() {
        let previous = Self.baseFrame()
        var current = previous
        Self.drawStreak(
            into: &current,
            from: CGPoint(x: 80, y: 60),
            to: CGPoint(x: 190, y: 130)
        )

        guard let event = TransientDetector().detect(
            current: current, previous: previous, width: Self.width, height: Self.height
        ) else {
            Issue.record("Missed the meteor")
            return
        }

        #expect(event.isStreak)
        // Centre should land on the middle of the streak.
        #expect(abs(event.x - 135) < 12)
        #expect(abs(event.y - 95) < 12)
    }

    @Test("The reported angle follows the streak's direction")
    func measuresDirection() {
        let previous = Self.baseFrame()

        var horizontal = previous
        Self.drawStreak(
            into: &horizontal,
            from: CGPoint(x: 60, y: 120), to: CGPoint(x: 240, y: 120)
        )
        let flat = TransientDetector().detect(
            current: horizontal, previous: previous, width: Self.width, height: Self.height
        )
        #expect(flat != nil)
        #expect(abs(flat?.angle ?? 90) < 8)

        var diagonal = previous
        Self.drawStreak(
            into: &diagonal,
            from: CGPoint(x: 60, y: 60), to: CGPoint(x: 180, y: 180)
        )
        let slanted = TransientDetector().detect(
            current: diagonal, previous: previous, width: Self.width, height: Self.height
        )
        #expect(slanted != nil)
        #expect(abs((slanted?.angle ?? 0) - 45) < 10)
    }

    @Test("A faint meteor is still caught")
    func detectsFaintMeteor() {
        let previous = Self.baseFrame()
        var current = previous
        Self.drawStreak(
            into: &current,
            from: CGPoint(x: 100, y: 80), to: CGPoint(x: 170, y: 120),
            brightness: 0.18
        )

        #expect(TransientDetector().detect(
            current: current, previous: previous, width: Self.width, height: Self.height
        ) != nil)
    }

    // MARK: - What it must ignore

    @Test("An unchanged sky triggers nothing")
    func ignoresStillSky() {
        let frame = Self.baseFrame()
        #expect(TransientDetector().detect(
            current: frame, previous: frame, width: Self.width, height: Self.height
        ) == nil)
    }

    @Test("Sensor noise alone triggers nothing")
    func ignoresNoise() {
        let previous = Self.baseFrame()
        var current = previous
        // Per-pixel jitter, deterministic.
        var state: UInt64 = 11
        for index in 0..<current.count {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let jitter = Float((state >> 33) % 1000) / 1000.0 - 0.5
            current[index] += jitter * 0.02
        }

        #expect(TransientDetector().detect(
            current: current, previous: previous, width: Self.width, height: Self.height
        ) == nil)
    }

    @Test("A hot pixel is too small to count")
    func ignoresHotPixel() {
        let previous = Self.baseFrame()
        var current = previous
        current[120 * Self.width + 200] = 1.0
        current[121 * Self.width + 200] = 0.9

        #expect(TransientDetector().detect(
            current: current, previous: previous, width: Self.width, height: Self.height
        ) == nil)
    }

    @Test("Cloud or headlights brightening the frame is not an event")
    func ignoresWholeFrameBrightening() {
        let previous = Self.baseFrame()
        var current = previous
        // A car's headlights sweeping the horizon, or moonrise: a large area lifts at once.
        for y in 0..<Self.height {
            for x in 0..<Self.width where y > Self.height / 2 {
                current[y * Self.width + x] += 0.25
            }
        }

        #expect(TransientDetector().detect(
            current: current, previous: previous, width: Self.width, height: Self.height
        ) == nil)
    }

    @Test("A defocused blob is detected but not called a streak")
    func distinguishesBlobFromStreak() {
        let previous = Self.baseFrame()
        var current = previous
        // A round glow — a lens flare or a distant lamp coming on.
        let centreX = 160.0
        let centreY = 120.0
        for y in 0..<Self.height {
            for x in 0..<Self.width {
                let distance = ((Double(x) - centreX) * (Double(x) - centreX)
                    + (Double(y) - centreY) * (Double(y) - centreY)).squareRoot()
                guard distance < 9 else { continue }
                current[y * Self.width + x] += Float(0.7 * exp(-distance * distance / 30))
            }
        }

        let event = TransientDetector().detect(
            current: current, previous: previous, width: Self.width, height: Self.height
        )
        #expect(event != nil)
        // Round: it should not pass the streak test that a meteor does.
        #expect(!(event?.isStreak ?? true))
    }

    @Test("A star that merely twinkles does not trigger")
    func ignoresScintillation() {
        let previous = Self.baseFrame()
        var current = previous
        // Atmospheric scintillation: existing stars vary by a few percent, in place.
        for index in 0..<current.count where current[index] > 0.2 {
            current[index] *= 1.06
        }

        #expect(TransientDetector().detect(
            current: current, previous: previous, width: Self.width, height: Self.height
        ) == nil)
    }
}
