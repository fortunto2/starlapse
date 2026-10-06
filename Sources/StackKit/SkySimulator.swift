import Foundation

/// A night sky with known answers, and a camera that ruins it in known ways.
///
/// Every claim about stacking quality in this project used to be reasoning. This makes
/// it a measurement: render the sky linearly, add the noise a phone sensor adds, push it
/// through the same transfer curve and quantisation the camera applies, and hand the
/// result to a pipeline. The truth is kept, so whatever comes out can be scored.
public struct SkyScene: Sendable {
    public struct Star: Sendable, Hashable {
        public let x: Double
        public let y: Double
        /// Peak brightness above the sky, linear.
        public let peak: Float
    }

    public let width: Int
    public let height: Int
    public let background: Float
    public let stars: [Star]
    public let hotPixels: [Int]
    public let hotPixelLevel: Float
    public let psfSigma: Double

    /// A repeatable field: many faint stars, a few bright ones, the way the sky really is.
    public static func field(
        width: Int = 192, height: Int = 128, stars: Int = 60, background: Float = 0.02,
        hotPixels: Int = 25, seed: UInt64 = 7
    ) -> SkyScene {
        var random = SeededRandom(seed: seed)
        let margin = 6.0
        let field = (0..<stars).map { _ in
            Star(
                x: margin + random.unit() * (Double(width) - 2 * margin),
                y: margin + random.unit() * (Double(height) - 2 * margin),
                // Power law: most stars are barely there.
                peak: Float(0.004 + 0.4 * pow(random.unit(), 4))
            )
        }
        let hot = (0..<hotPixels).map { _ in Int(random.unit() * Double(width * height - 1)) }
        return SkyScene(
            width: width, height: height, background: background, stars: field,
            hotPixels: hot, hotPixelLevel: 0.25, psfSigma: 1.4
        )
    }

    /// The sky with nothing wrong with it.
    public func truth() -> [Float] {
        var buffer = [Float](repeating: background, count: width * height)
        let radius = Int((psfSigma * 3).rounded(.up))
        for star in stars {
            let cx = Int(star.x.rounded())
            let cy = Int(star.y.rounded())
            for dy in -radius...radius {
                for dx in -radius...radius {
                    let x = cx + dx
                    let y = cy + dy
                    guard x >= 0, x < width, y >= 0, y < height else { continue }
                    let ddx = Double(x) - star.x
                    let ddy = Double(y) - star.y
                    let weight = exp(-(ddx * ddx + ddy * ddy) / (2 * psfSigma * psfSigma))
                    buffer[y * width + x] += star.peak * Float(weight)
                }
            }
        }
        return buffer
    }

    /// Pixels a satellite crossing at `row` would light: a two-pixel-wide diagonal.
    public func satellitePath(row: Int) -> [Int] {
        (0..<width).flatMap { x -> [Int] in
            let y = row + x / 4
            return [y, y + 1].filter { $0 >= 0 && $0 < height }.map { $0 * width + x }
        }
    }
}

/// What the phone does between photons and our code.
public struct CameraModel: Sendable, Hashable {
    /// Electrons that fill the sensor at this ISO. Lower means more shot noise.
    public var electronsAtFullScale: Float = 800
    /// Read noise, linear units.
    public var readNoise: Float = 0.003
    public var transfer: TransferFunction = .bt709
    public var bitDepth: Int = 8
    public var fullRange = false

    public init() {}

    /// Linear signal → code the camera writes → value our pipeline sees.
    ///
    /// `linearize` false is the shipped pipeline: it stacked the encoded value as if it
    /// were light.
    public func capture(_ linear: Float, linearize: Bool) -> Float {
        let decoder = YCbCrDecoder(bitDepth: bitDepth, fullRange: fullRange)
        let code = decoder.lumaCode(transfer.encode(linear))
        let encoded = decoder.rgb(y: code, cb: decoder.neutralChroma, cr: decoder.neutralChroma).green
        return linearize ? transfer.decode(encoded) : encoded
    }
}

/// Renders noisy frames of a scene through a camera.
public struct SkySimulator: Sendable {
    public let scene: SkyScene
    public let camera: CameraModel
    private let clean: [Float]
    private var random: SeededRandom

    public init(scene: SkyScene, camera: CameraModel, seed: UInt64 = 99) {
        self.scene = scene
        self.camera = camera
        self.clean = scene.truth()
        self.random = SeededRandom(seed: seed)
    }

    /// One light frame, already aligned to the reference.
    ///
    /// - Parameters:
    ///   - coveredFrom: columns left of this were outside the frame — the field rotated
    ///     away. They come out `nan`.
    ///   - satelliteRow: a satellite crosses this frame, starting at this row.
    public mutating func lightFrame(
        coveredFrom: Int = 0, satelliteRow: Int? = nil, linearize: Bool
    ) -> [Float] {
        var signal = clean
        for index in scene.hotPixels { signal[index] += scene.hotPixelLevel }
        if let satelliteRow {
            for index in scene.satellitePath(row: satelliteRow) { signal[index] += 0.3 }
        }
        return expose(signal, coveredFrom: coveredFrom, linearize: linearize)
    }

    /// Lens covered: hot pixels and noise, no sky.
    public mutating func darkFrame(linearize: Bool) -> [Float] {
        var signal = [Float](repeating: 0, count: clean.count)
        for index in scene.hotPixels { signal[index] += scene.hotPixelLevel }
        return expose(signal, coveredFrom: 0, linearize: linearize)
    }

    private mutating func expose(_ signal: [Float], coveredFrom: Int, linearize: Bool) -> [Float] {
        let scale = camera.electronsAtFullScale
        var frame = [Float](repeating: .nan, count: signal.count)
        for index in signal.indices where index % scene.width >= coveredFrom {
            let shot = (max(signal[index], 0) * scale).squareRoot() / scale
            let noisy = signal[index] + shot * random.gaussian() + camera.readNoise * random.gaussian()
            frame[index] = camera.capture(noisy, linearize: linearize)
        }
        return frame
    }
}

/// xorshift64* with Box–Muller. Deterministic, so a comparison is the same every run.
public struct SeededRandom: Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }

    public mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545_F491_4F6C_DD1D
    }

    /// Uniform in [0, 1).
    public mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

    public mutating func gaussian() -> Float {
        let u1 = max(unit(), 1e-12)
        let u2 = unit()
        return Float((-2 * log(u1)).squareRoot() * cos(2 * .pi * u2))
    }
}
