import MetalKit
import SwiftUI

/// Displays the live view and the growing stack.
///
/// Before a session this is the raw sensor frame, for framing and focus. During one it is
/// the accumulated result — watching stars precipitate out of the noise is how you know
/// focus and framing are right, minutes before the session ends.
struct MetalPreviewView: UIViewRepresentable {

    /// Latest resolved texture. Changing it triggers a redraw.
    let texture: MTLTexture?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        let device = MTLCreateSystemDefaultDevice()
        view.device = device
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        // Redraw only when a new frame arrives. During a session frames land once a second;
        // a 60 Hz display loop would burn battery all night to show the same pixels.
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.delegate = context.coordinator
        view.isOpaque = true
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        context.coordinator.configure(device: device)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.texture = texture
        view.setNeedsDisplay()
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        var texture: MTLTexture?
        private var commandQueue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?

        func configure(device: MTLDevice?) {
            guard let device else { return }
            commandQueue = device.makeCommandQueue()

            guard let library = device.makeDefaultLibrary(),
                  let vertexFunction = library.makeFunction(name: "present_vertex"),
                  let fragmentFunction = library.makeFunction(name: "present_fragment") else {
                return
            }

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let descriptor = view.currentRenderPassDescriptor,
                  let commandQueue,
                  let buffer = commandQueue.makeCommandBuffer() else { return }

            if let texture, let pipeline,
               let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) {
                encoder.setRenderPipelineState(pipeline)
                encoder.setFragmentTexture(texture, index: 0)

                // Aspect-fit. A sensor frame is 4:3; a phone screen is roughly 19.5:9, so
                // without this the sky would be stretched into something that is not the
                // sky. Scale > 1 on an axis widens the sampling window and letterboxes.
                var scale = Self.aspectFitScale(
                    source: CGSize(width: texture.width, height: texture.height),
                    destination: view.drawableSize
                )
                encoder.setFragmentBytes(&scale, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                encoder.endEncoding()
            } else if let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) {
                // No frame yet — clear to black rather than showing stale contents.
                encoder.endEncoding()
            }

            buffer.present(drawable)
            buffer.commit()
        }

        static func aspectFitScale(source: CGSize, destination: CGSize) -> SIMD2<Float> {
            guard source.width > 0, source.height > 0,
                  destination.width > 0, destination.height > 0 else {
                return SIMD2(1, 1)
            }

            let sourceAspect = source.width / source.height
            let destinationAspect = destination.width / destination.height

            if sourceAspect > destinationAspect {
                // Source is wider: it fits across, so pad vertically.
                return SIMD2(1, Float(sourceAspect / destinationAspect))
            } else {
                return SIMD2(Float(destinationAspect / sourceAspect), 1)
            }
        }
    }
}
