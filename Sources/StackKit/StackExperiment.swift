import Foundation

/// One way of turning camera frames into a stack — the knobs worth comparing.
public struct StackPipeline: Sendable, Hashable {
    public var name: String
    /// What the camera quantises to before we see it.
    public var bitDepth: Int
    /// Undo the camera's transfer curve before adding frames.
    public var linearize: Bool
    public var mode: CombineMode
    /// Dark frames averaged into a master and subtracted. 0 means none.
    public var darkFrames: Int
    /// Subtract only the hot pixels the master dark finds, not the whole frame.
    public var hotPixelsOnly: Bool
    /// Per-frame isolated-spike removal: hot pixels without dark frames.
    public var cosmetic = false
    /// Divide each pixel by the frames that actually covered it, rather than by all of them.
    public var perPixelCoverage: Bool

    public init(
        name: String, bitDepth: Int, linearize: Bool, mode: CombineMode,
        darkFrames: Int = 0, hotPixelsOnly: Bool = false, perPixelCoverage: Bool = true
    ) {
        self.hotPixelsOnly = hotPixelsOnly
        self.name = name
        self.bitDepth = bitDepth
        self.linearize = linearize
        self.mode = mode
        self.darkFrames = darkFrames
        self.perPixelCoverage = perPixelCoverage
    }

    /// What 1.0.x ships: 8-bit BGRA stacked as if it were light, divided by the frame count.
    public static let shipped = StackPipeline(
        name: "shipped", bitDepth: 8, linearize: false, mode: .mean, perPixelCoverage: false
    )

    /// What the app stacks with, chosen by `starlapse-stack compare`: light added as
    /// light, each pixel divided by its own coverage, one-frame outliers rejected at 4σ,
    /// and lone hot pixels replaced per frame. 8-bit, because 10 measured under 2% better
    /// at phone noise levels. A dark-frame hot-pixel map measured better still on hot
    /// pixels, but needs a lens-covered capture step the app does not have yet.
    public static let chosen: StackPipeline = {
        var pipeline = StackPipeline(
            name: "8-bit + sigma4 + cosmetic", bitDepth: 8, linearize: true,
            mode: .sigmaClip(kappa: 4, warmup: 8)
        )
        pipeline.cosmetic = true
        return pipeline
    }()

    /// The candidates, in the order they build on each other.
    public static let candidates: [StackPipeline] = [
        .shipped,
        StackPipeline(name: "linear 8-bit", bitDepth: 8, linearize: true, mode: .mean),
        StackPipeline(name: "linear 10-bit", bitDepth: 10, linearize: true, mode: .mean),
        StackPipeline(
            name: "10-bit + sigma", bitDepth: 10, linearize: true,
            mode: .sigmaClip(kappa: 3, warmup: 5)
        ),
        StackPipeline(
            name: "10-bit + sigma4", bitDepth: 10, linearize: true,
            mode: .sigmaClip(kappa: 4, warmup: 8)
        ),
        StackPipeline(
            name: "10-bit + sigma + dark", bitDepth: 10, linearize: true,
            mode: .sigmaClip(kappa: 3, warmup: 5), darkFrames: 16
        ),
        StackPipeline(
            name: "10-bit + sigma4 + hotmap", bitDepth: 10, linearize: true,
            mode: .sigmaClip(kappa: 4, warmup: 8), darkFrames: 16, hotPixelsOnly: true
        ),
        StackPipeline(
            name: "8-bit + sigma4 + hotmap", bitDepth: 8, linearize: true,
            mode: .sigmaClip(kappa: 4, warmup: 8), darkFrames: 16, hotPixelsOnly: true
        ),
        .chosen,
    ]
}

/// A night out, emulated: how many frames, what crosses the sky, how far the field drifts.
public struct StackExperiment: Sendable {
    public var scene: SkyScene
    public var camera: CameraModel
    public var frames: Int
    /// Which frame a satellite crosses, and where. `nil` for a clean night.
    public var satellite: (frame: Int, row: Int)?
    /// Columns of coverage lost per frame as the field rotates out of the sensor.
    public var driftPerFrame: Double

    public init(
        scene: SkyScene = .field(), camera: CameraModel = CameraModel(), frames: Int = 40,
        satellite: (frame: Int, row: Int)? = (frame: 17, row: 30), driftPerFrame: Double = 0.5
    ) {
        self.scene = scene
        self.camera = camera
        self.frames = frames
        self.satellite = satellite
        self.driftPerFrame = driftPerFrame
    }

    /// Columns that some, but not all, frames covered.
    public var edgeColumns: Int { Int((Double(frames - 1) * driftPerFrame).rounded(.up)) }

    public func run(_ pipeline: StackPipeline) -> StackQuality {
        var lens = camera
        lens.bitDepth = pipeline.bitDepth
        // Same seed for every pipeline: they all see the same photons.
        var simulator = SkySimulator(scene: scene, camera: lens)

        var dark = pipeline.darkFrames > 0
            ? MasterDark.average((0..<pipeline.darkFrames).map { _ in simulator.darkFrame(linearize: pipeline.linearize) })
            : nil
        if pipeline.hotPixelsOnly, let master = dark { dark = MasterDark.hotPixelMap(master) }

        var combiner = StackCombiner(width: scene.width, height: scene.height, mode: pipeline.mode)
        for index in 0..<frames {
            var frame = simulator.lightFrame(
                coveredFrom: Int(Double(index) * driftPerFrame),
                satelliteRow: satellite?.frame == index ? satellite?.row : nil,
                linearize: pipeline.linearize
            )
            if let dark { frame = MasterDark.subtract(dark, from: frame) }
            if pipeline.cosmetic {
                frame = CosmeticCorrection.apply(frame, width: scene.width, height: scene.height)
            }
            if !pipeline.perPixelCoverage {
                // The shipped resolve divides by the session's frame count, so a pixel a
                // frame never reached counted as a black sample.
                frame = frame.map { $0.isNaN ? 0 : $0 }
            }
            combiner.add(frame)
        }

        var result = combiner.result()
        if !pipeline.linearize {
            // Score it in light, the most charitable reading of an encoded stack.
            result = result.map { $0.isNaN ? .nan : camera.transfer.decode($0) }
        }
        return StackQuality.score(
            result, scene: scene, satelliteRow: satellite?.row, edgeColumns: edgeColumns
        )
    }
}
