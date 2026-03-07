import SwiftUI

/// Bridges non-SwiftUI code (AppDelegate) to SwiftUI window management.
/// Stores a reference to `OpenWindowAction` so AppDelegate can open windows.
@MainActor
@Observable
final class WindowRouter {
    static let shared = WindowRouter()

    /// Stored reference to SwiftUI's open-window action.
    /// Set by the first view that appears (StartView or BrowserWindowRoot).
    var openWindowAction: OpenWindowAction?

    /// Opens a new browser window with the given request.
    func openBrowser(_ request: BrowserOpenRequest) {
        openWindowAction?(id: "browser", value: request)
    }

    private init() {}
}
