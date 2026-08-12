import Foundation
import Metal

/// A small set of display textures with explicit ownership.
///
/// Double buffering by itself only guarantees the *instant of hand-off*: the texture handed
/// over is not the one being written right then. It says nothing about how long the consumer
/// holds it, and the consumer here holds it indefinitely — the view keeps the last frame on
/// screen until a new one arrives. With enough frames in flight the producer wraps around
/// and starts writing into the texture the display is sampling.
///
/// So ownership is tracked rather than assumed. A texture is checked out for rendering and
/// checked back in once the view is finished with it. If nothing is free the producer skips
/// the preview for that frame — it never blocks. Blocking would be worse than a dropped
/// preview: the capture queue also carries the actual photons, and stalling it to wait on a
/// screen refresh would cost light.
final class TexturePool: @unchecked Sendable {

    private let lock = NSLock()
    private var textures: [MTLTexture] = []
    private var available: [Int] = []
    /// Maps a texture back to its slot, so `release` needs no bookkeeping from the caller.
    private var slots: [ObjectIdentifier: Int] = [:]

    private(set) var width = 0
    private(set) var height = 0

    /// Rebuild for a new frame size. Throws rather than degrading: a pool that came back
    /// half-allocated would silently behave like a single buffer, which is the data race
    /// this type exists to prevent.
    func configure(
        count: Int,
        width: Int,
        height: Int,
        make: (Int, Int) -> MTLTexture?
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        guard self.width != width || self.height != height || textures.isEmpty else { return }

        var built: [MTLTexture] = []
        built.reserveCapacity(count)
        for _ in 0..<count {
            guard let texture = make(width, height) else {
                throw StackError.metalUnavailable
            }
            built.append(texture)
        }

        textures = built
        available = Array(0..<count)
        slots = Dictionary(
            uniqueKeysWithValues: built.enumerated().map { (ObjectIdentifier($0.element), $0.offset) }
        )
        self.width = width
        self.height = height
    }

    /// Check out a texture to render into, or nil if the consumer still holds them all.
    func acquire() -> MTLTexture? {
        lock.lock()
        defer { lock.unlock() }
        guard let slot = available.popLast() else { return nil }
        return textures[slot]
    }

    /// Hand a texture back once it is no longer on screen.
    func release(_ texture: MTLTexture) {
        lock.lock()
        defer { lock.unlock() }
        guard let slot = slots[ObjectIdentifier(texture)], !available.contains(slot) else { return }
        available.append(slot)
    }

    /// Reclaim everything — used when tearing down or resizing.
    func releaseAll() {
        lock.lock()
        defer { lock.unlock() }
        available = Array(0..<textures.count)
    }
}
