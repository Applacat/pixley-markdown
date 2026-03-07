import Foundation

/// Data passed to a new browser window via `WindowGroup(for:)`.
/// Each field maps to an `AppCoordinator` setup action.
struct BrowserOpenRequest: Codable, Hashable {
    let folderURL: URL
    var fileURL: URL? = nil
    var preferSidebarCollapsed: Bool = false
    var initialChatQuestion: String? = nil
    var isFirstLaunchWelcome: Bool = false
}
