import Foundation

/// Writing results to the photo library, and saying what happened.
///
/// Split from the main view model to keep it inside the size limit. The library calls
/// themselves live in `PhotoLibraryWriter`, which is nonisolated for a reason — see the
/// note there about Swift 6 executor checks.
extension CaptureViewModel {

    func save(image rendered: RenderedImage) async {
        guard await PhotoLibraryWriter.requestAccess() else {
            lastSavedMessage = PhotoLibraryWriter.WriteError.accessDenied.localizedDescription
            return
        }
        do {
            try await PhotoLibraryWriter.write(rendered)
            lastSavedMessage = "Saved \(progress.framesStacked) frames to Photos."
        } catch {
            lastSavedMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func save(videoAt url: URL) async {
        guard await PhotoLibraryWriter.requestAccess() else {
            lastSavedMessage = PhotoLibraryWriter.WriteError.accessDenied.localizedDescription
            return
        }
        do {
            try await PhotoLibraryWriter.write(videoAt: url)
            lastSavedMessage = "Saved \(progress.segmentsCompleted)-frame time-lapse to Photos."
        } catch {
            lastSavedMessage = "Save failed: \(error.localizedDescription)"
        }
    }
}
