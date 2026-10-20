import Foundation
import SkyKit
import StackKit
import Testing
@testable import SkyMeter

/// The overlay's lock, judged the same way as the meter: a rendered sky with a known
/// camera, sensors that are wrong by what phones get wrong, and the question of whether a
/// named star then lands on its own pixel.
@Suite("Sky lock")
struct SkyLockTests {

    /// Portrait, as the preview buffer arrives: 58° across the width on the main lens.
    static let truth = CameraPointing(
        center: HorizontalCoordinates(azimuth: 60, altitude: 45), roll: 0, horizontalFieldOfView: 58
    )
    static let width = 900
    static let height = 1200

    /// The sensors: compass 6° off, a degree low, roll 3° off, the published field 4% wide.
    static func sensors(for truth: CameraPointing) -> CameraPointing {
        CameraPointing(
            center: HorizontalCoordinates(azimuth: truth.center.azimuth - 6, altitude: truth.center.altitude + 1),
            roll: truth.roll - 3,
            horizontalFieldOfView: truth.horizontalFieldOfView * 1.04
        )
    }

    static func solve(_ assumed: CameraPointing) -> PlateMatch? {
        let image = SkyMeterTests.render(truth: truth, sky: 20.5, width: width, height: height)
        let detected = StarDetector(threshold: 5, maxStars: 150)
            .detect(in: image.luminance, width: image.width, height: image.height)
        var options = PlateMatch.Options()
        options.rotations = Array(stride(from: -12.0, through: 12.0, by: 2.0))
        return PlateMatch.solve(
            detected: detected, pointing: assumed,
            moment: SkyMoment(location: SkyMeterTests.madrid, date: SkyMeterTests.date),
            width: width, height: height, options: options
        )
    }

    /// Where the overlay would draw `direction` from these sensors, with or without a lock.
    static func drawn(
        _ direction: HorizontalCoordinates, sensors: CameraPointing, lock: SkyLock?
    ) -> (x: Double, y: Double)? {
        var pointing = sensors
        if let lock {
            let corrected = lock.apply(aim: sensors.center, roll: sensors.roll)
            pointing.center = corrected.aim
            pointing.roll = corrected.roll
            pointing.horizontalFieldOfView *= lock.fieldScale
        }
        return pointing.project(direction, width: width, height: height)
    }

    /// Bright catalogue stars inside the frame.
    static func starsInFrame(_ truth: CameraPointing) -> [HorizontalCoordinates] {
        StarCatalog.stars
            .filter { $0.magnitude < 3 }
            .map { $0.position.horizontal(at: SkyMeterTests.madrid, date: SkyMeterTests.date) }
            .filter { direction in
                guard let pixel = truth.project(direction, width: width, height: height) else { return false }
                return pixel.x > 50 && pixel.y > 50 && pixel.x < Double(width - 50) && pixel.y < Double(height - 50)
            }
    }

    @Test("With the lock, every bright star is drawn within two pixels of where it is")
    func lockPutsStarsOnTheirPixels() throws {
        let assumed = Self.sensors(for: Self.truth)
        let plate = try #require(Self.solve(assumed))
        #expect(SkyLock.accepts(plate, assumed: assumed))
        // Most of the frame's stars, not a handful: a false solution matches few.
        #expect(plate.matches.count >= 100, "\(plate.matches.count) matched")
        let lock = SkyLock(assumed: assumed, solved: plate.pointing, matchedStars: plate.matches.count, at: .now)

        let stars = Self.starsInFrame(Self.truth)
        #expect(stars.count >= 3, "\(stars.count) bright stars in frame")
        var worstCompass = 0.0
        for star in stars {
            let real = try #require(Self.truth.project(star, width: Self.width, height: Self.height))
            let locked = try #require(Self.drawn(star, sensors: assumed, lock: lock))
            let compass = try #require(Self.drawn(star, sensors: assumed, lock: nil))
            #expect(hypot(locked.x - real.x, locked.y - real.y) < 2)
            worstCompass = max(worstCompass, hypot(compass.x - real.x, compass.y - real.y))
        }
        // The test means something only if the compass alone was visibly wrong.
        #expect(worstCompass > 50)
    }

    @Test("The lock is a bias, so it still holds after the phone turns")
    func lockSurvivesATurn() throws {
        let assumed = Self.sensors(for: Self.truth)
        let plate = try #require(Self.solve(assumed))
        let lock = SkyLock(assumed: assumed, solved: plate.pointing, matchedStars: plate.matches.count, at: .now)

        // Turned 20° east and 10° up; the sensors are wrong by the same amounts as before.
        let turned = CameraPointing(
            center: HorizontalCoordinates(azimuth: 80, altitude: 55), roll: 0, horizontalFieldOfView: 58
        )
        let sensors = Self.sensors(for: turned)
        for star in Self.starsInFrame(turned) {
            let real = try #require(turned.project(star, width: Self.width, height: Self.height))
            let locked = try #require(Self.drawn(star, sensors: sensors, lock: lock))
            #expect(hypot(locked.x - real.x, locked.y - real.y) < 6)
        }
    }

    @Test("Fresh for ten minutes, then the compass again")
    func expires() {
        let lock = SkyLock(
            assumed: Self.truth, solved: Self.truth, matchedStars: 20, at: Date(timeIntervalSince1970: 0)
        )
        #expect(lock.isFresh(at: Date(timeIntervalSince1970: 599)))
        #expect(!lock.isFresh(at: Date(timeIntervalSince1970: 601)))
    }

    @Test("Azimuth wraps across north")
    func wraps() {
        var solved = Self.truth
        solved.center = HorizontalCoordinates(azimuth: 2, altitude: 45)
        var assumed = Self.truth
        assumed.center = HorizontalCoordinates(azimuth: 356, altitude: 45)
        let lock = SkyLock(assumed: assumed, solved: solved, matchedStars: 20, at: .now)
        #expect(abs(lock.azimuthOffset - 6) < 1e-9)
        #expect(abs(lock.apply(aim: assumed.center, roll: 0).aim.azimuth - 2) < 1e-9)
    }
}
