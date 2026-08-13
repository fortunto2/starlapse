import Foundation
import StackKit

/// Focusing on starlight.
///
/// The problem this solves: autofocus is useless against a night sky — there is nothing for
/// it to hunt on — and "just set infinity" is not quite right either. `lensPosition = 1.0`
/// is the mechanical end stop, and the sharpest point sits slightly inside it, at a place
/// that differs between individual lenses and moves overnight as the phone cools.
///
/// So it focuses the way observatories do: step the lens, measure how big the stars come
/// out, keep the position where they are smallest.
extension CaptureViewModel {

    /// Run a focus sweep. Only meaningful while framing, under a sky with visible stars.
    func autofocus() async {
        guard let captureEngine, let stackEngine, state == .aiming, !isFocusing else { return }

        isFocusing = true
        focusProgress = 0
        defer { isFocusing = false }

        let sweep = FocusSweep()
        let startedAt = settings.focusPosition
        var samples: [FocusSweep.Sample] = []

        let coarse = sweep.coarsePositions()
        for (index, position) in coarse.enumerated() {
            guard isFocusing else { break }   // cancelled
            samples.append(await measure(position, engine: captureEngine, stack: stackEngine))
            focusProgress = Double(index + 1) / Double(coarse.count) * 0.6
        }

        guard let rough = sweep.bestPosition(from: samples) else {
            // Nothing measurable: cloud, a lens cap, or pointed at the ground. Leave the
            // lens exactly where the user had it rather than guessing.
            settings.focusPosition = startedAt
            try? await captureEngine.apply(activeSettings)
            focusResult = .noStars
            return
        }

        let fine = sweep.finePositions(around: rough)
        for (index, position) in fine.enumerated() {
            guard isFocusing else { break }
            samples.append(await measure(position, engine: captureEngine, stack: stackEngine))
            focusProgress = 0.6 + Double(index + 1) / Double(fine.count) * 0.4
        }

        guard let best = sweep.bestPosition(from: samples) else {
            settings.focusPosition = startedAt
            try? await captureEngine.apply(activeSettings)
            focusResult = .noStars
            return
        }

        settings.focusPosition = best
        try? await captureEngine.apply(activeSettings)

        let sharpness = samples
            .filter(\.metric.isUsable)
            .min { $0.metric.sharper(than: $1.metric) }?
            .metric.halfFluxDiameter

        focusResult = .found(position: best, starSize: sharpness ?? 0)
        logger.info("Autofocus settled at \(best, format: .fixed(precision: 3))")
    }

    func cancelAutofocus() {
        isFocusing = false
    }

    /// Set a lens position and read back how sharp the stars are at it.
    private func measure(
        _ position: Float,
        engine: CaptureEngine,
        stack: StackEngine
    ) async -> FocusSweep.Sample {
        var probing = activeSettings
        probing.focusPosition = position
        try? await engine.apply(probing)

        // Discard one frame: the sensor may already have been mid-exposure when the lens
        // moved, and a frame straddling the move measures neither position.
        _ = await stack.measureFocus()
        let metric = await stack.measureFocus()

        return FocusSweep.Sample(position: position, metric: metric)
    }

    enum FocusResult: Equatable, Sendable {
        case found(position: Float, starSize: Double)
        case noStars

        var message: String {
            switch self {
            case .found(let position, let size):
                String(format: "Focused at %.3f — stars %.1f px", position, size)
            case .noStars:
                "No stars to focus on. Point at open sky, or wait for cloud to pass."
            }
        }
    }
}
