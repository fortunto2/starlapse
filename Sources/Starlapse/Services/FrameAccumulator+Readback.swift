import CoreVideo
import Foundation
import Metal

// Split from FrameAccumulator.swift to keep it inside the file-length limit.

extension FrameAccumulator {

    /// The decoded frame as linear RGB triplets, row-major. For checking the GPU decode
    /// against StackKit's CPU reference; a camera is not needed, Metal on a simulator is.
    func linearPixels(from pixelBuffer: CVPixelBuffer) -> [SIMD3<Float>]? {
        guard let texture = decode(pixelBuffer) else { return nil }
        var halves = [Float16](repeating: 0, count: texture.width * texture.height * 4)
        halves.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            texture.getBytes(
                base, bytesPerRow: texture.width * 8,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0
            )
        }
        return stride(from: 0, to: halves.count, by: 4).map {
            SIMD3(Float(halves[$0]), Float(halves[$0 + 1]), Float(halves[$0 + 2]))
        }
    }
}

enum StackError: LocalizedError {
    case metalUnavailable
    case shaderLibraryMissing
    case shaderMissing(String)

    var errorDescription: String? {
        switch self {
        case .metalUnavailable: "This device has no usable Metal GPU."
        case .shaderLibraryMissing: "Shader library missing from the app bundle."
        case .shaderMissing(let name): "Shader function '\(name)' not found."
        }
    }
}
