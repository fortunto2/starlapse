#if DEBUG
import CoreVideo
import Foundation
import simd

/// DEBUG-only stand-in for the camera, for the Simulator — which has none.
///
/// Why it exists: App Store screenshots. The Simulator has no camera, so the viewfinder is a
/// black rectangle and every screenshot looks like a broken app. This synthesises a night
/// sky and feeds it through the *real* pipeline instead, so what ends up on screen is
/// genuinely this app's output — the same stacking, the same star alignment, the same asinh
/// curve — just from a sky we computed rather than one we photographed.
///
/// It stays inside `#if DEBUG` and never ships.
///
/// The stars rotate about the celestial pole at the true sidereal rate, so alignment has
/// something real to solve and the trails curve the way they actually would.
///
/// A meteor crosses the frame on one frame in every cycle — because that is what the app is
/// built to catch, and during the Perseids a real user sees dozens an hour. It is drawn into
/// the *sky*, not onto the screenshot, so the detector finds it the same way it finds a real
/// one: frame differencing, connected regions, streak shape. What the screenshot shows is a
/// genuine detection.
///
/// No comet, though. Those come every few years, and a screenshot promising one would be
/// promising a buyer something they will not get.
final class StubSkySource: @unchecked Sendable {

    private let width: Int
    private let height: Int
    private var pool: CVPixelBufferPool?
    private var frameIndex = 0

    private struct Star {
        let x: Double
        let y: Double
        let magnitude: Double
        /// 0 = blue-white, 1 = orange. Real stars vary, and it shows in a stacked image.
        let warmth: Double
    }

    private let stars: [Star]

    /// Shutter × ISO in force, when the stub sky carries a Moon (`UITEST_MOON=1`). The disc
    /// answers the exposure, so Moon mode's meter can be watched converging in the Simulator.
    var moonLight: Double?

    /// Frames on which a meteor crosses. Frequent, because a screenshot has to catch one —
    /// and in a stacked shot it stays in the result anyway, which is exactly what happens
    /// on a real Perseid night.
    private let meteorFrame = 2
    private let meteorPeriod = 4
    /// Where the sky turns about — off-frame, as it is for anyone not shooting the pole.
    private let poleX: Double
    private let poleY: Double

    /// Sidereal rotation per frame, radians. The sky turns 15°/hour; at one frame a second
    /// that is a hair over four arcseconds, which is what the aligner is built to track.
    private let rotationPerFrame = 15.0 / 3600.0 * .pi / 180.0 * 12

