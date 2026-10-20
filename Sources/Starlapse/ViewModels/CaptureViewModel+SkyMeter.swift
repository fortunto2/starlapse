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
    /// The first saved shot waits here, as a JPEG, while the dataset question is open.
    var pendingContribution: (SkyDataset.Contribution, Data?)?
    var asksConsent = false
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

    // MARK: - The dataset

    private var camera: SkyDataset.Camera {
        SkyDataset.Camera(
            lens: settings.lens.displayName, iso: Double(settings.iso), shutter: settings.frameExposure,
            frames: progress.framesStacked, fieldOfView: Double(settings.lens.fieldOfView),
            device: SkyDataset.deviceModel
        )
    }

    /// After a still is saved: send it, or ask the first time.
    func contribute(_ rendered: RenderedImage) async {
        guard SkyDataset.choice != false, let start = sky.start else { return }
        // A save in the second after review opens can beat the measurement; it is worth
        // waiting a few seconds for, the reading is the point of the contribution.
        for _ in 0..<20 where sky.isMeasuring { try? await Task.sleep(for: .milliseconds(250)) }
        let photo = await Task.detached(priority: .utility) { SkyDataset.jpeg(from: rendered) }.value
        let contribution = SkyDataset.contribution(kind: "stack", start: start, sky: sky.reading, camera: camera)
        if SkyDataset.choice == nil {
            sky.pendingContribution = (contribution, photo)
            sky.asksConsent = true
        } else {
            await SkyDataset.enqueue(contribution, photo: photo)
        }
    }

    /// The answer to the one-time question.
    func answerConsent(_ contribute: Bool) {
        SkyDataset.choice = contribute
        sky.asksConsent = false
        guard contribute, let pending = sky.pendingContribution else {
            sky.pendingContribution = nil
            return
        }
        sky.pendingContribution = nil
        Task { await SkyDataset.enqueue(pending.0, photo: pending.1) }
    }

    /// A finished watch: the meteors placed on the sky go in as data, without the clips.
    func contributeMeteors() {
        let meteors = events.compactMap(\.meteor)
        guard SkyDataset.isEnabled, !meteors.isEmpty, let start = sky.start else { return }
        let contribution = SkyDataset.contribution(
            kind: "meteors", start: start, sky: nil, camera: camera, meteors: meteors
        )
        Task { await SkyDataset.enqueue(contribution, photo: nil) }
    }
}
