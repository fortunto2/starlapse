import SkyKit
import StoreKitTest
import Testing
@testable import Starlapse

/// Where the free sky ends. And that a purchase actually flips the switch, against the
/// local StoreKit configuration rather than the App Store.
@Suite("Free and Pro", .serialized, .timeLimit(.minutes(1)))
struct ProAccessTests {

    @Test("The aim target is free on a night with no shower, Pro when a shower drives it")
    func aimFollowsTheEvent() {
        #expect(ProAccess.showsAim(isPro: false, eventActive: false))
        #expect(!ProAccess.showsAim(isPro: false, eventActive: true))
        #expect(ProAccess.showsAim(isPro: true, eventActive: true))
    }

    @Test("Five taps on Alzirr, and only on Alzirr")
    func dedication() {
        let alzirr = SkyDirector.Landmark(
            name: "Alzirr", kind: .star, magnitude: 3.35,
            direction: HorizontalCoordinates(azimuth: 100, altitude: 40), constellation: "Gemini"
        )
        #expect(StarTap(landmark: alzirr, point: .zero, count: 4).dedication == nil)
        #expect(StarTap(landmark: alzirr, point: .zero, count: 5).dedication != nil)
        let vega = SkyDirector.Landmark(
            name: "Vega", kind: .star, magnitude: 0.03,
            direction: HorizontalCoordinates(azimuth: 100, altitude: 40), constellation: "Lyra"
        )
        #expect(StarTap(landmark: vega, point: .zero, count: 9).dedication == nil)
    }

    @Test("Buying Pro in the local store unlocks it")
    @MainActor
    func purchaseUnlocks() async throws {
        let session = try SKTestSession(configurationFileNamed: "Starlapse")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        // The test host is the real app bundle: a purchase left here shows up as Pro the
        // next time the app is launched on this simulator.
        defer { session.clearTransactions() }

        let entitlements = Entitlements()
        // The local store takes a moment to come up when the whole suite runs at once.
        for _ in 0..<10 where entitlements.product == nil {
            await entitlements.refresh()
            if entitlements.product == nil { try await Task.sleep(for: .milliseconds(200)) }
        }
        #expect(entitlements.product != nil, "store never came up")
        #expect(!entitlements.isPro)

        await entitlements.purchase()
        #expect(entitlements.isPro, Comment(rawValue: entitlements.lastError ?? "no error reported"))
    }
}