    init(width: Int = 1170, height: Int = 2532, seed: UInt64 = 20260813) {
        self.width = width
        self.height = height
        poleX = Double(width) * 0.5
        poleY = Double(height) * 1.35

        var state = seed
        func random() -> Double {
            state ^= state >> 12
            state ^= state << 25
            state ^= state >> 27
            return Double((state &* 2_685_821_657_736_338_717) >> 11) / Double(1 << 53)
        }

        // Magnitude distribution: each step fainter is roughly 2.5× more numerous, which is
        // why a real sky looks like a few bright anchors scattered in a haze of faint ones.
        var built: [Star] = []
        for _ in 0..<2200 {
            let roll = random()
            let magnitude = 1.2 + pow(roll, 0.45) * 5.0
            built.append(Star(
                x: random() * Double(width),
                y: random() * Double(height),
                magnitude: magnitude,
                warmth: random()
            ))
        }
        stars = built

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        var created: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &created)
        pool = created
    }

    /// One frame of sky, rotated a little further than the last.
    func nextFrame() -> CVPixelBuffer? {
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        let angle = Double(frameIndex) * rotationPerFrame
        frameIndex += 1

        render(into: pixels, bytesPerRow: bytesPerRow, angle: angle)
        return buffer
    }

    private func render(into pixels: UnsafeMutablePointer<UInt8>, bytesPerRow: Int, angle: Double) {
        drawBackground(into: pixels, bytesPerRow: bytesPerRow)
        drawMilkyWay(into: pixels, bytesPerRow: bytesPerRow)
        drawStars(into: pixels, bytesPerRow: bytesPerRow, angle: angle)

        // No meteor across the Moon: one every fourth frame is a screenshot's convenience,
        // and through the disc it reads as a blown-out Moon to the meter.
        if moonLight == nil, (frameIndex - 1) % meteorPeriod == meteorFrame {
            drawMeteor(into: pixels, bytesPerRow: bytesPerRow)
        }
        if let moonLight {
            drawMoon(into: pixels, bytesPerRow: bytesPerRow, light: moonLight)
        }
    }

    /// A full Moon with three maria, jittered a few pixels per frame like a hand-held phone,
    /// and soft on every third frame like a shaken one. Its highlands reach linear 1.0 at
    /// 1/250 s and ISO 55, roughly what a real full Moon does through the telephoto.
    private func drawMoon(into pixels: UnsafeMutablePointer<UInt8>, bytesPerRow: Int, light: Double) {
        let jitter = Double((frameIndex * 7919) % 7) - 3
        let centerX = Double(width) * 0.5 + jitter
        let centerY = Double(height) * 0.42 - jitter * 0.6
        let radius = 150.0
        let softness = frameIndex % 3 == 0 ? 7.0 : 1.2
        let gain = light / (55.0 / 250.0)
        // Maria as offset from the centre and radius, in pixels.
        let maria: [SIMD3<Double>] = [[-45, -30, 50], [40, 10, 38], [-10, 60, 30]]

        let lowY = max(0, Int(centerY - radius - 10)), highY = min(height - 1, Int(centerY + radius + 10))
        let lowX = max(0, Int(centerX - radius - 10)), highX = min(width - 1, Int(centerX + radius + 10))
        for py in lowY...highY {
            for px in lowX...highX {
                let dx = Double(px) - centerX, dy = Double(py) - centerY
                let inside = min(1, max(0, (radius - (dx * dx + dy * dy).squareRoot()) / softness + 0.5))
                guard inside > 0 else { continue }
                var albedo = 1.0
                for mare in maria {
                    let mx = dx - mare.x, my = dy - mare.y
                    let depth = min(1, max(0, (mare.z - (mx * mx + my * my).squareRoot()) / (softness * 2) + 0.5))
                    albedo -= 0.3 * depth
                }
                let linear = min(1, albedo * gain * inside)
                let value = 255 * pow(linear, 1 / 2.2)
                let offset = py * bytesPerRow + px * 4
                pixels[offset] = UInt8(max(Double(pixels[offset]), value * 0.94))
                pixels[offset + 1] = UInt8(max(Double(pixels[offset + 1]), value * 0.97))
                pixels[offset + 2] = UInt8(max(Double(pixels[offset + 2]), value))
            }
        }
    }

    /// A Perseid: a bright streak, brightest two-thirds along, gone in one frame.
    ///
    /// Drawn radiating away from the shower's radiant, which is what real ones do — and
    /// the reason the app tells you to aim 40° off it rather than at it.
    private func drawMeteor(into pixels: UnsafeMutablePointer<UInt8>, bytesPerRow: Int) {
        let startX = Double(width) * 0.17
        let startY = Double(height) * 0.30
        let endX = Double(width) * 0.78
        let endY = Double(height) * 0.62
        let steps = 900
        let thickness = 2.1

        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let px = startX + (endX - startX) * t
            let py = startY + (endY - startY) * t

            // Fades in, peaks around two thirds, then cuts out — the way one burns up.
            let envelope: Double
            if t < 0.62 {
                envelope = pow(t / 0.62, 2.4)
            } else {
                envelope = pow(max(0, 1 - (t - 0.62) / 0.38), 2.6)
            }
            let brightness = 250.0 * envelope
            guard brightness > 1 else { continue }

            // Thicker where it burns brightest, hair-thin at the ends — that taper is what
            // a straight line of constant width never looks like.
            let localThickness = thickness * (0.45 + 0.55 * envelope)
            let radius = Int((localThickness * 3).rounded(.up))
            for offsetY in -radius...radius {
                for offsetX in -radius...radius {
                    let x = Int(px) + offsetX
                    let y = Int(py) + offsetY
                    guard x >= 0, x < width, y >= 0, y < height else { continue }

                    let dx = Double(x) - px
                    let dy = Double(y) - py
                    let falloff = exp(-(dx * dx + dy * dy) / (2 * localThickness * localThickness))
                    let value = brightness * falloff
                    guard value > 0.6 else { continue }

                    let offset = y * bytesPerRow + x * 4
                    // Perseids run blue-green from their entry speed — 59 km/s.
                    pixels[offset] = UInt8(min(255, Double(pixels[offset]) + value))
                    pixels[offset + 1] = UInt8(min(255, Double(pixels[offset + 1]) + value * 0.97))
                    pixels[offset + 2] = UInt8(min(255, Double(pixels[offset + 2]) + value * 0.82))
                }
            }
        }
    }

    /// Light pollution gradient from the horizon, the way any sky within reach of a town
    /// actually looks.
    private func drawBackground(into pixels: UnsafeMutablePointer<UInt8>, bytesPerRow: Int) {
        for y in 0..<height {
            let horizon = 1.0 - Double(y) / Double(height)
            let glow = pow(horizon, 3.4) * 17
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                pixels[offset] = UInt8(min(255, 7 + glow * 1.25))     // B
                pixels[offset + 1] = UInt8(min(255, 5 + glow * 0.85))  // G
                pixels[offset + 2] = UInt8(min(255, 4 + glow * 0.55))  // R
                pixels[offset + 3] = 255
            }
        }

    }

    /// The Milky Way: a diagonal band of unresolved light.
    private func drawMilkyWay(into pixels: UnsafeMutablePointer<UInt8>, bytesPerRow: Int) {
        let bandAngle: Double = -0.55
        let bandSin = sin(bandAngle)
        let bandCos = cos(bandAngle)
        let bandCentreX = Double(width) * 0.62
        let bandCentreY = Double(height) * 0.42
        let bandWidth: Double = 210

        for y in 0..<height {
            let dy = Double(y) - bandCentreY
            for x in 0..<width {
                let dx = Double(x) - bandCentreX
                let across = -dx * bandSin + dy * bandCos
                let falloff = exp(-(across * across) / (2 * bandWidth * bandWidth))
                guard falloff > 0.01 else { continue }
                let value = falloff * 11
                let offset = y * bytesPerRow + x * 4
                pixels[offset] = UInt8(min(255, Double(pixels[offset]) + value * 1.1))
                pixels[offset + 1] = UInt8(min(255, Double(pixels[offset + 1]) + value))
                pixels[offset + 2] = UInt8(min(255, Double(pixels[offset + 2]) + value * 0.9))
            }
        }

    }

    /// Stars, rotated about the pole at the sidereal rate.
    private func drawStars(into pixels: UnsafeMutablePointer<UInt8>, bytesPerRow: Int, angle: Double) {
        let cosine = cos(angle)
        let sine = sin(angle)

        for star in stars {
            let dx = star.x - poleX
            let dy = star.y - poleY
            let x = poleX + cosine * dx - sine * dy
            let y = poleY + sine * dx + cosine * dy
            guard x > -8, x < Double(width) + 8, y > -8, y < Double(height) + 8 else { continue }

            // Brightness from magnitude, on the real logarithmic scale.
            let brightness = pow(2.512, 3.4 - star.magnitude) * 42
            let sigma = 1.0 + max(0, 2.6 - star.magnitude) * 0.35
            let radius = Int((sigma * 3).rounded(.up))

            for offsetY in -radius...radius {
                for offsetX in -radius...radius {
                    let px = Int(x) + offsetX
                    let py = Int(y) + offsetY
                    guard px >= 0, px < width, py >= 0, py < height else { continue }

                    let deltaX = Double(px) - x
                    let deltaY = Double(py) - y
                    let falloff = exp(-(deltaX * deltaX + deltaY * deltaY) / (2 * sigma * sigma))
                    let value = brightness * falloff
                    guard value > 0.5 else { continue }

                    let offset = py * bytesPerRow + px * 4
                    // Warm stars lean red, cool ones blue — visible once stacked.
                    let red = value * (0.75 + star.warmth * 0.25)
                    let blue = value * (1.0 - star.warmth * 0.3)
                    pixels[offset] = UInt8(min(255, Double(pixels[offset]) + blue))
                    pixels[offset + 1] = UInt8(min(255, Double(pixels[offset + 1]) + value * 0.9))
                    pixels[offset + 2] = UInt8(min(255, Double(pixels[offset + 2]) + red))
                }
            }
        }
    }
}
#endif
