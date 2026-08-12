import CoreVideo
import Foundation
import Metal
import simd

/// Holds the growing stack on the GPU.
///
/// `@unchecked Sendable` under the same contract as `CaptureEngine`: every method here is
/// called from the capture queue and nowhere else. Metal command buffers are cheap to
/// build and the work per frame is a single dispatch, so at one frame per second this
/// costs a rounding error of GPU time.
final class FrameAccumulator: @unchecked Sendable {

    /// Tone-mapping controls, matching the `ToneParams` struct in Stacking.metal.
    struct ToneSettings: Sendable, Equatable {
        /// Sky background to subtract. Light pollution raises this.
        var blackPoint: Float = 0.02
        /// asinh strength. Higher digs deeper into the noise.
        var stretch: Float = 12
        var exposure: Float = 1.0
        var saturation: Float = 1.35

        static let neutral = ToneSettings(blackPoint: 0, stretch: 0.001, exposure: 1, saturation: 1)
    }

    private struct StackParams {
        var transform: simd_float3x3
        var mode: UInt32
        var frameIndex: UInt32
        var useTransform: UInt32
    }

    private struct ToneParams {
        var blackPoint: Float
        var stretch: Float
        var exposure: Float
        var saturation: Float
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let accumulatePipeline: MTLComputePipelineState
    private let clearPipeline: MTLComputePipelineState
    private let resolvePipeline: MTLComputePipelineState
    private let downsamplePipeline: MTLComputePipelineState
    private var textureCache: CVMetalTextureCache?

    /// How many frames may be in flight between the capture queue and the screen.
    ///
    /// This is a correctness number, not a memory-tuning one. The first version used a
    /// single display texture, resolved on the capture queue and simultaneously read by the
    /// view on the main thread — a data race on GPU memory that crashed at the end of a
    /// session, exactly when the final render and the next frame overlapped. Two means the
    /// view always reads the one the GPU is not writing. Lowering it to one restores the
    /// crash; raising it only costs memory.
    static let displayBufferCount = 2

    private var accumulator: MTLTexture?
    private var displays: [MTLTexture] = []
    private var displayIndex = 0
    private var luma: MTLTexture?

    private(set) var frameCount: Int = 0
    private(set) var width: Int = 0
    private(set) var height: Int = 0

    /// Star detection runs on a downsampled luminance copy. A quarter-width buffer keeps
    /// the CPU readback at a few hundred kilobytes while still locating stars to a
    /// fraction of a pixel once centroided.
    private let lumaScale = 4

    var lumaWidth: Int { max(1, width / lumaScale) }
    var lumaHeight: Int { max(1, height / lumaScale) }

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw StackError.metalUnavailable
        }
        guard let queue = device.makeCommandQueue() else {
            throw StackError.metalUnavailable
        }
        guard let library = device.makeDefaultLibrary() else {
            throw StackError.shaderLibraryMissing
        }

        func pipeline(_ name: String) throws -> MTLComputePipelineState {
            guard let function = library.makeFunction(name: name) else {
                throw StackError.shaderMissing(name)
            }
            return try device.makeComputePipelineState(function: function)
        }

