import Metal

/// A rendered frame on its way to the screen.
///
/// `@unchecked Sendable` under one specific guarantee, and it is worth stating precisely
/// because the unchecked version of this crashed in the field:
///
/// `FrameAccumulator` keeps **two** display textures and alternates between them. The one
/// wrapped here is the one just finished; the next render goes to the other. So while the
/// view reads this texture on the main thread, the capture queue is writing elsewhere.
///
/// What is *not* safe, and what this type does not permit, is the main actor reaching back
/// into the accumulator to ask for a render — that shared the command queue with the
/// capture path and crashed at the end of a session. Frames are pushed, never pulled.
struct PreviewFrame: @unchecked Sendable {
    let texture: MTLTexture
}
