import Testing
@testable import StackKit

/// Moon mode meters, aligns and selects on the lunar disc, so each step is checked against a
/// disc drawn where we chose, at a brightness we chose.
@Suite("Moon")
struct MoonTests {

    static let width = 160
    static let height = 120

    /// A uniform disc on a dark, faintly noisy sky. `edgeBlur` softens the limb the way
    /// shake or bad seeing does.
    static func frame(
        centerX: Double = 80, centerY: Double = 60, radius: Double = 18,
        brightness: Float = 0.5, background: Float = 0.01, edgeBlur: Double = 0.5,
        lamp: (x: Int, y: Int)? = nil
    ) -> [Float] {
        var pixels = [Float](repeating: background, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let distance = ((Double(x) - centerX) * (Double(x) - centerX)
                    + (Double(y) - centerY) * (Double(y) - centerY)).squareRoot()
                let inside = min(1, max(0, (radius - distance) / max(edgeBlur, 0.01) + 0.5))
                // A little texture so the noise estimate is not zero.
                let texture = Float((x * 7 + y * 13) % 5) * 0.0004
                pixels[y * width + x] = min(1, background + texture + brightness * Float(inside))
            }
        }
        if let lamp {
            for dy in -1...1 { for dx in -1...1 { pixels[(lamp.y + dy) * width + lamp.x + dx] = 1 } }
        }
        return pixels
    }

    // MARK: - Finding the disc

    @Test("The disc is found where it was drawn, at its size")
    func locatesTheDisc() throws {
        let sky = Self.frame(centerX: 70.5, centerY: 52)
        let disc = try #require(MoonDisc.locate(in: sky, width: Self.width, height: Self.height))
        #expect(abs(disc.x - 70.5) < 0.3)
        #expect(abs(disc.y - 52) < 0.3)
        #expect(abs(disc.radius - 18) < 1)
        #expect(disc.clippedFraction == 0)
    }

    @Test("A small bright lamp does not pass for the Moon")
    func ignoresALampWhenTheMoonIsThere() throws {
        let disc = try #require(MoonDisc.locate(
            in: Self.frame(brightness: 0.5, lamp: (x: 10, y: 10)), width: Self.width, height: Self.height
        ))
        #expect(abs(disc.x - 80) < 0.5)
    }

    @Test("An empty sky has no Moon")
    func emptySky() {
        let sky = Self.frame(brightness: 0)
        #expect(MoonDisc.locate(in: sky, width: Self.width, height: Self.height) == nil)
    }

    @Test("A blown-out disc says so")
    func clipping() throws {
        let sky = Self.frame(brightness: 1.5)
        let disc = try #require(MoonDisc.locate(in: sky, width: Self.width, height: Self.height))
        #expect(disc.clippedFraction > 0.5)
    }

    // MARK: - Exposure

    static let limits = ExposureMeter.Limits(shutter: 1.0 / 8000...1.0 / 60, iso: 50...3200)

    @Test("A blown disc steps the shutter down hard, harder when it is mostly white")
    func clippedStepsDown() {
        let next = ExposureMeter.next(
            Exposure(shutter: 1.0 / 30, iso: 50),
            reading: LightReading(level: 1, clippedFraction: 0.8),
            target: ExposureMeter.moonTarget, limits: Self.limits
        )
        #expect(next.shutter <= 1.0 / 240)
        #expect(next.iso == 50)
    }

    @Test("An underexposed disc lengthens the shutter at base ISO")
    func darkGoesLonger() {
        let next = ExposureMeter.next(
            Exposure(shutter: 1.0 / 2000, iso: 50),
            reading: LightReading(level: 0.175, clippedFraction: 0),
            target: ExposureMeter.moonTarget, limits: Self.limits
        )
        #expect(abs(next.shutter - 1.0 / 500) < 1e-6)
        #expect(next.iso == 50)
    }

    @Test("Past the shake limit, ISO takes the rest")
    func isoAfterShutter() {
        // A thin crescent: wants 8× the light of 1/120 s.
        let next = ExposureMeter.next(
            Exposure(shutter: 1.0 / 120, iso: 50),
            reading: LightReading(level: 0.0875, clippedFraction: 0),
            target: ExposureMeter.moonTarget, limits: Self.limits
        )
        #expect(next.shutter == 1.0 / 60)
        #expect(abs(next.iso - 200) < 0.5)
    }

    @Test("Close to the target, nothing moves")
    func holdsNearTarget() {
        let next = ExposureMeter.next(
            Exposure(shutter: 1.0 / 1000, iso: 50),
            reading: LightReading(level: 0.66, clippedFraction: 0),
            target: ExposureMeter.moonTarget, limits: Self.limits
        )
        #expect(next.shutter == 1.0 / 1000)
        #expect(next.iso == 50)
    }

    // MARK: - Lucky frames

    @Test("A shaken frame scores softer than a steady one")
    func sharpnessFollowsTheLimb() throws {
        let sharp = Self.frame(edgeBlur: 0.5)
        let soft = Self.frame(edgeBlur: 4)
        let disc = try #require(MoonDisc.locate(in: sharp, width: Self.width, height: Self.height))
        let sharpScore = disc.sharpness(in: sharp, width: Self.width, height: Self.height)
        let softScore = disc.sharpness(in: soft, width: Self.width, height: Self.height)
        #expect(sharpScore > softScore * 1.5)
    }

    @Test("After the warm-up, only frames at or above the running median are kept")
    func luckyKeepsTheBetterHalf() {
        var selector = LuckySelector(warmup: 4)
        let warmup = [5.0, 6, 7, 8].map { selector.accepts($0) }
        #expect(warmup.allSatisfy { $0 })
        let soft = selector.accepts(5.5)
        let steady = selector.accepts(7.5)
        #expect(!soft)
        #expect(steady)
    }

    @Test("Each kept frame is shifted onto the first one's disc")
    func trackerShiftsOntoReference() throws {
        var tracker = MoonTracker()
        let first = tracker.register(Self.frame(centerX: 80, centerY: 60), width: Self.width, height: Self.height)
        #expect(first == .identity)
        let shift = tracker.register(Self.frame(centerX: 83, centerY: 58), width: Self.width, height: Self.height)
        let drifted = try #require(shift)
        #expect(abs(drifted.translationX + 3) < 0.2)
        #expect(abs(drifted.translationY - 2) < 0.2)
    }

    @Test("One saturated pixel on the disc is not a blown-out Moon")
    func onePixelIsNotClipping() throws {
        var sky = Self.frame(brightness: 0.6)
        sky[60 * Self.width + 80] = 1
        let disc = try #require(MoonDisc.locate(in: sky, width: Self.width, height: Self.height))
        #expect(disc.peak < 0.7)
        let next = ExposureMeter.next(
            Exposure(shutter: 1.0 / 1000, iso: 50),
            reading: LightReading(level: disc.peak, clippedFraction: disc.clippedFraction),
            target: ExposureMeter.moonTarget, limits: Self.limits
        )
        #expect(next.shutter >= 1.0 / 1000)
    }

    // MARK: - Scene

    static let sceneLimits = ExposureMeter.Limits(shutter: 1.0 / 8000...1.0 / 30, iso: 50...3200)

    @Test("A scene's level is its median, and the white part is counted")
    func sceneLevel() {
        var frame = [Float](repeating: 0.3, count: 10_000)
        for index in 0..<7_000 { frame[index] = 1 }
        let reading = SceneLevel.measure(frame)
        #expect(reading.level == 1)
        #expect(abs(reading.clippedFraction - 0.7) < 0.01)
        #expect(abs(SceneLevel.measure([Float](repeating: 0.05, count: 400)).level - 0.05) < 1e-6)
    }

    @Test("Daylight on night framing comes down five stops a reading")
    func whiteFramingDropsFast() {
        let night = Exposure(shutter: 1.0 / 8, iso: 3200)
        let next = ExposureMeter.next(
            night, reading: LightReading(level: 1, clippedFraction: 0.9),
            target: ExposureMeter.sceneTarget, limits: Self.sceneLimits
        )
        #expect(abs(next.light - night.light / 32) < 1e-6)
    }

    @Test("A dim scene is brought to mid-grey at base ISO")
    func sceneToMidGrey() {
        let next = ExposureMeter.next(
            Exposure(shutter: 1.0 / 1000, iso: 50), reading: LightReading(level: 0.045, clippedFraction: 0),
            target: ExposureMeter.sceneTarget, limits: Self.sceneLimits
        )
        #expect(abs(next.shutter - 1.0 / 250) < 1e-6)
        #expect(next.iso == 50)
    }

    @Test("A white screen drops eight stops in one reading")
    func whiteScreenDropsEightStops() {
        let night = Exposure(shutter: 1.0 / 8, iso: 3200)
        let next = ExposureMeter.next(
            night, reading: LightReading(level: 1, clippedFraction: 0.99),
            target: ExposureMeter.sceneTarget, limits: Self.sceneLimits
        )
        #expect(abs(next.light - night.light / 256) < 1e-6)
    }
}
