import StackKit

/// How the phone is being held, from the last second of gyroscope readings.
enum HoldState: Sendable, Equatable {
    /// No readings yet, or no gyroscope (the Simulator).
    case unknown
    /// Set down: a tripod, a wall, the roof of a car.
    case steady
    /// Braced but not still: frames will be dropped now and then.
    case braced
    /// In a hand: most one-second frames will be dropped.
    case handheld

    init(rate: Double?) {
        guard let rate else {
            self = .unknown
            return
        }
        if rate < Steadiness.steadyRate {
            self = .steady
        } else if rate < Steadiness.handheldRate {
            self = .braced
        } else {
            self = .handheld
        }
    }
}
