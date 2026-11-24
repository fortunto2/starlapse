import AVFoundation
import Foundation
import os

/// Time-lapses a session left behind when it did not end on its own: a force-quit, a dead
/// battery on the tripod, iOS killing the app, an encoder that failed mid-night.
///
/// Until 1.2.2 the launch-time cleanup deleted these along with every other scratch file,
/// so the one thing that could have been saved was the first thing destroyed. Now they are
/// moved out of the temporary directory before the purge, and the capture screen offers
/// them. `TimelapseWriter` writes fragmented files, so a part cut off mid-write still
/// plays up to its last fragment.
enum RecoveredClips {

    private static let logger = Logger(subsystem: "co.superduperai.starlapse", category: "recovery")

    /// Outside `tmp`, which iOS may empty, and outside Documents, which the user sees.
    static var directory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Recovered", isDirectory: true)
    }

    /// Called at launch, before `ScratchStore.purgeLeftovers()`. Synchronous and cheap:
    /// only renames. Whether a file actually plays is decided later, off the launch path.
    static func rescueLeftovers() {
        let manager = FileManager.default
        guard let contents = try? manager.contentsOfDirectory(
            at: ScratchStore.directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return }
        let leftovers = contents.filter {
            $0.lastPathComponent.hasPrefix(TimelapseWriter.prefix) && $0.pathExtension == "mov"
        }
        guard !leftovers.isEmpty else { return }

        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        for url in leftovers {
            let target = directory.appendingPathComponent(url.lastPathComponent)
            try? manager.removeItem(at: target)
            do {
                try manager.moveItem(at: url, to: target)
            } catch {
                logger.error("Could not keep \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        logger.info("Kept \(leftovers.count) unfinished time-lapse file(s)")
    }

    /// Rescued clips that play, oldest first. Files that hold no frame are deleted.
    static func pending() async -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        var playable: [URL] = []
        for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if await isPlayable(url) { playable.append(url) } else { ScratchStore.remove(url) }
        }
        return playable
    }

    /// Holds at least one video frame that a player can reach.
    static func isPlayable(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty,
              let duration = try? await asset.load(.duration) else { return false }
        return duration.isNumeric && duration.seconds > 0
    }

    /// Concatenate clips without re-encoding. False leaves the inputs untouched.
    static func join(_ urls: [URL], into output: URL) async -> Bool {
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return false }

        var cursor = CMTime.zero
        for url in urls {
            let asset = AVURLAsset(url: url)
            guard let source = try? await asset.loadTracks(withMediaType: .video).first,
                  let duration = try? await asset.load(.duration) else { continue }
            let range = CMTimeRange(start: .zero, duration: duration)
            do {
                try track.insertTimeRange(range, of: source, at: cursor)
                cursor = CMTimeAdd(cursor, duration)
            } catch {
                logger.error("Skipping part \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        guard cursor > .zero,
              let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)
        else { return false }

        try? FileManager.default.removeItem(at: output)
        do {
            try await export.export(to: output, as: .mov)
            return true
        } catch {
            logger.error("Joining time-lapse parts failed: \(error.localizedDescription)")
            return false
        }
    }
}
