import Foundation

/// The line between free and Pro, in one place so it can be read and tested.
///
/// The constant sky is free: planets, bright stars, the Moon, the horizon, the compass.
/// The events are Pro: tonight's showers, their rates, and the aim target when a shower
/// is what it points at. On a night with no shower the target is the Milky Way, and
/// the Milky Way is nobody's to sell.
enum ProAccess {
    static func showsAim(isPro: Bool, eventActive: Bool) -> Bool {
        isPro || !eventActive
    }
}
