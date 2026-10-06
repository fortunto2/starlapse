import Foundation
import StoreKit
import UIKit

/// Ask for a rating at the one moment it is earned: a picture just landed in Photos.
///
/// Three ratings in the first two months, all five stars, from people who went looking
/// for a way to leave one. The App Store ranks on count as well as average, and the
/// system prompt is the only way most people ever rate anything. It is asked after the
/// second save — the first one is still a test shot — and once per version after that;
/// iOS itself caps it at three prompts a year, so the ceiling is Apple's, not ours.
@MainActor
enum RatingPrompt {

    private static let savesKey = "ratingPrompt.saves"
    private static let askedVersionKey = "ratingPrompt.askedVersion"

    /// Which save counts earn a prompt. Pure, so it is testable.
    static func shouldAsk(saves: Int, askedVersion: String?, currentVersion: String) -> Bool {
        guard saves >= 2 else { return false }
        if askedVersion == nil { return saves == 2 }
        return askedVersion != currentVersion && saves % 5 == 0
    }

    /// Call after a successful save.
    static func saved(defaults: UserDefaults = .standard) {
        let saves = defaults.integer(forKey: savesKey) + 1
        defaults.set(saves, forKey: savesKey)

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        guard shouldAsk(saves: saves, askedVersion: defaults.string(forKey: askedVersionKey), currentVersion: version),
              let scene = UIApplication.shared.connectedScenes
                  .compactMap({ $0 as? UIWindowScene })
                  .first(where: { $0.activationState == .foregroundActive })
        else { return }

        defaults.set(version, forKey: askedVersionKey)
        AppStore.requestReview(in: scene)
    }
}
