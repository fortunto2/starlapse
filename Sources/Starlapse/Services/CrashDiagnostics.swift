import Foundation
import MetricKit
import os

/// Crash reports that carry the reason, kept on the phone until its owner sends one.
///
/// The crash reports Xcode's Organizer hands over name the frame that raised —
/// `-[AVCaptureSession startRunning]` — and nothing else. The `NSException` message, the
/// one line that says *what* the camera refused, is not in them. Three fixes in a row were
/// inferred from the frame alone, on a phone nobody here owns.
///
/// MetricKit delivers the same crash to the app on its next launch, with
/// `exceptionReason.composedMessage` filled in. Nothing leaves the device on its own: the
/// payload is written to Application Support, and the controls panel offers to share it.
/// No photo, no location, no identifier — the camera's error and the code path.
final class CrashDiagnostics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {

    static let shared = CrashDiagnostics()

    private let logger = Logger(subsystem: "co.superduperai.starlapse", category: "diagnostics")

    /// Where reports wait to be shared.
    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "Diagnostics", directoryHint: .isDirectory)
    }

    /// Reports on disk, newest first.
    static var reports: [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        return files.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Call once at launch. MetricKit delivers the previous run's crash shortly after.
    func start() {
        MXMetricManager.shared.add(self)
    }

    /// Called by MetricKit on a queue of its own — never on the main actor.
    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let crashes = payload.crashDiagnostics ?? []
            guard !crashes.isEmpty else { continue }

            for crash in crashes {
                let reason = crash.exceptionReason?.composedMessage ?? "no exception reason"
                logger.error("""
                    Previous run crashed: \(crash.applicationVersion, privacy: .public) \
                    signal \(crash.signal?.intValue ?? 0) — \(reason, privacy: .public)
                    """)
            }
            save(payload)
        }
    }

    private func save(_ payload: MXDiagnosticPayload) {
        let directory = Self.directory
        let stamp = ISO8601DateFormatter().string(from: payload.timeStampEnd)
            .replacingOccurrences(of: ":", with: "-")
        let url = directory.appending(path: "crash-\(stamp).json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try payload.jsonRepresentation().write(to: url, options: .atomic)
        } catch {
            logger.error("Could not keep crash report: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// After the owner has shared them, there is no reason to keep them.
    static func clear() {
        for url in reports { try? FileManager.default.removeItem(at: url) }
    }
}
