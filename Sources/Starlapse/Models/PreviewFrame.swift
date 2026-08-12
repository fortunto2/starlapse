import Metal

/// A rendered frame on its way to the screen, with its return ticket attached.
///
/// `@unchecked Sendable` is still a promise, but now it is one the code keeps rather than
/// one the doc comment makes. The texture inside is checked out of a `TexturePool`; the
/// producer cannot hand out the same one twice, and cannot reuse it until `release()` is
/// called. Whoever displays the frame is responsible for releasing it — see
/// `MetalPreviewView`, which does so from the command buffer's completion handler, i.e.
/// when the GPU is genuinely finished reading.
///
/// The earlier version wrapped a texture from a manually rotated pair and documented that
/// "the view reads this while the capture queue writes elsewhere". That held only for the
/// instant of the hand-off, and the view keeps a frame on screen until the next one lands.
struct PreviewFrame: @unchecked Sendable {
    let texture: MTLTexture
    private let pool: TexturePool

    init(texture: MTLTexture, pool: TexturePool) {
        self.texture = texture
        self.pool = pool
    }

    /// Give the texture back so the pipeline can render into it again.
    /// Safe to call more than once; the pool ignores duplicates.
    func release() {
        pool.release(texture)
    }
}