        self.device = device
        self.commandQueue = queue
        self.accumulatePipeline = try pipeline("accumulate")
        self.clearPipeline = try pipeline("clear_accumulator")
        self.resolvePipeline = try pipeline("resolve")
        self.downsamplePipeline = try pipeline("downsample_luma")

        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
    }

    // MARK: - Lifecycle

    /// Prepare for a frame size without disturbing what is already accumulated.
    ///
    /// Split out from `reset` because the framing path needs the textures to exist but has
    /// no stack to clear — and clearing an RGBA32Float accumulator at full sensor
    /// resolution is ~200 MB of pointless GPU writes, several times a second.
    func prepare(width: Int, height: Int) {
        guard self.width != width || self.height != height || accumulator == nil else { return }
        reset(width: width, height: height)
    }

    /// (Re)allocate for a given frame size and clear the stack.
    func reset(width: Int, height: Int) {
        if self.width != width || self.height != height || accumulator == nil {
            self.width = width
            self.height = height
            accumulator = makeTexture(
                width: width, height: height, format: .rgba32Float,
                usage: [.shaderRead, .shaderWrite]
            )
            // Both, or neither. `compactMap` here would silently accept one texture, which
            // makes `resolve()` hand back the same texture every call — single-buffered,
            // i.e. exactly the data race this pair exists to prevent, with no error and no
            // log to say so.
            let pair = (0..<Self.displayBufferCount).map { _ in
                makeTexture(
                    width: width, height: height, format: .bgra8Unorm,
                    usage: [.shaderRead, .shaderWrite]
                )
            }
            displays = pair.contains(where: { $0 == nil }) ? [] : pair.compactMap { $0 }
            luma = makeTexture(
                width: lumaWidth, height: lumaHeight, format: .r32Float,
                usage: [.shaderRead, .shaderWrite]
            )
        }
        clear()
    }

    func clear() {
        frameCount = 0
        guard let accumulator,
              let buffer = commandQueue.makeCommandBuffer(),
              let encoder = buffer.makeComputeCommandEncoder() else { return }

        encoder.setComputePipelineState(clearPipeline)
        encoder.setTexture(accumulator, index: 0)
        dispatch(encoder, pipeline: clearPipeline, width: accumulator.width, height: accumulator.height)
        encoder.endEncoding()
        buffer.commit()
    }

    private func makeTexture(
        width: Int, height: Int, format: MTLPixelFormat, usage: MTLTextureUsage
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: width, height: height, mipmapped: false
        )
        descriptor.usage = usage
        descriptor.storageMode = .shared
        return device.makeTexture(descriptor: descriptor)
    }

    // MARK: - Per-frame work

    /// Wrap a camera pixel buffer as a Metal texture without copying it.
    private func texture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let textureCache else { return nil }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var wrapped: CVMetalTexture?

        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, pixelBuffer, nil,
            .bgra8Unorm, width, height, 0, &wrapped
        )
        guard status == kCVReturnSuccess, let wrapped else { return nil }
        return CVMetalTextureGetTexture(wrapped)
    }

    /// Pull the downsampled luminance back to the CPU for star detection.
    /// Returns nil until a frame has been through `downsample`.
    func readLuminance(from pixelBuffer: CVPixelBuffer) -> [Float]? {
        guard let source = texture(from: pixelBuffer), let luma else { return nil }
        guard let buffer = commandQueue.makeCommandBuffer(),
              let encoder = buffer.makeComputeCommandEncoder() else { return nil }

        encoder.setComputePipelineState(downsamplePipeline)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(luma, index: 1)
        dispatch(encoder, pipeline: downsamplePipeline, width: luma.width, height: luma.height)
        encoder.endEncoding()

        buffer.commit()
        // Star detection is the next step and needs the pixels, so this one blocking wait
        // is unavoidable. At one frame per second it is invisible.
        buffer.waitUntilCompleted()

        var pixels = [Float](repeating: 0, count: luma.width * luma.height)
        pixels.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            luma.getBytes(
                base,
                bytesPerRow: luma.width * MemoryLayout<Float>.size,
                from: MTLRegionMake2D(0, 0, luma.width, luma.height),
                mipmapLevel: 0
            )
        }
        return pixels
    }

    /// Add one frame to the stack, optionally warped to cancel the sky's rotation.
    func add(_ pixelBuffer: CVPixelBuffer, transform: simd_float3x3?, mode: StackMode) {
        blend(pixelBuffer, transform: transform, shaderMode: mode == .trails ? 1 : 0)
        frameCount += 1
    }

    /// Overwrite the buffer with a single frame, for the framing preview.
    ///
    /// Distinct from `add` because there is nothing to accumulate: this frame replaces the
    /// last. Going through `reset` + `add` instead would clear a full-resolution
    /// RGBA32Float texture several times a second to write zeros that the same dispatch
    /// immediately overwrites.
    func show(_ pixelBuffer: CVPixelBuffer) {
        blend(pixelBuffer, transform: nil, shaderMode: 2)
        frameCount = 1
    }

    private func blend(_ pixelBuffer: CVPixelBuffer, transform: simd_float3x3?, shaderMode: UInt32) {
        guard let source = texture(from: pixelBuffer), let accumulator else { return }
        guard let buffer = commandQueue.makeCommandBuffer(),
              let encoder = buffer.makeComputeCommandEncoder() else { return }

        var params = StackParams(
            transform: transform ?? matrix_identity_float3x3,
            mode: shaderMode,
            frameIndex: UInt32(frameCount),
            useTransform: transform == nil ? 0 : 1
        )

        encoder.setComputePipelineState(accumulatePipeline)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(accumulator, index: 1)
        encoder.setBytes(&params, length: MemoryLayout<StackParams>.stride, index: 0)
        dispatch(encoder, pipeline: accumulatePipeline, width: accumulator.width, height: accumulator.height)
        encoder.endEncoding()
        buffer.commit()
    }

    /// Render the current stack. Must be called on the capture queue.
    ///
    /// Alternates between the two display textures so the returned one is never the one
    /// the view is currently reading.
    func resolve(tone: ToneSettings, mode: StackMode) -> MTLTexture? {
        guard let accumulator, !displays.isEmpty else { return nil }
        displayIndex = (displayIndex + 1) % displays.count
        let display = displays[displayIndex]

        guard let buffer = commandQueue.makeCommandBuffer(),
              let encoder = buffer.makeComputeCommandEncoder() else { return nil }

        var toneParams = ToneParams(
            blackPoint: tone.blackPoint,
            stretch: tone.stretch,
            exposure: tone.exposure,
            saturation: tone.saturation
        )
        var count = UInt32(max(frameCount, 1))
        var modeValue = UInt32(mode == .trails ? 1 : 0)

        encoder.setComputePipelineState(resolvePipeline)
        encoder.setTexture(accumulator, index: 0)
        encoder.setTexture(display, index: 1)
        encoder.setBytes(&toneParams, length: MemoryLayout<ToneParams>.stride, index: 0)
        encoder.setBytes(&count, length: MemoryLayout<UInt32>.stride, index: 1)
        encoder.setBytes(&modeValue, length: MemoryLayout<UInt32>.stride, index: 2)
        dispatch(encoder, pipeline: resolvePipeline, width: display.width, height: display.height)
        encoder.endEncoding()

        buffer.commit()
        buffer.waitUntilCompleted()
        return display
    }

    /// Copy a rendered texture into plain bytes.
    ///
    /// Saving happens on the main actor, and an `MTLTexture` must never travel there —
    /// GPU memory keeps being written behind it. A `Data` blob is genuinely `Sendable` and
    /// costs one copy, once, at the end of a session.
    func snapshot(of texture: MTLTexture) -> RenderedImage {
        let bytesPerRow = texture.width * 4
        var pixels = Data(count: bytesPerRow * texture.height)
        pixels.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            texture.getBytes(
                base,
                bytesPerRow: bytesPerRow,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        return RenderedImage(
            pixels: pixels,
            width: texture.width,
            height: texture.height,
            bytesPerRow: bytesPerRow
        )
    }

    private func dispatch(
        _ encoder: MTLComputeCommandEncoder,
        pipeline: MTLComputePipelineState,
        width: Int,
        height: Int
    ) {
        let threadWidth = pipeline.threadExecutionWidth
        let threadHeight = max(1, pipeline.maxTotalThreadsPerThreadgroup / threadWidth)
        let threadgroup = MTLSize(width: threadWidth, height: threadHeight, depth: 1)
        let grid = MTLSize(
            width: (width + threadWidth - 1) / threadWidth,
            height: (height + threadHeight - 1) / threadHeight,
            depth: 1
        )
        encoder.dispatchThreadgroups(grid, threadsPerThreadgroup: threadgroup)
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
