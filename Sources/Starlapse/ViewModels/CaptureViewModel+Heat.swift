import Foundation

/// A hot phone, read on the sky timer every ten seconds.
///
/// Nothing in the app asked before 1.2.4. A night time-lapse runs the sensor, the GPU and the
/// screen for hours; on a warm night iOS throttles and then ends the process, and with it the
/// night. Serious: redraw the screen a quarter as often. Critical: stop and keep what was shot,
/// because a stop the app chose ends in review and a kill ends in nothing.
extension CaptureViewModel {

    func checkHeat() {
        let heat = ProcessInfo.processInfo.thermalState
        let hot = heat == .serious || heat == .critical
        if hot != isHot {
            isHot = hot
            stackEngine?.setHot(hot)
        }
        guard state == .capturing else { return }
        if heat.rawValue > sessionHeat.rawValue { sessionHeat = heat }
        if heat == .critical, !stoppedForHeat {
            stoppedForHeat = true
            Task { await cancel() }
        }
    }

    /// For `capture_finished`: the hottest the phone got during the session.
    var sessionHeatName: String {
        switch sessionHeat {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}
