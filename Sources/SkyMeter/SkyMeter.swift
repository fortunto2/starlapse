import Foundation
import SkyKit
import StackKit

/// What one shot says about the sky it was taken under.
public struct SkyReading: Sendable, Hashable, Codable {
    /// Sky surface brightness at the frame centre's altitude, in V magnitudes per square
    /// arcsecond: what a Sky Quality Meter reads. 22 is a pristine site, 17 a city.
    public let skyBrightness: Double
    /// Scatter of the per-star estimates, as a standard error.
    public let uncertainty: Double
    /// Naked-eye limiting magnitude implied by `skyBrightness` (Schaefer's relation).
    public let nakedEyeLimit: Double
    /// 1–9, from `skyBrightness`.
    public let bortle: Int
    /// Faintest point source the stack itself would show at five sigma, in V.
    public let stackLimit: Double
    public let matchedStars: Int
    /// Altitude of the frame centre, degrees: sky brightness depends on it.
    public let altitude: Double
    public let azimuth: Double

    public init(
        skyBrightness: Double, uncertainty: Double, nakedEyeLimit: Double, bortle: Int, stackLimit: Double,
        matchedStars: Int, altitude: Double, azimuth: Double
    ) {
        self.skyBrightness = skyBrightness
        self.uncertainty = uncertainty
        self.nakedEyeLimit = nakedEyeLimit
        self.bortle = bortle
        self.stackLimit = stackLimit
        self.matchedStars = matchedStars
        self.altitude = altitude
        self.azimuth = azimuth
    }
}

/// Measures sky brightness from a stack, using the stars in it as the calibration.
///
/// A phone has no absolute photometric calibration, and does not need one: every frame
/// carries its own. Each identified star of known magnitude is a reference, and comparing
/// it with the sky right around it gives the sky's brightness in magnitudes per square
/// arcsecond directly. Exposure, ISO, vignetting and the lens's throughput all cancel,
/// because star and sky went through the same pixels at the same moment.
///
/// What does not cancel: colour (a phone's luminance is not Johnson V, ±0.2 mag) and
/// extinction, which dims the star but not the sky glow in front of it; the second is
/// corrected with a standard 0.2 mag per airmass.
public struct SkyMeter: Sendable {

    public var extinction = 0.2
    public var aperture = 3
    public var detector = StarDetector(threshold: 5, maxStars: 200)

    public init() {}

    /// `luminance` must be linear light, averaged per pixel (not summed or tone-mapped).
    public func measure(image: LumaImage, pointing: CameraPointing, moment: SkyMoment) -> SkyReading? {
        let width = image.width
        let height = image.height
        let detected = detector.detect(in: image.pixels, width: width, height: height)
        guard let plate = PlateMatch.solve(
            detected: detected, pointing: pointing, moment: moment, width: width, height: height
        ), plate.isTrustworthy else { return nil }

        var brightness: [Double] = []
        var zeroPoints: [Double] = []
        var noises: [Double] = []
        for match in plate.matches {
            guard let photometry = Photometry.measure(
                image, x: match.pixel.x, y: match.pixel.y, radius: aperture
            ), photometry.flux > 0, photometry.background > 0 else { continue }

            let observed = match.star.magnitude + extinction * Self.airmass(altitude: match.horizontal.altitude)
            let predicted = plate.correction.invert((match.pixel.x, match.pixel.y))
            let area = plate.pointing.pixelArea(x: predicted.x, y: predicted.y, width: width, height: height)
                / pow(plate.correction.scale, 2)
            brightness.append(observed - 2.5 * log10(photometry.background / (photometry.flux * area)))
            zeroPoints.append(observed + 2.5 * log10(photometry.flux))
            noises.append(photometry.noise)
        }
        guard brightness.count >= 6 else { return nil }

        let sky = Self.median(brightness)
        let spread = Self.median(brightness.map { abs($0 - sky) }) * 1.4826
        let zeroPoint = Self.median(zeroPoints)
        let apertureArea = Double.pi * Double(aperture * aperture)
        let limitFlux = 5 * Self.median(noises) * apertureArea.squareRoot()
        return SkyReading(
            skyBrightness: sky,
            uncertainty: spread / Double(brightness.count).squareRoot(),
            nakedEyeLimit: Self.nakedEyeLimit(skyBrightness: sky),
            bortle: Self.bortle(skyBrightness: sky),
            stackLimit: zeroPoint - 2.5 * log10(limitFlux),
            matchedStars: brightness.count,
            altitude: plate.pointing.center.altitude,
            azimuth: plate.pointing.center.azimuth
        )
    }

    /// Kasten & Young (1989): good to the horizon, where 1/sin(h) blows up.
    public static func airmass(altitude: Double) -> Double {
        let clamped = max(altitude, 0.5)
        return 1 / (sin(clamped.radians) + 0.50572 * pow(clamped + 6.07995, -1.6364))
    }

    /// Naked-eye limiting magnitude from sky brightness, as Globe at Night and the
    /// Unihedron SQM tables convert it (after Schaefer 1990).
    public static func nakedEyeLimit(skyBrightness: Double) -> Double {
        7.93 - 5 * log10(pow(10, 4.316 - skyBrightness / 5) + 1)
    }

    /// The Bortle class an SQM reading corresponds to, on the usual table.
    public static func bortle(skyBrightness: Double) -> Int {
        let bounds: [(Double, Int)] = [
            (21.99, 1), (21.89, 2), (21.69, 3), (20.49, 4), (19.50, 5), (18.94, 6), (18.38, 7), (17.80, 8),
        ]
        return bounds.first { skyBrightness >= $0.0 }?.1 ?? 9
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return .nan }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

/// Aperture photometry: light inside a circle, sky from the ring around it.
enum Photometry {
    struct Result {
        let flux: Double
        /// Per-pixel sky level around the star.
        let background: Double
        /// Per-pixel noise in that ring.
        let noise: Double
    }

    static func measure(_ image: LumaImage, x: Double, y: Double, radius: Int) -> Result? {
        let width = image.width
        let buffer = image.pixels
        let inner = Double(radius) + 2
        let outer = Double(radius) + 6
        let reach = Int(outer.rounded(.up))
        let cx = Int(x.rounded())
        let cy = Int(y.rounded())
        guard cx - reach >= 0, cy - reach >= 0, cx + reach < width, cy + reach < image.height else { return nil }

        var ring: [Double] = []
        var sum = 0.0
        var count = 0
        for dy in -reach...reach {
            for dx in -reach...reach {
                let distance = hypot(Double(cx + dx) - x, Double(cy + dy) - y)
                let value = Double(buffer[(cy + dy) * width + cx + dx])
                if distance <= Double(radius) {
                    // A clipped pixel has lost light: the star cannot be measured.
                    guard value < 0.95 else { return nil }
                    sum += value
                    count += 1
                } else if distance >= inner, distance <= outer {
                    ring.append(value)
                }
            }
        }
        guard ring.count > 20, count >= 1 else { return nil }
        let background = SkyMeter.median(ring)
        let noise = SkyMeter.median(ring.map { abs($0 - background) }) * 1.4826
        return Result(flux: sum - background * Double(count), background: background, noise: noise)
    }
}
