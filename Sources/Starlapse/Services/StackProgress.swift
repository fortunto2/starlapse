import Foundation

/// Progress of a running capture, published to the UI.
struct StackProgress: Sendable, Equatable {
    var framesStacked: Int = 0
    var framesRequested: Int = 0
    var framesRejected: Int = 0
    /// Of those, dropped because the phone turned during the exposure.
    var framesMoved: Int = 0
    var starsTracked: Int = 0
    var alignmentResidual: Double = 0
    /// Output frames written, in time-lapse mode.
    var segmentsCompleted: Int = 0
    var segmentsRequested: Int = 0
    /// Detector mode: transients seen, and clips actually written.
    var eventsDetected: Int = 0
    var eventsRecorded: Int = 0

    var fraction: Double {
        guard framesRequested > 0 else { return 0 }
        return min(1, Double(framesStacked) / Double(framesRequested))
    }

    /// Noise improvement so far, in stops — the number that makes stacking feel worth it.
    var noiseReductionStops: Double {
        guard framesStacked > 1 else { return 0 }
        return log2(Double(framesStacked).squareRoot())
    }

    var isTracking: Bool { starsTracked >= 6 }
}
