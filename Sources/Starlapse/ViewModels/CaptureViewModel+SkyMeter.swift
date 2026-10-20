import Foundation
import SkyKit
import SkyMeter

/// Where the phone pointed when a stack began, and what the finished stack says about the
/// sky. Split from the main view model to keep it inside the size limit.
struct SkyMeasurement {
    struct Start {
        let aim: HorizontalCoordinates
        let location: GeographicCoordinates
        let date: Date
        let fieldOfView: Double
    }

    var start: Start?
    var reading: SkyReading?
    var isMeasuring = false
}

extension CaptureViewModel {

    /// Called as a still stack begins. Without a location there is no sky to compare with.
    func beginSkyMeasurement() {
        sky = SkyMeasurement()
        guard case .still = mode, let location = attitude.location else { return }
        sky.start = SkyMeasurement.Start(
            aim: attitude.aim, location: location, date: Date(),
            fieldOfView: Double(settings.lens.fieldOfView)
        )
    }

    /// Called in review. The stack is read once, then measured off the main actor: the
    /// catalogue match walks nine thousand stars a few times, about a second on a phone.
    func measureSky() {
        guard let start = sky.start, let stackEngine else { return }
        sky.isMeasuring = true
        let middle = start.date.addingTimeInterval(Date().timeIntervalSince(start.date) / 2)
        Task {
            guard let stack = await stackEngine.skyLuminance() else {
                sky.isMeasuring = false
                return
            }
            let pointing = CameraPointing(center: start.aim, roll: 0, horizontalFieldOfView: start.fieldOfView)
            let reading = await Task.detached(priority: .userInitiated) {
                SkyMeter().measure(
                    image: stack, pointing: pointing, moment: SkyMoment(location: start.location, date: middle)
                )
            }.value
            guard sky.start?.date == start.date else { return }
            sky.reading = reading
            sky.isMeasuring = false
        }
    }
}
