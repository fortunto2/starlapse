import Foundation
import SkyKit
import StackKit
import Testing
@testable import SkyMeter

/// The meter is judged on a sky with a known answer: real catalogue stars projected
/// through a known camera, at a chosen zero point and sky brightness, with noise. The
/// phone's reported pointing is then deliberately wrong by what a compass gets wrong.
@Suite("Sky meter")
struct SkyMeterTests {

    static let madrid = GeographicCoordinates(latitude: 40.4, longitude: -3.7)
    /// 23:00 UTC, 20 October 2026: Orion rising, Cassiopeia high.
    static let date: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 23)) ?? .distantPast
    }()

    struct Render {
        let luminance: [Float]
        let width: Int
        let height: Int
    }

    /// Stars at `zeroPoint`, extinction 0.2/airmass, a sky of `sky` mag/arcsec², read noise.
    static func render(
        truth: CameraPointing, sky: Double, zeroPoint: Double = 5.6, width: Int = 1200, height: Int = 900,
        seed: UInt64 = 3
    ) -> Render {
        var pixels = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let area = truth.pixelArea(x: Double(x), y: Double(y), width: width, height: height)
                pixels[y * width + x] = Float(area * pow(10, -0.4 * (sky - zeroPoint)))
            }
        }
        let sigma = 1.3
        for star in StarCatalog.stars where star.magnitude < 7 {
            let horizontal = star.position.horizontal(at: madrid, date: date)
            guard horizontal.altitude > 3,
                  let pixel = truth.project(horizontal, width: width, height: height),
                  pixel.x > 8, pixel.y > 8, pixel.x < Double(width - 8), pixel.y < Double(height - 8)
            else { continue }
            let observed = star.magnitude + 0.2 * SkyMeter.airmass(altitude: horizontal.altitude)
            let flux = pow(10, -0.4 * (observed - zeroPoint))
            let norm = flux / (2 * .pi * sigma * sigma)
            for dy in -6...6 {
                for dx in -6...6 {
                    let px = Int(pixel.x.rounded()) + dx
                    let py = Int(pixel.y.rounded()) + dy
                    let r2 = pow(Double(px) - pixel.x, 2) + pow(Double(py) - pixel.y, 2)
                    pixels[py * width + px] += Float(norm * exp(-r2 / (2 * sigma * sigma)))
                }
            }
        }
        // Read noise at a tenth of the sky level: a stack of a few dozen frames.
        var state = seed
        let level = Double(pixels[(height / 2) * width + width / 2]) * 0.1
        for index in pixels.indices {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let u1 = max(Double(state >> 11) / Double(1 << 53), 1e-12)
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let u2 = Double(state >> 11) / Double(1 << 53)
            let gaussian = (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
            pixels[index] = max(0, pixels[index] + Float(gaussian * level))
        }
        return Render(luminance: pixels, width: width, height: height)
    }

    static let truth = CameraPointing(
        center: HorizontalCoordinates(azimuth: 60, altitude: 45), roll: 0, horizontalFieldOfView: 70
    )

    @Test("The catalogue is the Yale BSC: 9096 stars, Vega where Vega is")
    func catalogue() throws {
        #expect(StarCatalog.stars.count == 9096)
        let vega = try #require(StarCatalog.stars.first {
            abs($0.magnitude - 0.03) < 0.005 && $0.position.declination > 38
        })
        #expect(abs(vega.position.rightAscension - 279.23) < 0.05)
        #expect(abs(vega.position.declination - 38.78) < 0.05)
    }

    @Test("Project and back is the identity, off-axis and rolled")
    func projectionRoundTrip() throws {
        let pointing = CameraPointing(
            center: HorizontalCoordinates(azimuth: 200, altitude: 30), roll: 17, horizontalFieldOfView: 106
        )
        let direction = HorizontalCoordinates(azimuth: 230, altitude: 52)
        let pixel = try #require(pointing.project(direction, width: 4000, height: 3000))
        let back = pointing.direction(x: pixel.x, y: pixel.y, width: 4000, height: 3000)
        #expect(back.separation(from: direction) < 1e-6)
    }

    @Test("A compass 4° off and the buffer turned 90° still find the stars")
    func solvesThroughPointingError() throws {
        let image = Self.render(truth: Self.truth, sky: 20.5)
        var reported = Self.truth
        reported.center = HorizontalCoordinates(azimuth: 64, altitude: 44)
        reported.roll = 93
        let detected = StarDetector(threshold: 5, maxStars: 200)
            .detect(in: image.luminance, width: image.width, height: image.height)
        let solved = PlateMatch.solve(
            detected: detected, pointing: reported, moment: SkyMoment(location: Self.madrid, date: Self.date),
            width: image.width, height: image.height
        )
        let plate = try #require(solved, "\(detected.count) detected")
        #expect(plate.isTrustworthy, "\(plate.matches.count) matches, residual \(plate.residual)")
        #expect(plate.matches.count >= 25, "\(plate.matches.count) matches")
    }

    @Test("Sky brightness comes back within 0.15 mag at 18, 20.5 and 21.5")
    func recoversSkyBrightness() throws {
        for sky in [18.0, 20.5, 21.5] {
            // Exposed the way anyone would: a brighter sky gets a shorter shutter, so the
            // background sits near 5% of full scale whatever the site.
            let image = Self.render(truth: Self.truth, sky: sky, zeroPoint: sky - 14.9)
            var reported = Self.truth
            reported.center = HorizontalCoordinates(azimuth: 63, altitude: 46)
            let reading = try #require(SkyMeter().measure(
                image: LumaImage(pixels: image.luminance, width: image.width, height: image.height),
                pointing: reported, moment: SkyMoment(location: Self.madrid, date: Self.date)
            ), "sky \(sky)")
            #expect(abs(reading.skyBrightness - sky) < 0.15, "sky \(sky) read \(reading.skyBrightness)")
            #expect(reading.uncertainty < 0.1)
        }
    }

    @Test("SQM to naked-eye limit and Bortle follow the published tables")
    func tables() {
        #expect(abs(SkyMeter.nakedEyeLimit(skyBrightness: 21.5) - 6.4) < 0.15)
        let city = SkyMeter.nakedEyeLimit(skyBrightness: 18.0)
        #expect(city > 3.5 && city < 4.5)
        #expect(SkyMeter.bortle(skyBrightness: 22.0) == 1)
        #expect(SkyMeter.bortle(skyBrightness: 21.0) == 4)
        #expect(SkyMeter.bortle(skyBrightness: 17.0) == 9)
    }
}
