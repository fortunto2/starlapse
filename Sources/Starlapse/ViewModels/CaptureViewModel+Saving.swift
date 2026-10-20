import Foundation
import SuperDuperAnalytics

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
            lastSavedMessage = String(format: String(localized: "Saved %d frames to Photos."), progress.framesStacked)
            Analytics.track(
                "capture_saved", props: ["kind": "photo"], metrics: ["frames": Double(progress.framesStacked)]
            )
            await remindersAfterSave(ratingPromptShown: RatingPrompt.saved())
            // Not awaited: Save is done when the photo is in the library, not when a
            // dataset upload over a field's one bar of signal finishes.
            Task { await contribute(rendered) }
        } catch {
            lastSavedMessage = String(format: String(localized: "Save failed: %@"), error.localizedDescription)
        }
    }

    func save(videoAt url: URL) async {
        guard await PhotoLibraryWriter.requestAccess() else {
            lastSavedMessage = PhotoLibraryWriter.WriteError.accessDenied.localizedDescription
            return
        }
        do {
            try await PhotoLibraryWriter.write(videoAt: url)
            lastSavedMessage = String(
                format: String(localized: "Saved %d-frame time-lapse to Photos."), progress.segmentsCompleted
            )
            Analytics.track(
                "capture_saved", props: ["kind": "video"], metrics: ["frames": Double(progress.segmentsCompleted)]
            )
            await remindersAfterSave(ratingPromptShown: RatingPrompt.saved())
        } catch {
            lastSavedMessage = String(format: String(localized: "Save failed: %@"), error.localizedDescription)
        }
    }

    /// Every kind of save, photo, time-lapse or detector clip, is the moment to ask once for
    /// reminders, and to rebuild them.
    func remindersAfterSave(ratingPromptShown: Bool = false) async {
        await ShowerAlerts.askAfterSaveIfNeeded(ratingPromptShown: ratingPromptShown)
        rescheduleAlerts()
    }

    func saveAllEvents() async {
        guard await PhotoLibraryWriter.requestAccess() else {
            lastSavedMessage = PhotoLibraryWriter.WriteError.accessDenied.localizedDescription
            return
        }
        let saved = await PhotoLibraryWriter.write(videosAt: events.map(\.url))
        lastSavedMessage = saved == events.count
            ? String(format: String(localized: "Saved %d clips to Photos."), saved)
            : String(format: String(localized: "Saved %d of %d clips."), saved, events.count)
        if saved > 0 { await remindersAfterSave() }
    }
}
