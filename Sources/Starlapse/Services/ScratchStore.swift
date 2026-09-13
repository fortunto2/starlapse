import Foundation
import os

/// The temporary files this app writes, and getting rid of them.
///
/// Time-lapses and event clips are written to disk before anyone decides whether to keep
/// them — a clip has to exist before you can watch it. Nothing removed them once saved, so
/// a night of detector work left every clip behind twice: once in Photos, once here. iOS
/// clears its temporary directory eventually, but "eventually" is not a size the user sees
/// in Settings, and it was showing up as tens of megabytes of "Documents & Data".
enum ScratchStore {

    private static let logger = Logger(subsystem: "co.superduperai.starlapse", category: "scratch")
    private static let prefix = "starlapse-"

    /// Where clips and time-lapses go before they are kept or discarded.
    static var directory: URL {
        FileManager.default.temporaryDirectory
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func remove(_ urls: [URL]) {
        urls.forEach(remove)
    }

    /// Delete anything this app left behind on a previous run.
    ///
    /// Called at launch. A session that ends by force-quitting — or by the battery dying
    /// on a tripod at 4am, which is the realistic case — never gets to clean up after
    /// itself, so the next launch does it instead.
    static func purgeLeftovers() {
        let manager = FileManager.default
        guard let contents = try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var removed = 0
        var bytes = 0

        for url in contents where url.lastPathComponent.hasPrefix(prefix) {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            remove(url)
            removed += 1
            bytes += size
        }

        if removed > 0 {
            logger.info("Cleared \(removed) leftover file(s), \(bytes / 1_048_576) MB")
        }
    }

    /// How much scratch space is currently in use — shown to the user rather than left as
    /// a surprise in Settings.
    static func bytesInUse() -> Int {
        let manager = FileManager.default
        guard let contents = try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        return contents
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .reduce(0) { total, url in
                total + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
    }
}
