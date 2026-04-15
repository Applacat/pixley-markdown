import SwiftUI
import SwiftData

#if os(iOS)

// MARK: - iOS Root View

/// Single-window root for iOS that switches between StartView and BrowserView.
///
/// iPhone doesn't support multiple windows, so we can't use separate WindowGroups
/// for start and browser like macOS does. Instead, this view owns the navigation
/// state and switches between the two views internally.
///
/// On iPad with Stage Manager, additional windows can be opened via the system,
/// but the base flow must work single-window.
struct iOSRootView: View {

    @Environment(\.settings) private var settings
    @Environment(\.modelContext) private var modelContext

    /// The active browser request — nil means show StartView, non-nil means show BrowserView.
    @State private var activeRequest: BrowserOpenRequest?
    @State private var coordinator = AppCoordinator()
    @State private var isConfigured = false

    /// Show browser when coordinator has an active folder, StartView otherwise.
    private var isBrowsing: Bool {
        activeRequest != nil && isConfigured && coordinator.navigation.rootFolderURL != nil
    }

    var body: some View {
        Group {
            if isBrowsing {
                BrowserView()
                    .environment(\.coordinator, coordinator)
                    .focusedSceneValue(\.activeCoordinator, coordinator)
            } else {
                StartView(onOpenBrowser: { request in
                    openBrowser(request)
                })
            }
        }
        .onChange(of: coordinator.navigation.rootFolderURL) { _, newValue in
            // When coordinator closes folder, return to StartView
            if newValue == nil {
                activeRequest = nil
            }
        }
        .onAppear {
            CoordinatorRegistry.shared.register(coordinator)
        }
        .onDisappear {
            coordinator.flushScrollPosition()
            CoordinatorRegistry.shared.unregister(coordinator)
        }
    }

    // MARK: - Navigation

    private func openBrowser(_ request: BrowserOpenRequest) {
        // Configure coordinator on first use
        if !isConfigured {
            let context = ModelContext(modelContext.container)
            context.autosaveEnabled = true
            coordinator.metadata = SwiftDataMetadataRepository(modelContext: context)
            coordinator.chatSummaryRepository = SwiftDataChatSummaryRepository(modelContext: context)
            isConfigured = true
        }

        // Hydrate from request
        coordinator.openFolder(request.folderURL)

        if let file = request.fileURL {
            coordinator.selectFile(file)
        }
        if request.preferSidebarCollapsed {
            coordinator.requestSidebarCollapsed()
        }
        // Skip auto-opening chat on iOS — small screen, let user discover it.
        // macOS opens chat via BrowserWindowRoot which isn't used on iOS.
        if request.isFirstLaunchWelcome {
            coordinator.setFirstLaunchWelcome(true)
        }

        activeRequest = request
    }
}

#endif
