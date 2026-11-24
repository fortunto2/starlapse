import AVFoundation
import Foundation
import Metal
import Testing
@testable import Starlapse

/// A night that ends without `finish()` — killed process, dead battery, failed encoder —
/// must still leave a clip that plays. Lost in 1.2.1: three hours of Star Trails, nothing kept.
@Suite("An interrupted time-lapse is kept", .serialized)
struct TimelapseRecoveryTests {

    static let size = 128

    static func texture() throws -> MTLTexture {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false
        )
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let bytes = [UInt8](repeating: 90, count: size * size * 4)
        texture.replace(
            region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0, withBytes: bytes, bytesPerRow: size * 4
        )
        return texture
    }

    static func partFiles() -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: ScratchStore.directory, includingPropertiesForKeys: nil
        )) ?? []
        return contents.filter { $0.lastPathComponent.hasPrefix(TimelapseWriter.prefix) }
    }

    static func clean() {
        ScratchStore.remove(partFiles())
        try? FileManager.default.removeItem(at: RecoveredClips.directory)
    }

    @Test("Frames written before the process dies still play, and the next launch keeps them")
    func unfinishedFilePlays() async throws {
        Self.clean()
        defer { Self.clean() }

        let writer = try TimelapseWriter(width: Self.size, height: Self.size, frameRate: 30)
        let texture = try Self.texture()
        for index in 0..<12 { writer.append(texture, frameIndex: index) }
        #expect(writer.framesWritten == 12)
        // No finish(): this is the crash. Give the writer a moment to land its fragments.
        try await Task.sleep(for: .milliseconds(500))

        let part = try #require(Self.partFiles().first)
        #expect(await RecoveredClips.isPlayable(part))

        RecoveredClips.rescueLeftovers()
        #expect(Self.partFiles().isEmpty)
        let pending = await RecoveredClips.pending()
        #expect(pending.count == 1)
        _ = writer
    }

    @Test("A finished session returns one playable clip")
    func finishedFilePlays() async throws {
        Self.clean()
        defer { Self.clean() }

        let writer = try TimelapseWriter(width: Self.size, height: Self.size, frameRate: 30)
        let texture = try Self.texture()
        for index in 0..<5 { writer.append(texture, frameIndex: index) }
        let url = try #require(await writer.finish())
        #expect(await RecoveredClips.isPlayable(url))
        #expect(writer.failures == 0)
    }

    @Test("Parts are joined into one clip as long as all of them")
    func partsJoin() async throws {
        Self.clean()
        defer { Self.clean() }

        var parts: [URL] = []
        for _ in 0..<2 {
            let writer = try TimelapseWriter(width: Self.size, height: Self.size, frameRate: 30)
            let texture = try Self.texture()
            for index in 0..<30 { writer.append(texture, frameIndex: index) }
            let url = try #require(await writer.finish())
            let moved = url.deletingLastPathComponent().appendingPathComponent("join-\(parts.count).mov")
            try FileManager.default.moveItem(at: url, to: moved)
            parts.append(moved)
            try await Task.sleep(for: .seconds(1.1)) // a new stamp, a new file name
        }
        let joined = ScratchStore.directory.appendingPathComponent("join-out.mov")
        defer { ScratchStore.remove(parts + [joined]) }
        #expect(await RecoveredClips.join(parts, into: joined))
        let duration = try await AVURLAssetDuration.seconds(joined)
        #expect(abs(duration - 2.0) < 0.1)
    }
}

private enum AVURLAssetDuration {
    static func seconds(_ url: URL) async throws -> Double {
        try await AVURLAsset(url: url).load(.duration).seconds
    }
}
