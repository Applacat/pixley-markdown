import Foundation

/// Tracks all active per-window coordinators for bulk operations
/// (e.g., flushing scroll positions on app termination).
@MainActor
final class CoordinatorRegistry {
    static let shared = CoordinatorRegistry()

    private var entries: [ObjectIdentifier: WeakCoordinator] = [:]

    func register(_ coordinator: AppCoordinator) {
        entries[ObjectIdentifier(coordinator)] = WeakCoordinator(coordinator)
    }

    func unregister(_ coordinator: AppCoordinator) {
        entries.removeValue(forKey: ObjectIdentifier(coordinator))
    }

    /// Flushes scroll positions for all live coordinators.
    func flushAll() {
        for entry in entries.values {
            entry.coordinator?.flushScrollPosition()
        }
    }

    private init() {}
}

private final class WeakCoordinator {
    weak var coordinator: AppCoordinator?
    init(_ coordinator: AppCoordinator) { self.coordinator = coordinator }
}
