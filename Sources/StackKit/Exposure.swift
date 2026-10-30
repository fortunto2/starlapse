import Foundation

/// Shutter and gain, the two numbers the meter moves.
public struct Exposure: Sendable, Equatable {
    public var shutter: Double
    public var iso: Float
    public init(shutter: Double, iso: Float) {
        self.shutter = shutter
        self.iso = iso
    }
    /// Light gathered, in shutter-seconds × ISO: what a meter changes.
    public var light: Double { shutter * Double(iso) }
}

/// What a frame says about its exposure: one level (the Moon's peak, a scene's median) and
/// the share of pixels at the clip, whose real brightness is unknown.
public struct LightReading: Sendable, Equatable {
    public let level: Double
    public let clippedFraction: Double
    public init(level: Double, clippedFraction: Double) {
        self.level = level
        self.clippedFraction = clippedFraction
    }
}

/// Moves shutter and ISO so a reading lands on a target, preferring base ISO and only raising
/// gain once the shutter reaches its limit.
///
/// Used twice: the Moon meters its disc's peak to 0.7 (its brightness spans six stops
/// between a crescent and full, and an average over a black sky blows it out), and framing
/// meters the scene's median to 0.18 so daylight is not a white screen.
public enum ExposureMeter {

    public struct Limits: Sendable, Equatable {
        public var shutter: ClosedRange<Double>
        public var iso: ClosedRange<Float>
        public init(shutter: ClosedRange<Double>, iso: ClosedRange<Float>) {
            self.shutter = shutter
            self.iso = iso
        }
    }

    /// Linear peak for the Moon's disc. Highlands sit near it; the maria well below.
    public static let moonTarget = 0.7
    /// Linear median for a scene: photographic mid-grey.
    public static let sceneTarget = 0.18
    /// Closer than this (in stops) and nothing changes: no hunting between two frames.
    static let deadband = 0.15
    static let clipLevel = 0.98

    public static func next(_ current: Exposure, reading: LightReading, target: Double, limits: Limits) -> Exposure {
        let factor: Double
        if reading.clippedFraction > 0.5 {
            // Mostly white: night framing in daylight is twelve stops over or more. Big steps
            // down, eight stops when nearly everything is clipped: overshooting into a dark
            // frame costs nothing, because a dark frame can be read and the next step is exact.
            factor = reading.clippedFraction > 0.9 ? 1.0 / 256 : 1.0 / 32
        } else if reading.clippedFraction > 0.02 || reading.level >= clipLevel {
            // Clipped, so the real brightness is unknown: step down by a fixed three stops.
            factor = 1.0 / 8
        } else {
            guard reading.level > 0 else { return current }
            let wanted = target / reading.level
            guard abs(log2(wanted)) > deadband else { return current }
            factor = min(64, max(1.0 / 64, wanted))
        }

        let light = current.light * factor
        let shutter = (light / Double(limits.iso.lowerBound)).clamped(to: limits.shutter)
        let iso = Float(light / shutter).clamped(to: limits.iso)
        return Exposure(shutter: shutter, iso: iso)
    }
}

/// A whole frame's level: its median and how much of it is clipped. Sub-sampled, because it
/// runs several times a second while framing and a median does not need every pixel.
public enum SceneLevel {
    public static func measure(_ buffer: [Float]) -> LightReading {
        guard !buffer.isEmpty else { return LightReading(level: 0, clippedFraction: 0) }
        let stride = max(1, buffer.count / 20_000)
        var samples: [Float] = []
        samples.reserveCapacity(buffer.count / stride + 1)
        for index in Swift.stride(from: 0, to: buffer.count, by: stride) {
            samples.append(buffer[index])
        }
        samples.sort()
        let clipped = samples.count - (samples.firstIndex { Double($0) >= ExposureMeter.clipLevel } ?? samples.count)
        return LightReading(
            level: Double(samples[samples.count / 2]),
            clippedFraction: Double(clipped) / Double(samples.count)
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
