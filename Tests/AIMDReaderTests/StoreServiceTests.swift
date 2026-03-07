import XCTest
import Foundation

// MARK: - Mock Store Backend

/// Mirrors StoreBackend protocol for testing without StoreKit imports.
@MainActor
final class MockStoreBackend {
    var loadProductResult: String?
    var purchaseResult: MockPurchaseOutcome = .verified
    var purchaseShouldThrow: Error?
    var syncEntitlementResult: Bool = false
    var syncShouldThrow: Error?
    var localEntitlementResult: Bool = false

    enum MockPurchaseOutcome {
        case verified, unverified, cancelled, pending
    }
}

// MARK: - Testable StoreService Mirror

/// Mirrors StoreService logic without StoreKit dependency.
@MainActor
final class TestableStoreService {
    private(set) var isUnlocked: Bool
    private(set) var productDisplayPrice: String?
    private(set) var purchaseState: PurchaseState = .idle

    enum PurchaseState: Equatable {
        case idle, purchasing, restoring, failed(String)
    }

    let defaults: UserDefaults
    private let backend: MockStoreBackend
    private static let unlockedKey = "pixley.proUnlocked"
    static let productID = "com.pixley.app.pro"

    init(defaults: UserDefaults, backend: MockStoreBackend) {
        self.defaults = defaults
        self.backend = backend
        self.isUnlocked = defaults.bool(forKey: Self.unlockedKey)
    }

    func requiresPro(_ elementType: String) -> Bool {
        elementType != "Checkbox"
    }

    func verifyOnLaunch() async {
        productDisplayPrice = backend.loadProductResult
        await checkExistingEntitlement()
    }

    func purchase() async {
        guard productDisplayPrice != nil else { return }
        purchaseState = .purchasing

        if let error = backend.purchaseShouldThrow {
            purchaseState = .failed(error.localizedDescription)
            return
        }

        switch backend.purchaseResult {
        case .verified:
            unlock()
        case .unverified:
            purchaseState = .failed("Purchase could not be verified.")
        case .cancelled, .pending:
            purchaseState = .idle
        }
    }

    func restore() async {
        purchaseState = .restoring

        if let error = backend.syncShouldThrow {
            purchaseState = .failed(error.localizedDescription)
            return
        }

        if backend.syncEntitlementResult {
            unlock()
        } else {
            purchaseState = .idle
        }
    }

    func handleRefund() {
        lock()
    }

    private func checkExistingEntitlement() async {
        if backend.localEntitlementResult {
            unlock()
        } else {
            lock()
        }
    }

    private func unlock() {
        isUnlocked = true
        defaults.set(true, forKey: Self.unlockedKey)
        purchaseState = .idle
    }

    private func lock() {
        isUnlocked = false
        defaults.set(false, forKey: Self.unlockedKey)
    }
}

// MARK: - Tests

final class StoreServiceTests: XCTestCase {

    // MARK: - Initial State

