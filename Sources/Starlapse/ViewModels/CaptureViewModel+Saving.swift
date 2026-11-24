import Foundation
import SuperDuperAnalytics

/// Writing results to the photo library, and saying what happened.
///
/// Split from the main view model to keep it inside the size limit. The library calls
/// themselves live in `PhotoLibraryWriter`, which is nonisolated for a reason — see the
/// note there about Swift 6 executor checks.
extension CaptureViewModel {

    /// Keep the result.
    func saveResult() async {
        guard state.isReviewing else { return }

        if let url = reviewVideoURL {
            await save(videoAt: url)
        } else if let rendered = await stackEngine?.exportResult() {
            await save(image: rendered)
        } else {
            lastSavedMessage = String(localized: "Nothing to save.")
        }
    }

    func save(image rendered: RenderedImage) async {
        guard await PhotoLibraryWriter.requestAccess() else {
            lastSavedMessage = PhotoLibraryWriter.WriteError.accessDenied.localizedDescription
            return
        }
        let credited = Watermark.applies(isPro: entitlements.isPro)
        do {
            try await PhotoLibraryWriter.write(credited ? Watermark.stamped(rendered) : rendered)
            lastSavedMessage = String(format: String(localized: "Saved %d frames to Photos."), progress.framesStacked)
            Analytics.track(
                "capture_saved",
                // A time-lapse that ends in a photo is one whose video was lost.
                props: ["kind": "photo", "watermark": credited ? "true" : "false", "mode": mode.analyticsName],
                metrics: ["frames": Double(progress.framesStacked)]
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
            // In Photos now: a kill before the review closes must not offer it back as recovered.
            ScratchStore.remove(url)
            lastSavedMessage = String(
                format: String(localized: "Saved %d-frame time-lapse to Photos."), progress.segmentsCompleted
            )
            Analytics.track(
                "capture_saved",
                props: ["kind": "video", "watermark": Watermark.applies(isPro: entitlements.isPro) ? "true" : "false"],
                metrics: [
                    "frames": Double(progress.segmentsCompleted),
                    "encoder_failures": Double(reviewEncoderFailures),
                ]
            )
            await remindersAfterSave(ratingPromptShown: RatingPrompt.saved())
        } catch {
            lastSavedMessage = String(format: String(localized: "Save failed: %@"), error.localizedDescription)
        }
    }

    // MARK: - Recovered time-lapses

    func loadRecoveredClips() async {
        recoveredClips = await RecoveredClips.pending()
    }

    /// Keep what an interrupted night left behind. Each clip is removed once it is in Photos.
    func saveRecoveredClips() async {
        // Answered: the alert must not come back while this runs, or on a refusal below.
        recoveryAnswered = true
        guard await PhotoLibraryWriter.requestAccess() else {
            lastSavedMessage = PhotoLibraryWriter.WriteError.accessDenied.localizedDescription
            return
        }
        var saved = 0
        for url in recoveredClips {
            do {
                try await PhotoLibraryWriter.write(videoAt: url)
                ScratchStore.remove(url)
                saved += 1
                Analytics.track("capture_saved", props: ["kind": "video", "recovered": "true"])
            } catch {
                lastSavedMessage = String(format: String(localized: "Save failed: %@"), error.localizedDescription)
            }
        }
        recoveredClips = await RecoveredClips.pending()
        if saved > 0 {
            lastSavedMessage = String(localized: "Saved the recovered time-lapse to Photos.")
        }
    }

    func discardRecoveredClips() {
        recoveryAnswered = true
        ScratchStore.remove(recoveredClips)
        recoveredClips = []
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
