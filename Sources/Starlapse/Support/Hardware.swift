import Foundation
import os

/// Calls into the camera that can fail at runtime, made survivable.
///
/// The App Store review that started this file: *"when I allow Starlapse to access my
/// camera, the app autocloses when I try to open it; if I don't allow it, the app opens
/// perfectly."* Nothing in the Swift code can produce that. An `NSException` raised by
/// `AVCaptureDevice` on a device whose format ranges differ from the ones this was written
/// against produces exactly that, and Swift has no `catch` for it.
///
/// So every setter that AVFoundation documents as raising goes through here. The value is
/// still clamped to what the hardware reports — this is the net under that, not instead of
/// it, because a crash three lenses deep is not a bug report anyone can act on.
enum Hardware {

    private static let logger = Logger(subsystem: "co.superduperai.starlapse", category: "hardware")

    /// Perform one camera call. Throws `CameraError.configurationFailed` instead of
    /// terminating the process when AVFoundation rejects the value.
    static func perform(_ what: String, _ body: () -> Void) throws {
        var raised: NSError?
        guard StarlapseCatchException(body, &raised) else {
            let detail = raised?.localizedDescription ?? "unknown"
            logger.error("\(what, privacy: .public) rejected: \(detail, privacy: .public)")
            throw CameraError.configurationFailed("\(what) — \(detail)")
        }
    }

    /// Perform one camera call whose failure is survivable: an automatic system that
    /// refuses to be turned off is worth a log line, not a dead app.
    @discardableResult
    static func attempt(_ what: String, _ body: () -> Void) -> Bool {
        do {
            try perform(what, body)
            return true
        } catch {
            return false
        }
    }
}
