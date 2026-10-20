import Foundation
import SkyKit
import SkyMeter
import StackKit

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
    /// The detector's camera, solved from a watched frame's stars. Until it is, meteors are
    /// kept as clips but not placed on the sky: a compass bearing is not a measurement.
    var detectorPointing: CameraPointing?
}

extension CaptureViewModel {

    /// Called as a still stack begins. Without a location there is no sky to compare with.
    func beginSkyMeasurement() {
        sky = SkyMeasurement()
        let measurable = if case .still = mode { true } else { mode.isDetector }
        guard measurable, let location = attitude.location else { return }
        sky.start = SkyMeasurement.Start(
            aim: attitude.aim, location: location, date: Date(),
            fieldOfView: Double(settings.lens.fieldOfView)
        )
    }

    /// Called in review. The stack is read once, then measured off the main actor: the
    /// catalogue match walks nine thousand stars a few times, about a second on a phone.
    func measureSky() {
        guard case .still = mode, let start = sky.start, let stackEngine else { return }
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

    // MARK: - Meteors

    func recordEvent(url: URL, event: Transient, frame: LumaImage.Size) {
        let meteor: MeteorObservation? = sky.detectorPointing.flatMap { pointing in
            sky.start.map { start in
                MeteorAstrometry.observe(
                    event, frame: frame, pointing: pointing, moment: SkyMoment(location: start.location, date: Date())
                )
            }
        }
        events.insert(
            RecordedEvent(url: url, date: Date(), isStreak: event.isStreak, angle: event.angle, meteor: meteor),
            at: 0
        )
    }

    /// Orient the detector from its own frames: five seconds in, then once a minute until
    /// a frame shows enough stars (a cloud bank clears, the twilight ends).
    func solveDetectorPointing() {
        guard mode.isDetector, let start = sky.start, let stackEngine else { return }
        Task {
            try? await Task.sleep(for: .seconds(5))
            while state.isCapturing, mode.isDetector, sky.detectorPointing == nil {
                if let frame = await stackEngine.watchedLuminance() {
                    let guess = CameraPointing(
                        center: attitude.aim, roll: 0, horizontalFieldOfView: start.fieldOfView
                    )
                    let moment = SkyMoment(location: start.location, date: Date())
                    let solved = await Task.detached(priority: .utility) {
                        let stars = StarDetector(threshold: 5, maxStars: 150)
                            .detect(in: frame.pixels, width: frame.width, height: frame.height)
                        return PlateMatch.solve(
                            detected: stars, pointing: guess, moment: moment, width: frame.width, height: frame.height
                        )
                    }.value
                    if let solved, solved.isTrustworthy { sky.detectorPointing = solved.pointing }
                }
                if sky.detectorPointing == nil { try? await Task.sleep(for: .seconds(60)) }
            }
        }
    }
}
