import Foundation

extension Double {
    public var radians: Double { self * .pi / 180.0 }
    public var degrees: Double { self * 180.0 / .pi }

    /// Wrap into `[0, 360)`.
    public var normalizedDegrees: Double {
        let value = truncatingRemainder(dividingBy: 360.0)
        return value < 0 ? value + 360.0 : value
    }

    /// Wrap into `[-180, 180)` — "how far do I turn, and which way".
    public var signedDegrees: Double {
        let value = normalizedDegrees
        return value >= 180 ? value - 360 : value
    }

    public func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

/// Right ascension expressed the way catalogues print it.
public func hoursToDegrees(_ hours: Double, _ minutes: Double = 0, _ seconds: Double = 0) -> Double {
    (hours + minutes / 60.0 + seconds / 3600.0) * 15.0
}

/// The eight-point compass name for an azimuth, for spoken-word guidance
/// ("look north-east, two thirds of the way up").
public func compassPoint(forAzimuth azimuth: Double) -> String {
    let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    let index = Int((azimuth.normalizedDegrees / 45.0).rounded()) % 8
    return names[index]
}
