import Foundation

/// How good a stacked frame is, scored against the sky it was made from.
///
/// Five numbers, each in units a photographer cares about. Noise and bias are in linear
/// sky units; the residuals are in multiples of the remaining noise, so "3" means "you
/// would see it".
public struct StackQuality: Sendable, Hashable {
    /// Standard deviation of what is left after subtracting the truth, on empty sky.
    public let noise: Float
    /// Mean of the same: a pipeline that brightens or darkens the sky has a bias.
    public let bias: Float
    /// Faint stars: peak above the sky, over the noise. Higher means more stars visible.
    public let faintStarSNR: Float
    /// Hot pixels still standing, in noise units.
    public let hotPixelResidual: Float
    /// The satellite still standing, in noise units.
    public let satelliteResidual: Float
    /// Sky brightness at the partly covered edge over the centre. 1 is right.
    public let edgeRatio: Float

    public static func score(
        _ result: [Float], scene: SkyScene, satelliteRow: Int?, edgeColumns: Int
    ) -> StackQuality {
        let truth = scene.truth()
        let width = scene.width
        let satellite = Set(satelliteRow.map { scene.satellitePath(row: $0) } ?? [])
        let hot = Set(scene.hotPixels)
        let nearStar = starMask(scene)

        var sky: [Float] = []
        var edge: [Float] = []
        var centre: [Float] = []
        for index in result.indices {
            let value = result[index]
            guard !value.isNaN, !nearStar.contains(index), !hot.contains(index),
                  !satellite.contains(index) else { continue }
            let x = index % width
            // Noise and bias are measured where every frame landed; the edge has its own number.
            if x >= edgeColumns { sky.append(value - truth[index]) }
            if x < edgeColumns { edge.append(value) } else if x > width / 3 { centre.append(value) }
        }

        let bias = mean(sky)
        let noise = max(standardDeviation(sky, around: bias), 1e-6)

        let medianPeak = scene.stars.map(\.peak).sorted()[scene.stars.count / 2]
        let faint = scene.stars.filter { $0.peak <= medianPeak }
        let snr = faint.compactMap { star -> Float? in
            let index = Int(star.y.rounded()) * width + Int(star.x.rounded())
            guard !result[index].isNaN, index % width >= edgeColumns else { return nil }
            return (result[index] - (scene.background + bias)) / noise
        }

        let hotResidual = hot.filter { $0 % width >= edgeColumns }.compactMap { result[$0].isNaN ? nil : (result[$0] - truth[$0]) / noise }
        let trail = satellite.subtracting(nearStar).subtracting(hot).filter { $0 % width >= edgeColumns }
            .compactMap { result[$0].isNaN ? nil : (result[$0] - truth[$0]) / noise }

        return StackQuality(
            noise: noise, bias: bias, faintStarSNR: mean(snr),
            hotPixelResidual: mean(hotResidual), satelliteResidual: mean(trail),
            edgeRatio: centre.isEmpty ? 1 : mean(edge) / mean(centre)
        )
    }

    private static func starMask(_ scene: SkyScene) -> Set<Int> {
        let radius = Int((scene.psfSigma * 4).rounded(.up))
        var mask = Set<Int>()
        for star in scene.stars {
            let cx = Int(star.x.rounded())
            let cy = Int(star.y.rounded())
            for dy in -radius...radius {
                for dx in -radius...radius {
                    let x = cx + dx
                    let y = cy + dy
                    if x >= 0, x < scene.width, y >= 0, y < scene.height { mask.insert(y * scene.width + x) }
                }
            }
        }
        return mask
    }

    private static func mean(_ values: [Float]) -> Float {
        values.isEmpty ? 0 : values.reduce(0, +) / Float(values.count)
    }

    private static func standardDeviation(_ values: [Float], around centre: Float) -> Float {
        guard values.count > 1 else { return 0 }
        let squares = values.reduce(Float(0)) { $0 + ($1 - centre) * ($1 - centre) }
        return (squares / Float(values.count - 1)).squareRoot()
    }
}
