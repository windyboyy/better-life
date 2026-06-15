import Foundation
import StoreKit
import Observation

/// Manages the single non-consumable "unlimited" in-app purchase via StoreKit 2,
/// and owns the `isPro` entitlement that unlocks unlimited metronome time.
///
/// StoreKit 2 verifies and stores entitlements for us — there is no server to
/// run. `isPro` is recomputed from `Transaction.currentEntitlements`, which is
/// the source of truth across devices and reinstalls (for a signed-in Apple ID).
@MainActor
@Observable
final class StoreManager {
    /// App Store Connect product identifier for the unlimited unlock.
    ///
    /// The non-consumable Product ID created in App Store Connect.
    static let productID = "gcw.betterlife.unlimited"

    /// Whether the user has purchased unlimited access.
    private(set) var isPro = false
    /// The loaded product, used for localized price display. Nil until loaded.
    private(set) var product: Product?
    /// True while a purchase is in flight (so the UI can disable the buy button).
    private(set) var isPurchasing = false

    /// Background listener for transactions that arrive outside an explicit
    /// `purchase()` call (Ask to Buy approvals, purchases on another device, …).
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task { await refreshEntitlements() }
    }

    deinit { updatesTask?.cancel() }

    /// Localized price string, e.g. "¥12.00". Falls back to a dash before load.
    var priceText: String {
        product?.displayPrice ?? "—"
    }

    /// Loads product metadata so the paywall can show the real localized price.
    func loadProduct() async {
        product = try? await Product.products(for: [Self.productID]).first
    }

    /// Initiates purchase of the unlimited unlock. Returns true if the user is
    /// now Pro (purchase succeeded and verified).
    @discardableResult
    func purchase() async -> Bool {
        guard let product else { return false }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                await handle(verification)
                return isPro
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            return false
        }
    }

    /// Restores previous purchases. App Store review requires an explicit
    /// "Restore Purchases" entry point for non-consumables.
    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    /// Recomputes `isPro` from the current set of entitlements.
    func refreshEntitlements() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        isPro = owned
    }

    /// Validates a transaction result, grants entitlement, and finishes it.
    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        if transaction.productID == Self.productID, transaction.revocationDate == nil {
            isPro = true
        }
        await transaction.finish()
    }
}
