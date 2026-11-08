import Foundation
import Testing
@testable import Starlapse

/// The links the App Store's in-app events carry. Apple's reviewer taps them; one that
/// opens nothing is a rejection.
@Suite("Deep links")
struct DeepLinkTests {

    private func link(_ string: String) -> DeepLink? {
        URL(string: string).flatMap(DeepLink.init(url:))
    }

    @Test("The event links land where the event copy says")
    func eventLinks() {
        #expect(link("starlapse://moon") == .moon)
        #expect(link("starlapse://sky") == .sky)
        #expect(link("starlapse://meteors") == .sky)
    }

    @Test("Case and a trailing path do not matter")
    func tolerant() {
        #expect(link("STARLAPSE://Moon") == .moon)
        #expect(link("starlapse://moon/2026-12-24") == .moon)
    }

    @Test("Another scheme, an unknown host or no host is not a route")
    func refuses() {
        #expect(link("https://moon") == nil)
        #expect(link("starlapse://settings") == nil)
        #expect(link("starlapse:") == nil)
    }
}
