import Foundation

// `starlapse://` links from the App Store's in-app events. Out of CaptureView.swift to keep
// it inside SwiftLint's length limits.
extension CaptureView {

    /// Before `prepare()` finishes the link waits: the restored settings would overwrite it.
    func receive(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        if prepared { open(link) } else { pendingLink = link }
    }

    func openPendingLink() {
        guard let link = pendingLink else { return }
        pendingLink = nil
        open(link)
    }

    /// Never interrupts a running session.
    private func open(_ link: DeepLink) {
        guard !model.state.isCapturing else { return }
        switch link {
        case .moon:
            model.enterMoonMode()
        case .sky:
            model.leaveMoonMode()
            model.mode = .still
        }
    }
}
