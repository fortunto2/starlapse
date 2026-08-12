import Foundation
import Photos
import UIKit

/// Writes finished work to the photo library.
///
/// Every method here is `nonisolated`, and that is the entire reason this type exists as
/// something separate from the view model.
///
/// `PHPhotoLibrary.performChanges` runs its block on its own internal queue. A block written
/// inline inside a `@MainActor` method inherits main-actor isolation, so Swift 6 emits a
/// runtime executor check inside it — which fires on Photos' queue and kills the process
/// with SIGTRAP. That crashed the app at the end of every single shoot, and survived two
/// rounds of fixes aimed at the Metal pipeline before a crash report named it.
///
/// Keeping the library calls in a type that has no actor makes the mistake hard to repeat.
enum PhotoLibraryWriter {

    enum WriteError: LocalizedError {
        case accessDenied
        case couldNotRender

        var errorDescription: String? {
            switch self {
            case .accessDenied: "Photo library access denied."
            case .couldNotRender: "Could not render the stack into an image."
            }
        }
    }

    static func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return status == .authorized || status == .limited
    }

    static func write(_ rendered: RenderedImage) async throws {
        guard let image = rendered.makeUIImage() else {
            throw WriteError.couldNotRender
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }

    static func write(videoAt url: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }

    /// Save a batch, returning how many made it. Used by the detector, which can come back
    /// from a night with dozens of clips.
    static func write(videosAt urls: [URL]) async -> Int {
        var saved = 0
        for url in urls {
            do {
                try await write(videoAt: url)
                saved += 1
            } catch {
                continue
            }
        }
        return saved
    }
}
