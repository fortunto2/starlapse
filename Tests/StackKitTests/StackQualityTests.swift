import Testing
@testable import StackKit

/// The emulated night is what every stacking decision is now argued from, so its parts
/// are pinned to known answers, and the decisions are pinned to what it measured.
@Suite("Stack quality on an emulated sky")
struct StackQualityTests {

    // MARK: - Colour decode

    @Test("Each transfer curve round-trips through its inverse")
    func transferRoundTrips() {
        for curve in TransferFunction.allCases {
            for value: Float in [0, 0.001, 0.01, 0.018, 0.1, 0.5, 1] {
                #expect(abs(curve.decode(curve.encode(value)) - value) < 1e-4)
            }
        }
    }

    @Test("Video-range codes map black to 0 and white to 1, at 8 and 10 bits")
    func videoRangeEndpoints() {
        for bits in [8, 10] {
            let decoder = YCbCrDecoder(bitDepth: bits, fullRange: false)
            let scale = 1 << (bits - 8)
            let black = decoder.rgb(y: 16 * scale, cb: 128 * scale, cr: 128 * scale)
            let white = decoder.rgb(y: 235 * scale, cb: 128 * scale, cr: 128 * scale)
            #expect(black.r == 0 && black.g == 0 && black.b == 0)
            #expect(abs(white.r - 1) < 1e-5 && abs(white.g - 1) < 1e-5 && abs(white.b - 1) < 1e-5)
        }
    }

    @Test("Pure BT.709 red decodes to red")
    func bt709Red() {
        // Y = 0.2126, Cb = -0.1146, Cr = 0.5 for (1, 0, 0), full range 8-bit.
        let decoder = YCbCrDecoder(bitDepth: 8, fullRange: true)
        let rgb = decoder.rgb(y: 54, cb: 98, cr: 255)
        #expect(rgb.r > 0.97 && rgb.g < 0.03 && rgb.b < 0.03)
    }

    // MARK: - Combiner

    @Test("Sigma clipping keeps the sky and drops the one frame a satellite crossed")
    func sigmaDropsOneFrameOutlier() {
        var combiner = StackCombiner(width: 1, height: 1, mode: .sigmaClip(kappa: 4, warmup: 8))
        var random = SeededRandom(seed: 3)
        for index in 0..<40 {
            let sky = 0.02 + 0.001 * random.gaussian()
            combiner.add([index == 20 ? sky + 0.3 : sky])
        }
        #expect(combiner.rejected == 1)
        #expect(abs(combiner.result()[0] - 0.02) < 0.001)
    }

    @Test("A pixel divides by the frames that reached it, not by all of them")
    func coverageIsPerPixel() {
        var combiner = StackCombiner(width: 2, height: 1, mode: .mean)
        combiner.add([0.5, 0.5])
        combiner.add([.nan, 0.5])
        #expect(combiner.result() == [0.5, 0.5])
    }

    @Test("Comet mode lets old light fade")
    func cometFades() {
        var combiner = StackCombiner(width: 1, height: 1, mode: .comet(decay: 0.5))
        combiner.add([1])
        combiner.add([0])
        combiner.add([0])
        #expect(combiner.result() == [0.25])
    }

    @Test("Cosmetic correction removes a lone spike and leaves a star alone")
    func cosmeticSparesStars() {
        let scene = SkyScene(
            width: 32, height: 32, background: 0.02,
            stars: [SkyScene.Star(x: 20, y: 20, peak: 0.05)],
            hotPixels: [], hotPixelLevel: 0, psfSigma: 1.4
        )
        var frame = scene.truth()
        frame[8 * 32 + 8] += 0.25
        let fixed = CosmeticCorrection.apply(frame, width: 32, height: 32)

        #expect(abs(fixed[8 * 32 + 8] - 0.02) < 0.001)
        #expect(fixed[20 * 32 + 20] == frame[20 * 32 + 20])
    }

    @Test("The hot-pixel map keeps hot pixels and zeroes the rest")
    func hotPixelMap() {
        var random = SeededRandom(seed: 5)
        var dark = (0..<400).map { _ in 0.003 + 0.001 * random.gaussian() }
        dark[17] = 0.3
        let map = MasterDark.hotPixelMap(dark)
        #expect(map[17] > 0.29)
        #expect(map.enumerated().filter { $0.offset != 17 }.allSatisfy { $0.element == 0 })
    }

    // MARK: - The decisions, as measured

    @Test("The shipped pipeline darkens the edge of a drifting field by half")
    func shippedDarkensTheEdge() {
        let quality = StackExperiment().run(.shipped)
        #expect(quality.edgeRatio < 0.6)
    }

    @Test("The chosen pipeline: no dark edge, no satellite, no hot pixels, no lost stars")
    func chosenPipelineWins() {
        let experiment = StackExperiment()
        let linear = experiment.run(StackPipeline(name: "linear", bitDepth: 8, linearize: true, mode: .mean))
        let chosen = experiment.run(.chosen)

        #expect(abs(chosen.edgeRatio - 1) < 0.05)
        #expect(abs(chosen.satelliteResidual) < 1)
        #expect(chosen.hotPixelResidual < linear.hotPixelResidual * 0.1)
        #expect(chosen.faintStarSNR >= linear.faintStarSNR * 0.97)
        #expect(abs(chosen.bias) < 0.0002)
    }

    @Test("Ten bits buy less than 2% at phone noise levels — not worth a riskier format")
    func tenBitsBarelyMatter() {
        let experiment = StackExperiment()
        let eight = experiment.run(StackPipeline(name: "8", bitDepth: 8, linearize: true, mode: .mean))
        let ten = experiment.run(StackPipeline(name: "10", bitDepth: 10, linearize: true, mode: .mean))
        #expect(abs(ten.faintStarSNR - eight.faintStarSNR) / eight.faintStarSNR < 0.02)
    }
}
