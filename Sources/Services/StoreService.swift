import Foundation
import os
import StoreKit

// MARK: - Backend protocol (testability seam)

/// Abstracts StoreKit I/O so StoreService logic can be tested with a mock.
@MainActor
protocol StoreBackend: Sendable {
    func loadProduct(id: String) async -> StoreProductInfo?
    func purchase(id: String) async throws -> PurchaseOutcome
    func syncAndCheckEntitlement(productID: String) async throws -> Bool
    func checkLocalEntitlement(productID: String) async -> Bool
}

/// Displayable product metadata, decoupled from StoreKit's `Product` type.
struct StoreProductInfo: Sendable {
    let displayPrice: String
}

/// Outcome of a purchase attempt, decoupled from StoreKit's `PurchaseResult`.
enum PurchaseOutcome: Sendable {
    case verified
    case unverified
    case cancelled
    case pending
}

// MARK: - Live backend (real StoreKit)

/// Production implementation that talks to the App Store.
@MainActor
final class LiveStoreBackend: StoreBackend {

    func loadProduct(id: String) async -> StoreProductInfo? {
        do {
            let products = try await Product.products(for: [id])
            guard let product = products.first else { return nil }
            return StoreProductInfo(displayPrice: product.displayPrice)
        } catch {
            return nil
        }
    }

    func purchase(id: String) async throws -> PurchaseOutcome {
        let products = try await Product.products(for: [id])
        guard let product = products.first else {
            throw StoreService.StoreError.productNotFound
        }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let tx):
                await tx.finish()
                return .verified
            case .unverified(let tx, _):
                await tx.finish()
                return .unverified
            }
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .pending
        }
    }

    func syncAndCheckEntitlement(productID: String) async throws -> Bool {
        try await AppStore.sync()
        return await checkLocalEntitlement(productID: productID)
    }

    func checkLocalEntitlement(productID: String) async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result, tx.productID == productID {
                return true
            }
        }
        return false
    }
}

// MARK: - StoreService

/// Manages the one-time "Pixley Pro" in-app purchase.
///
/// Free tier:  Markdown reading, checkboxes, basic AI chat.
/// Pro tier:   All interactive elements, AI field interaction.
///
/// Purchase state is cached in UserDefaults and verified against StoreKit
/// on each launch via `verifyOnLaunch()`.
/* SACRED CODE - DO NOT MODIFY WITHOUT EXPLICIT PERMISSION
 *
 * Premium Tier Gate (Monetization Model)
 *
 * WHY SACRED: This service defines the free/pro tier split. Free: checkboxes only.
 * Pro: all interactive Pixley Markdown elements + AI field interaction.
 * Every paywall check in the UI reads `isUnlocked` from this service.
 *
 * DANGERS:
 * - Changing `isUnlocked` logic (bypasses purchase requirement)
 * - Removing UserDefaults cache (breaks instant launch entitlement)
 * - Modifying productID (orphans existing purchases)
 * - Adding `isUnlocked = true` in debug builds (ships with gate disabled)
 *
 * DEPENDENT CODE:
 * - MarkdownNSTextView.mouseDown: checks isUnlocked before non-checkbox interactions
 * - EditInteractiveElementsTool: checks isUnlocked before AI field edits
 * - SettingsView Pro tab: shows purchase/status based on isUnlocked
 * - AIMDReaderApp menu: "Upgrade to Pro" visibility
 *
 * REVISION HISTORY:
 * - 2026-03-07: Initial implementation following DockPops StoreService pattern
 */
@MainActor
@Observable
final class StoreService {

    static let shared = StoreService()

    static let productID = "com.pixley.app.pro"
    private static let unlockedKey = "pixley.proUnlocked"

    /// True once the user has completed the one-time purchase.
    private(set) var isUnlocked: Bool

    /// Product display info, loaded once at startup.
    private(set) var productInfo: StoreProductInfo?

    /// Non-nil while a purchase or restore is in flight.
    private(set) var purchaseState: PurchaseState = .idle

    /// Returns true if the given element type requires Pro.
    /// Checkboxes are always free. All other interactive elements are Pro.
    func requiresPro(_ elementType: String) -> Bool {
        elementType != "Checkbox"
    }

    enum PurchaseState: Sendable, Equatable {
        case idle, purchasing, restoring, failed(String)

        static func == (lhs: PurchaseState, rhs: PurchaseState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.purchasing, .purchasing), (.restoring, .restoring): true
            case (.failed(let a), .failed(let b)): a == b
            default: false
            }
        }
    }

    private let defaults: UserDefaults
    private let backend: StoreBackend
    @ObservationIgnored nonisolated(unsafe) private var transactionListener: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, backend: StoreBackend? = nil) {
        self.defaults = defaults
        self.isUnlocked = defaults.bool(forKey: Self.unlockedKey)
        self.backend = backend ?? LiveStoreBackend()
        startTransactionListener()
    }

    deinit {
        transactionListener?.cancel()
    }

    /// Listens for Transaction.updates to handle ask-to-buy approvals,
    /// family sharing grants, and other out-of-band transaction events.
    private func startTransactionListener() {
        transactionListener = Task { @MainActor [weak self] in
            for await result in Transaction.updates {
                guard let self else { break }
                switch result {
                case .verified(let tx):
                    if tx.productID == Self.productID {
                        if tx.revocationDate != nil {
                            self.lock()
                        } else {
                            self.unlock()
                        }
                    }
                    await tx.finish()
                case .unverified(let tx, let error):
                    Logger(subsystem: "com.pixley.app", category: "StoreService")
                        .warning("Unverified transaction \(tx.productID): \(error)")
                    await tx.finish()
                }
            }
        }
    }

    // MARK: - Startup

    /// Loads the product from App Store Connect and re-verifies unlock state.
    /// Call once from app launch.
    func verifyOnLaunch() async {
        productInfo = await backend.loadProduct(id: Self.productID)
        await checkExistingEntitlement()
    }

    // MARK: - Purchase

    func purchase() async {
        guard productInfo != nil else { return }
        purchaseState = .purchasing
        do {
            let outcome = try await backend.purchase(id: Self.productID)
            switch outcome {
            case .verified:
                unlock()
            case .unverified:
                purchaseState = .failed(StoreError.unverified.localizedDescription)
            case .cancelled, .pending:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Restore

    func restore() async {
        purchaseState = .restoring
        do {
            let entitled = try await backend.syncAndCheckEntitlement(productID: Self.productID)
            if entitled {
                unlock()
            } else {
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Private

    private func checkExistingEntitlement() async {
        let entitled = await backend.checkLocalEntitlement(productID: Self.productID)
        if entitled {
            unlock()
        } else {
            lock()
        }
    }

    private func lock() {
        isUnlocked = false
        defaults.set(false, forKey: Self.unlockedKey)
    }

    private func unlock() {
        isUnlocked = true
        defaults.set(true, forKey: Self.unlockedKey)
        purchaseState = .idle
    }

    enum StoreError: LocalizedError {
        case unverified
        case productNotFound

        var errorDescription: String? {
            switch self {
            case .unverified:
                return "Purchase could not be verified. Please contact support."
            case .productNotFound:
                return "Product not found. Please try again later."
            }
        }
    }
}
/* END SACRED CODE */
