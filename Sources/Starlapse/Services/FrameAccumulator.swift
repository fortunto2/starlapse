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
        /// Sky background to subtract, in linear light. Light pollution raises this.
        ///
        /// The defaults moved when the stack moved to linear light: `starlapse-stack tone`
        /// fits the linear settings that reproduce the encoded 0.02 / 12 look to ±0.02.
        var blackPoint: Float = 0.0064
        /// asinh strength. Higher digs deeper into the noise.
        var stretch: Float = 158
        var exposure: Float = 1.0
        var saturation: Float = 1.35

        static let neutral = ToneSettings(blackPoint: 0, stretch: 0.001, exposure: 1, saturation: 1)
    }

    private struct StackParams {
        var transform: simd_float3x3
        var mode: UInt32
        var frameIndex: UInt32
        var useTransform: UInt32
        var kappa: Float
        var warmup: UInt32
    }

    private struct DecodeParams {
        var fullRange: UInt32
        var hotRatio: Float
        var hotFloor: Float
    }

    /// Sigma-clip settings, as `starlapse-stack compare` chose them: 3σ cost 8% of faint-star
    /// SNR, 4σ cost nothing and still removed the satellite.
    static let clipKappa: Float = 4
    static let clipWarmup: UInt32 = 8

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
    private let decodeYCbCrPipeline: MTLComputePipelineState
    private let decodeBGRAPipeline: MTLComputePipelineState
    private var textureCache: CVMetalTextureCache?

    /// How many frames may be in flight between the capture queue and the screen.
    ///
    /// Three, because the display genuinely holds one: the view keeps the last frame on
    /// screen until a new one arrives. One for the GPU to render into, one on screen, one
    /// in transit. Ownership is tracked by `TexturePool` rather than assumed — with a bare
    /// rotating pair the producer eventually wrapped around onto the texture being sampled.
    static let displayBufferCount = 3

    private var accumulator: MTLTexture?
    /// Running M2 of luminance per pixel, for sigma clipping.
    private var spread: MTLTexture?
    /// The current camera frame in linear light, after cosmetic correction.
    private var decoded: MTLTexture?
    /// The camera buffer `decoded` holds. Held strongly, so the camera's pool cannot hand
    /// the same buffer back with new contents while this identity check trusts it.
    private var decodedSource: CVPixelBuffer?
    let displayPool = TexturePool()
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
        self.decodeYCbCrPipeline = try pipeline("decode_ycbcr")
        self.decodeBGRAPipeline = try pipeline("decode_bgra")

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
            spread = makeTexture(
                width: width, height: height, format: .r32Float,
                usage: [.shaderRead, .shaderWrite]
            )
            decoded = makeTexture(
                width: width, height: height, format: .rgba16Float,
                usage: [.shaderRead, .shaderWrite]
            )
            decodedSource = nil
            try? displayPool.configure(
                count: Self.displayBufferCount,
                width: width,
                height: height
            ) { width, height in
                makeTexture(
                    width: width, height: height, format: .bgra8Unorm,
                    usage: [.shaderRead, .shaderWrite]
                )
            }
            luma = makeTexture(
                width: lumaWidth, height: lumaHeight, format: .r32Float,
                usage: [.shaderRead, .shaderWrite]
            )
        }
        clear()
    }

    func clear() {
        frameCount = 0
        guard let accumulator, let spread,
              let buffer = commandQueue.makeCommandBuffer(),
              let encoder = buffer.makeComputeCommandEncoder() else { return }

        encoder.setComputePipelineState(clearPipeline)
        encoder.setTexture(accumulator, index: 0)
        encoder.setTexture(spread, index: 1)
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

    /// Pull the downsampled luminance back to the CPU for star detection.
    /// Returns nil until a frame has been through `downsample`.
    func readLuminance(from pixelBuffer: CVPixelBuffer) -> [Float]? {
        guard let source = decode(pixelBuffer), let luma else { return nil }
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
    ///
    /// `replacingContents` overwrites the buffer instead of accumulating into it — what the
    /// first frame of every segment does. That removes the need to clear beforehand, which
    /// at full sensor resolution is a ~200 MB write of zeros the next dispatch overwrites
    /// anyway, and removes the whole class of "stacked on top of the previous segment" bugs.
    func add(
        _ pixelBuffer: CVPixelBuffer,
        transform: simd_float3x3?,
        mode: StackMode,
        replacingContents: Bool = false
    ) {
        let shaderMode: UInt32 = replacingContents ? 2 : (mode == .trails ? 1 : 0)
        blend(pixelBuffer, transform: transform, shaderMode: shaderMode)
        frameCount = replacingContents ? 1 : frameCount + 1
        // Done with this camera buffer: let the pool have it back.
        decodedSource = nil
    }

    private func blend(_ pixelBuffer: CVPixelBuffer, transform: simd_float3x3?, shaderMode: UInt32) {
        guard let source = decode(pixelBuffer), let accumulator, let spread else { return }
        guard let buffer = commandQueue.makeCommandBuffer(),
              let encoder = buffer.makeComputeCommandEncoder() else { return }

        var params = StackParams(
            transform: transform ?? matrix_identity_float3x3,
            mode: shaderMode,
            frameIndex: UInt32(frameCount),
            useTransform: transform == nil ? 0 : 1,
            kappa: Self.clipKappa,
            warmup: Self.clipWarmup
        )

        encoder.setComputePipelineState(accumulatePipeline)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(accumulator, index: 1)
        encoder.setTexture(spread, index: 2)
        encoder.setBytes(&params, length: MemoryLayout<StackParams>.stride, index: 0)
        dispatch(encoder, pipeline: accumulatePipeline, width: accumulator.width, height: accumulator.height)
        encoder.endEncoding()
        buffer.commit()
    }

    /// Render the current stack. Must be called on the capture queue.
    ///
    /// Returns nil when the display still holds every pooled texture. Skipping a preview
    /// frame is the right failure here — blocking would stall the queue that carries the
    /// actual photons.
    func resolve(tone: ToneSettings, mode: StackMode) -> MTLTexture? {
        guard let accumulator, let display = displayPool.acquire() else { return nil }

        guard let buffer = commandQueue.makeCommandBuffer(),
              let encoder = buffer.makeComputeCommandEncoder() else { return nil }

        var toneParams = ToneParams(
            blackPoint: tone.blackPoint,
            stretch: tone.stretch,
            exposure: tone.exposure,
            saturation: tone.saturation
        )
        var modeValue = UInt32(mode == .trails ? 1 : 0)

        encoder.setComputePipelineState(resolvePipeline)
        encoder.setTexture(accumulator, index: 0)
        encoder.setTexture(display, index: 1)
        encoder.setBytes(&toneParams, length: MemoryLayout<ToneParams>.stride, index: 0)
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

// MARK: - Decoding

extension FrameAccumulator {

    /// Wrap one plane of a camera pixel buffer as a Metal texture without copying it.
    private func wrap(
        _ pixelBuffer: CVPixelBuffer, plane: Int, format: MTLPixelFormat
    ) -> CVMetalTexture? {
        guard let textureCache else { return nil }
        let planar = CVPixelBufferIsPlanar(pixelBuffer)
        let width = planar ? CVPixelBufferGetWidthOfPlane(pixelBuffer, plane) : CVPixelBufferGetWidth(pixelBuffer)
        let height = planar ? CVPixelBufferGetHeightOfPlane(pixelBuffer, plane) : CVPixelBufferGetHeight(pixelBuffer)
        var wrapped: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, pixelBuffer, nil,
            format, width, height, plane, &wrapped
        )
        return status == kCVReturnSuccess ? wrapped : nil
    }

    /// The camera frame in linear light, hot pixels removed. Decoded once per buffer.
    ///
    /// Takes whatever the camera delivers: biplanar 4:2:0 at 8 or 10 bits (the format's
    /// own pixels, no conversion asked of AVFoundation) or BGRA (the detector, whose ring
    /// buffer copies single-plane frames). Waits for the GPU: the plane wrappers must
    /// outlive the work that reads them, and at one frame a second the wait is invisible.
    private func decode(_ pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let decoded,
              CVPixelBufferGetWidth(pixelBuffer) == decoded.width,
              CVPixelBufferGetHeight(pixelBuffer) == decoded.height else { return nil }
        if decodedSource === pixelBuffer { return decoded }

        let layout = FramePixels(CVPixelBufferGetPixelFormatType(pixelBuffer))
        var wrappers: [CVMetalTexture] = []
        let pipeline: MTLComputePipelineState
        switch layout {
        case .biplanar(let tenBit, _):
            guard let luma = wrap(pixelBuffer, plane: 0, format: tenBit ? .r16Unorm : .r8Unorm),
                  let chroma = wrap(pixelBuffer, plane: 1, format: tenBit ? .rg16Unorm : .rg8Unorm)
            else { return nil }
            wrappers = [luma, chroma]
            pipeline = decodeYCbCrPipeline
        case .bgra:
            guard let frame = wrap(pixelBuffer, plane: 0, format: .bgra8Unorm_srgb) else { return nil }
            wrappers = [frame]
            pipeline = decodeBGRAPipeline
        case .unsupported:
            return nil
        }
        guard let buffer = commandQueue.makeCommandBuffer(),
              let encoder = buffer.makeComputeCommandEncoder() else { return nil }

        var params = DecodeParams(fullRange: layout.isFullRange ? 1 : 0, hotRatio: 3, hotFloor: 0.02)
        encoder.setComputePipelineState(pipeline)
        for (index, wrapper) in wrappers.enumerated() {
            encoder.setTexture(CVMetalTextureGetTexture(wrapper), index: index)
        }
        encoder.setTexture(decoded, index: 2)
        encoder.setBytes(&params, length: MemoryLayout<DecodeParams>.stride, index: 0)
        dispatch(encoder, pipeline: pipeline, width: decoded.width, height: decoded.height)
        encoder.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        withExtendedLifetime(wrappers) {}

        decodedSource = pixelBuffer
        return decoded
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

/// What the camera put in a pixel buffer, as far as decoding cares.
enum FramePixels: Equatable {
    case biplanar(tenBit: Bool, fullRange: Bool)
    case bgra
    case unsupported

    init(_ type: OSType) {
        switch type {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange: self = .biplanar(tenBit: false, fullRange: false)
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange: self = .biplanar(tenBit: false, fullRange: true)
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange: self = .biplanar(tenBit: true, fullRange: false)
        case kCVPixelFormatType_420YpCbCr10BiPlanarFullRange: self = .biplanar(tenBit: true, fullRange: true)
        case kCVPixelFormatType_32BGRA: self = .bgra
        default: self = .unsupported
        }
    }

    var isFullRange: Bool {
        if case .biplanar(_, let fullRange) = self { return fullRange }
        return true
    }

    /// The output formats to ask the camera for when stacking, best first: the sensor's
    /// own 4:2:0 at full range, then video range, then 10-bit. BGRA is the last resort.
    static let stackingPreference: [OSType] = [
        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
        kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
        kCVPixelFormatType_32BGRA,
    ]
}
