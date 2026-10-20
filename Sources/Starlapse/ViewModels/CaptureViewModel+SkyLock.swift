import CoreGraphics
import Foundation
import SkyKit
import SkyMeter
import StackKit

/// Locking the overlay to the stars in the live view.
///
/// Split from the main view model to keep it inside the size limit. The math is `SkyLock`
/// and `PlateMatch`; this is only the loop that feeds them.
extension CaptureViewModel {

    struct OverlayPointing {
        let aim: HorizontalCoordinates
        let roll: Double
        let fieldScale: Double
        let isLocked: Bool
    }

    /// What the overlay should draw from: the sensors, corrected by a fresh lock if any.
    var overlayPointing: OverlayPointing {
        guard let lock = skyLock, lock.isFresh(at: Date()) else {
            return OverlayPointing(aim: attitude.aim, roll: attitude.imageRoll, fieldScale: 1, isLocked: false)
        }
        let corrected = lock.apply(aim: attitude.aim, roll: attitude.imageRoll)
        return OverlayPointing(aim: corrected.aim, roll: corrected.roll, fieldScale: lock.fieldScale, isLocked: true)
    }

    /// Solve a framing frame every few seconds while the phone is held still under stars.
    /// Runs for the life of the screen; each pass is cheap to skip and about a second of
    /// utility-priority work when it does run.
    func startSkyLock() {
        skyLocking?.cancel()
        skyLocking = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard let self, !Task.isCancelled else { return }
                await self.solveSkyLock()
            }
        }
    }

    private func solveSkyLock() async {
        guard state == .aiming, !isFocusing, !mode.isDetector, attitude.hasFullFix,
              let location = attitude.location, let stackEngine,
              let frame = await stackEngine.watchedLuminance()
        else { return }

        let before = attitude.aim
        let buffer = CGSize(width: frame.width, height: frame.height)
        let assumed = CameraPointing(
            center: before,
            roll: attitude.imageRoll,
            horizontalFieldOfView: PreviewGeometry.fieldAcrossWidth(
                lensFieldOfView: Double(settings.lens.fieldOfView), buffer: buffer
            )
        )
        let moment = SkyMoment(location: location, date: Date())
        let solved = await Task.detached(priority: .utility) { () -> PlateMatch? in
            let stars = StarDetector(threshold: 5, maxStars: 150)
                .detect(in: frame.pixels, width: frame.width, height: frame.height)
            var options = PlateMatch.Options()
            // Roll comes from gravity and is good to a degree or two; no need to search
            // the whole circle the way an unknown buffer orientation would.
            options.rotations = Array(stride(from: -12.0, through: 12.0, by: 2.0))
            return PlateMatch.solve(
                detected: stars, pointing: assumed, moment: moment,
                width: frame.width, height: frame.height, options: options
            )
        }.value

        // A frame taken while the phone moved belongs to neither reading of the sensors.
        guard attitude.aim.separation(from: before) < 0.3,
              let solved, SkyLock.accepts(solved, assumed: assumed)
        else { return }
        skyLock = SkyLock(assumed: assumed, solved: solved.pointing, matchedStars: solved.matches.count, at: Date())
    }
}
