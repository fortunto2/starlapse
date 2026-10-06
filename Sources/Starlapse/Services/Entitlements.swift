import Foundation
import StoreKit

/// What this phone has paid for. One product, bought once.
///
/// Starlapse Pro is the sky *events*: tonight's meteor showers, where to aim for them,
/// peak nights. The constant sky — planets, bright stars, the Moon — and every camera
/// feature stay free. Events are the part that needs keeping up to date, which is what
/// is being paid for; and a non-consumable is the only honest shape for "forever".
///
/// StoreKit 2 only. The one network call this app makes is Apple's, from here.
@MainActor
@Observable
final class Entitlements {

    static let proID = "co.superduperai.starlapse.pro"

    private(set) var isPro = false
    private(set) var product: Product?
    private(set) var isPurchasing = false
    private(set) var lastError: String?
    private var updates: Task<Void, Never>?

    init() {
        #if DEBUG
        // Screenshots and the simulator: no store, so the entitlement is stood in for.
        if ProcessInfo.processInfo.environment["UITEST_PRO"] == "1" { isPro = true }
        #endif
    }

    /// Call once at launch. Listens for purchases made elsewhere (another device, a
    /// refund) and reads what is already owned.
    func start() {
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
        Task { await refresh() }
    }

    func refresh() async {
        for await result in Transaction.currentEntitlements {
            await handle(result)
        }
        if product == nil {
            product = try? await Product.products(for: [Self.proID]).first
        }
    }

    func purchase() async {
        isPurchasing = true
        defer { isPurchasing = false }
        lastError = nil
        if product == nil { await refresh() }
        guard let product else {
            lastError = "The App Store is not reachable right now."
            return
        }
        do {
            switch try await product.purchase() {
            case .success(let result):
                await handle(result)
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Bought on another phone, or reinstalled: ask the store again.
    func restore() async {
        lastError = nil
        do {
            try await AppStore.sync()
        } catch {
            lastError = error.localizedDescription
        }
        await refresh()
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result,
              transaction.productID == Self.proID else { return }
        isPro = transaction.revocationDate == nil
        await transaction.finish()
    }
}
