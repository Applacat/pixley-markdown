import SwiftUI
import SwiftData

/// Per-window wrapper that creates an independent `AppCoordinator`
/// and hydrates it from the `BrowserOpenRequest` payload.
///
/// Each window gets its own `ModelContext` (from the shared `ModelContainer`)
/// to avoid SwiftData transaction conflicts between windows.
struct BrowserWindowRoot: View {

    let request: BrowserOpenRequest?

    @State private var coordinator = AppCoordinator()
    @State private var isConfigured = false
    @Environment(\.modelContext) private var sharedModelContext
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if request != nil, isConfigured {
                BrowserView()
            } else if request == nil {
                // Window restoration with .restorationBehavior(.disabled)
                // should never hit this, but handle gracefully.
                Color.clear.onAppear {
                    openWindow(id: "start")
                }
            } else {
                // Brief placeholder while configure() runs next run-loop
                Color.clear
            }
        }
        .environment(\.coordinator, coordinator)
        .focusedSceneValue(\.activeCoordinator, coordinator)
        .onAppear {
            WindowRouter.shared.openWindowAction = openWindow
            CoordinatorRegistry.shared.register(coordinator)

            // Defer configuration to next run-loop tick to avoid
            // state mutations during the CA commit / layout pass.
            if !isConfigured {
                Task { @MainActor in
                    configure()
                }
            }
        }
        .onDisappear {
            coordinator.flushScrollPosition()
            CoordinatorRegistry.shared.unregister(coordinator)
        }
    }

    private func configure() {
        guard let request, !isConfigured else { return }

        // Each window gets its own ModelContext to avoid transaction conflicts
        let context = ModelContext(sharedModelContext.container)
        context.autosaveEnabled = true
        coordinator.metadata = SwiftDataMetadataRepository(modelContext: context)
        coordinator.chatSummaryRepository = SwiftDataChatSummaryRepository(modelContext: context)

        // Hydrate from request
        coordinator.openFolder(request.folderURL)

        if let file = request.fileURL {
            coordinator.selectFile(file)
        }
        if request.preferSidebarCollapsed {
            coordinator.requestSidebarCollapsed()
        }
        if let question = request.initialChatQuestion {
            coordinator.ui.initialChatQuestion = question
            coordinator.ui.isAIChatVisible = true
        }
        if request.isFirstLaunchWelcome {
            coordinator.setFirstLaunchWelcome(true)
        }

        isConfigured = true
    }
}
