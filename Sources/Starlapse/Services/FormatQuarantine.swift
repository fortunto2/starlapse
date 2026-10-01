import Foundation

/// Remembers sensor formats that killed the process, so they kill it once rather than on
/// every launch.
///
/// AVFoundation refuses a configuration by raising `NSException`, and the ones raised
/// outside `Hardware.perform` cannot be caught at all. Three builds in a row shipped a fix
/// for the refusal of the day, and each time the next iPhone found a new one: a customer
/// opened the app, it died, they opened it again, it died the same way. This is the part
/// that does not depend on knowing what the next refusal will be.
///
/// Before a format is tried, its name is written down. Once the session is running on it,
/// the note is erased. A note that survives to the next launch means the process died in
/// between — and the format goes on a list `FormatChoice` will not offer again.
final class FormatQuarantine: @unchecked Sendable {

    private let defaults: UserDefaults
    private static let pendingKey = "formatQuarantine.pending"
    private static let blockedKey = "formatQuarantine.blocked"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Formats on this phone that must not be offered, as `scope|key` pairs.
    var blocked: Set<String> {
        Set(defaults.stringArray(forKey: Self.blockedKey) ?? [])
    }

    /// The format keys blocked for one camera.
    func blocked(in scope: String) -> Set<String> {
        let prefix = scope + "|"
        return Set(blocked.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) })
    }

    /// About to hand this format to the camera.
    func begin(_ key: String, in scope: String) {
        defaults.set(scope + "|" + key, forKey: Self.pendingKey)
    }

    /// The camera took it, or refused it in a way that was caught. Either way the process
    /// survived, which is all this type is about.
    func survived() {
        defaults.removeObject(forKey: Self.pendingKey)
    }

    /// The camera refused the pending format in a way that was caught, but refused it at
    /// a point where trying it again costs a failed start every launch. Block it now.
    func condemnPending() {
        guard let pending = defaults.string(forKey: Self.pendingKey) else { return }
        block(pending)
        survived()
    }

    /// Call once, at launch, before any camera work. Returns the format that was in hand
    /// when the previous run died, if one was.
    @discardableResult
    func recoverFromCrash() -> String? {
        guard let pending = defaults.string(forKey: Self.pendingKey) else { return nil }
        block(pending)
        survived()
        return pending
    }

    private func block(_ entry: String) {
        var list = defaults.stringArray(forKey: Self.blockedKey) ?? []
        if !list.contains(entry) { list.append(entry) }
        defaults.set(list, forKey: Self.blockedKey)
    }
}
