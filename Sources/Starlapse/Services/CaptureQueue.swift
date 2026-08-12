import Foundation

/// The one serial queue the whole capture pipeline runs on.
///
/// Every stage — AVFoundation configuration, star detection, Metal accumulation, video
/// encoding — is confined to this queue. That confinement used to be a promise written in
/// doc comments, and it was broken twice: first by the main actor pulling a render out of
/// the accumulator, then by `cancel()` calling straight into `finish()` from a button tap
/// while frames were still arriving. Both crashed.
///
/// Making the queue an object that gets passed around means "run this on the pipeline" is
/// something you can write, instead of something you have to remember.
final class CaptureQueue: @unchecked Sendable {
    let dispatch: DispatchQueue

    init(label: String = "co.superduperai.starlapse.capture") {
        dispatch = DispatchQueue(label: label)
    }

    /// Schedule work on the pipeline.
    func run(_ work: @escaping @Sendable () -> Void) {
        dispatch.async(execute: work)
    }

    /// Schedule work and wait for it, bridging an async caller onto the pipeline.
    func perform<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            dispatch.async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func perform(_ work: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { continuation in
            dispatch.async {
                work()
                continuation.resume()
            }
        }
    }

    /// Non-throwing variant that carries a value back off the pipeline.
    func perform<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            dispatch.async {
                continuation.resume(returning: work())
            }
        }
    }
}
