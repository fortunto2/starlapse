import SwiftUI

extension View {
    /// Offers a time-lapse an earlier run left unfinished. See `RecoveredClips`.
    func recoveredClipsAlert(_ model: CaptureViewModel) -> some View {
        alert(
            String(localized: "Recovered time-lapse"),
            isPresented: Binding(
                get: { !model.recoveredClips.isEmpty && !model.recoveryAnswered && model.state == .aiming },
                set: { if !$0 { model.recoveryAnswered = true } }
            )
        ) {
            Button(String(localized: "Save to Photos")) { Task { await model.saveRecoveredClips() } }
            Button(String(localized: "Discard"), role: .destructive) { model.discardRecoveredClips() }
            Button(String(localized: "Not now"), role: .cancel) { model.recoveryAnswered = true }
        } message: {
            Text("A time-lapse was interrupted before it finished. The frames recorded until then were kept.")
        }
    }
}
