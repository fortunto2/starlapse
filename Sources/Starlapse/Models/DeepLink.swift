import Foundation

/// Where a `starlapse://` link opens the app.
///
/// The App Store's in-app events need a link that lands somewhere real: a full-Moon event
/// opens Moon mode, a meteor shower opens the night exposure that keeps its trails. Anything
/// else is not a route, and the app just opens where it was.
enum DeepLink: Equatable, Sendable {
    case moon
    case sky

    init?(url: URL) {
        guard url.scheme?.lowercased() == "starlapse" else { return nil }
        switch (url.host() ?? "").lowercased() {
        case "moon": self = .moon
        case "sky", "meteors": self = .sky
        default: return nil
        }
    }
}
