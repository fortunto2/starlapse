import MetalKit
import SwiftUI

/// Displays the live stack.
///
/// The preview is the accumulated result, not the raw camera feed — which is the point.
/// A single one-second frame of night sky looks like noise; watching stars precipitate out
/// of that noise as frames pile up is the moment the app earns its keep, and it also tells
/// you whether focus and framing are right long before the session ends.
struct MetalPreviewView: UIViewRepresentable {

    /// Latest resolved texture. Changing it triggers a redraw.
    let texture: MTLTexture?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.framebufferOnly = false
        // Redraw only when a new stack is resolved. At one frame per second, a 60 Hz
        // display loop would burn battery all night for nothing.
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.delegate = context.coordinator
        view.backgroundColor = .black
        view.contentMode = .scaleAspectFit
        context.coordinator.commandQueue = view.device?.makeCommandQueue()
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.texture = texture
        view.setNeedsDisplay()
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        var texture: MTLTexture?
        var commandQueue: MTLCommandQueue?

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let commandQueue,
                  let buffer = commandQueue.makeCommandBuffer() else { return }

            if let texture, let blit = buffer.makeBlitCommandEncoder() {
                // Letterbox: copy the largest centred region that fits, so the preview
                // never stretches the sky.
                let width = min(texture.width, drawable.texture.width)
                let height = min(texture.height, drawable.texture.height)
                blit.copy(
                    from: texture,
                    sourceSlice: 0, sourceLevel: 0,
                    sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                    sourceSize: MTLSize(width: width, height: height, depth: 1),
                    to: drawable.texture,
                    destinationSlice: 0, destinationLevel: 0,
                    destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
                )
                blit.endEncoding()
            }

            buffer.present(drawable)
            buffer.commit()
        }
    }
}