    @MainActor
    func testInitialStateIsLocked() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let service = TestableStoreService(defaults: defaults, backend: MockStoreBackend())
        XCTAssertFalse(service.isUnlocked)
        XCTAssertEqual(service.purchaseState, .idle)
    }

    @MainActor
    func testInitialStateReadsFromDefaults() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "pixley.proUnlocked")
        let service = TestableStoreService(defaults: defaults, backend: MockStoreBackend())
        XCTAssertTrue(service.isUnlocked)
    }

    // MARK: - requiresPro

    @MainActor
    func testRequiresProCheckboxIsFree() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let service = TestableStoreService(defaults: defaults, backend: MockStoreBackend())
        XCTAssertFalse(service.requiresPro("Checkbox"))
    }

    @MainActor
    func testRequiresProOtherTypesAreGated() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let service = TestableStoreService(defaults: defaults, backend: MockStoreBackend())
        XCTAssertTrue(service.requiresPro("Choice"))
        XCTAssertTrue(service.requiresPro("Fill-In"))
        XCTAssertTrue(service.requiresPro("Status"))
        XCTAssertTrue(service.requiresPro("Review"))
        XCTAssertTrue(service.requiresPro("Feedback"))
        XCTAssertTrue(service.requiresPro("Suggestion"))
        XCTAssertTrue(service.requiresPro("Confidence"))
    }

    // MARK: - Purchase Flow

    @MainActor
    func testSuccessfulPurchaseUnlocks() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let backend = MockStoreBackend()
        backend.loadProductResult = "$9.99"
        backend.purchaseResult = .verified
        let service = TestableStoreService(defaults: defaults, backend: backend)
        await service.verifyOnLaunch()

        await service.purchase()

        XCTAssertTrue(service.isUnlocked)
        XCTAssertEqual(service.purchaseState, .idle)
        XCTAssertTrue(defaults.bool(forKey: "pixley.proUnlocked"))
    }

    @MainActor
    func testCancelledPurchaseStaysLocked() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let backend = MockStoreBackend()
        backend.loadProductResult = "$9.99"
        backend.purchaseResult = .cancelled
        let service = TestableStoreService(defaults: defaults, backend: backend)
        await service.verifyOnLaunch()

        await service.purchase()

        XCTAssertFalse(service.isUnlocked)
        XCTAssertEqual(service.purchaseState, .idle)
    }

    @MainActor
    func testUnverifiedPurchaseFails() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let backend = MockStoreBackend()
        backend.loadProductResult = "$9.99"
        backend.purchaseResult = .unverified
        let service = TestableStoreService(defaults: defaults, backend: backend)
        await service.verifyOnLaunch()

        await service.purchase()

        XCTAssertFalse(service.isUnlocked)
        XCTAssertEqual(service.purchaseState, .failed("Purchase could not be verified."))
    }

    @MainActor
    func testPurchaseWithoutProductDoesNothing() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let backend = MockStoreBackend()
        backend.loadProductResult = nil
        let service = TestableStoreService(defaults: defaults, backend: backend)
        await service.verifyOnLaunch()

        await service.purchase()

        XCTAssertFalse(service.isUnlocked)
        XCTAssertEqual(service.purchaseState, .idle)
    }

    @MainActor
    func testPurchaseThrowingSetsFailedState() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let backend = MockStoreBackend()
        backend.loadProductResult = "$9.99"
        backend.purchaseShouldThrow = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        let service = TestableStoreService(defaults: defaults, backend: backend)
        await service.verifyOnLaunch()

        await service.purchase()

        XCTAssertFalse(service.isUnlocked)
        XCTAssertEqual(service.purchaseState, .failed("Network error"))
    }

    // MARK: - Restore Flow

    @MainActor
    func testSuccessfulRestoreUnlocks() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let backend = MockStoreBackend()
        backend.syncEntitlementResult = true
        let service = TestableStoreService(defaults: defaults, backend: backend)

        await service.restore()

        XCTAssertTrue(service.isUnlocked)
        XCTAssertEqual(service.purchaseState, .idle)
    }

    @MainActor
    func testRestoreWithNoEntitlementStaysLocked() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let backend = MockStoreBackend()
        backend.syncEntitlementResult = false
        let service = TestableStoreService(defaults: defaults, backend: backend)

        await service.restore()

        XCTAssertFalse(service.isUnlocked)
        XCTAssertEqual(service.purchaseState, .idle)
    }

    @MainActor
    func testRestoreThrowingSetsFailedState() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let backend = MockStoreBackend()
        backend.syncShouldThrow = NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Sync failed"])
        let service = TestableStoreService(defaults: defaults, backend: backend)

        await service.restore()

        XCTAssertFalse(service.isUnlocked)
        XCTAssertEqual(service.purchaseState, .failed("Sync failed"))
    }

    // MARK: - Refund

    @MainActor
    func testRefundLocksService() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let backend = MockStoreBackend()
        backend.loadProductResult = "$9.99"
        backend.purchaseResult = .verified
        let service = TestableStoreService(defaults: defaults, backend: backend)
        await service.verifyOnLaunch()
        await service.purchase()
        XCTAssertTrue(service.isUnlocked)

        service.handleRefund()

        XCTAssertFalse(service.isUnlocked)
        XCTAssertFalse(defaults.bool(forKey: "pixley.proUnlocked"))
    }

    // MARK: - Verify on Launch

    @MainActor
    func testVerifyOnLaunchWithEntitlementUnlocks() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let backend = MockStoreBackend()
        backend.loadProductResult = "$9.99"
        backend.localEntitlementResult = true
        let service = TestableStoreService(defaults: defaults, backend: backend)

        await service.verifyOnLaunch()

        XCTAssertTrue(service.isUnlocked)
        XCTAssertEqual(service.productDisplayPrice, "$9.99")
    }

    @MainActor
    func testVerifyOnLaunchRevokesStaleCache() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "pixley.proUnlocked")
        let backend = MockStoreBackend()
        backend.loadProductResult = "$9.99"
        backend.localEntitlementResult = false
        let service = TestableStoreService(defaults: defaults, backend: backend)
        XCTAssertTrue(service.isUnlocked)

        await service.verifyOnLaunch()

        XCTAssertFalse(service.isUnlocked)
    }

    // MARK: - Product ID

    @MainActor
    func testProductIDIsCorrect() {
        XCTAssertEqual(TestableStoreService.productID, "com.pixley.app.pro")
    }
}
