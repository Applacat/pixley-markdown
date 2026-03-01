import SwiftUI
import UniformTypeIdentifiers

// MARK: - Start View

/// Launcher window with branding, folder shortcuts, and recent items panel.
/// Compact (shortcuts only) when no recents exist; expands side-by-side when recents are available.
/// Shows when no folder is open. Click app icon to open Welcome tour (easter egg).
struct StartView: View {

    @Environment(\.coordinator) private var coordinator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var isDropTargeted = false
    @State private var hasPerformedLaunch = false
    @State private var isReady = false
    @State private var showWelcomeError = false
    @State private var recents: [RecentItem] = []
    @State private var hasPruned = false

    /// Closure to perform launch logic (first launch, session restore)
    var performLaunchIfNeeded: (() -> Void)? = nil

    private var hasRecents: Bool { !recents.isEmpty }

    var body: some View {
        Group {
            if isReady {
                launcherContent
            } else {
                // Show nothing while determining launch state
                Color.clear
            }
        }
        // Dynamic width: compact (480) when no recents, expanded (720) with recents panel
        .frame(width: hasRecents ? 720 : 480, height: 520)
        .animation(.easeInOut(duration: 0.25), value: hasRecents)
        .onAppear {
            // Run launch logic first (only once)
            if !hasPerformedLaunch {
                hasPerformedLaunch = true
                performLaunchIfNeeded?()
            }

            // If we have a root folder (from first launch or session restore),
            // redirect to browser immediately
            if coordinator.navigation.rootFolderURL != nil {
                activateOrOpenBrowser()
                dismissWindow(id: "start")
            } else {
                // Prune stale items once, then load recents for display
                if !hasPruned {
                    RecentFoldersManager.shared.pruneStaleItems()
                    hasPruned = true
                }
                recents = RecentFoldersManager.shared.getAllRecents()
                isReady = true
            }
        }
        .onChange(of: coordinator.ui.shouldOpenBrowser) { _, shouldOpen in
            // React to menu commands (Help, About) that request browser window
            if shouldOpen {
                coordinator.consumeOpenBrowser()  // Consume the flag
                activateOrOpenBrowser()
                dismissWindow(id: "start")
            }
        }
    }

    // MARK: - Launcher Content

    private var launcherContent: some View {
        VStack(spacing: 0) {
            Spacer()

            // Centered content
            VStack(spacing: 24) {
                // App mascot + title (click for welcome tour)
                mascotHeader

                // Content area: shortcuts + optional recents panel
                if hasRecents {
                    HStack(alignment: .top, spacing: 0) {
                        shortcutsColumn

                        Divider()
                            .padding(.vertical, 4)

                        recentsColumn
                    }
                } else {
                    shortcutsColumn
                }
            }

            Spacer()

            // Footer hint
            Text("or drop a folder or .md file anywhere")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDropTargeted {
                dropOverlay
            }
        }
        .alert("Tutorial Unavailable", isPresented: $showWelcomeError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("The tutorial files could not be found. Please reinstall the app.")
        }
    }

    // MARK: - Mascot Header

    private var mascotHeader: some View {
        Button(action: openWelcomeFolder) {
            VStack(spacing: 16) {
                Image("AIMD")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                    .accessibilityLabel("Pixley Markdown Reader app icon")

                VStack(spacing: 4) {
                    Text("Pixley Markdown Reader")
                        .font(.title2.bold())

                    Text("Read what AI writes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(MascotButtonStyle())
    }

    // MARK: - Shortcuts Column

    private var shortcutsColumn: some View {
        VStack(spacing: 0) {
            FolderShortcutButton(
                title: "Read Sample Files",
                icon: "book.circle",
                action: openWelcomeFolderWithPrompt
            )

            Divider()
                .padding(.vertical, 8)

            FolderShortcutButton(
                title: "Desktop",
                icon: "menubar.dock.rectangle",
                action: { openStandardFolder(.desktopDirectory) }
            )
            FolderShortcutButton(
                title: "Documents",
                icon: "doc.text",
                action: { openStandardFolder(.documentDirectory) }
            )
            FolderShortcutButton(
                title: "Downloads",
                icon: "arrow.down.circle",
                action: { openStandardFolder(.downloadsDirectory) }
            )

            Divider()
                .padding(.vertical, 8)

            FolderShortcutButton(
                title: "Choose Folder...",
                icon: "folder.badge.plus",
                action: chooseFolder
            )
        }
        .frame(width: 220)
    }

    // MARK: - Recents Column

    private var recentsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(recents) { item in
                        RecentItemButton(item: item) {
                            openRecentItem(item)
                        }
                        .contextMenu {
                            Button("Remove from Recents") {
                                removeRecentItem(item)
                            }
                        }
                    }
                }
            }

            Divider()
                .padding(.vertical, 4)

            Button("Clear Recents") {
                withAnimation {
                    RecentFoldersManager.shared.clearAll()
                    recents = []
                }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .frame(width: 240)
    }

    // MARK: - Drop Overlay

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 4]))
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .padding(4)
            .allowsHitTesting(false)
    }

    // MARK: - Recent Item Actions

    private func openRecentItem(_ item: RecentItem) {
        if item.isFolder {
            // Folder: resolve bookmark and open with sidebar visible
            let folders = RecentFoldersManager.shared.getRecentFolders()
            guard let folder = folders.first(where: { $0.path == item.path }),
                  let resolvedURL = RecentFoldersManager.shared.resolveBookmark(folder) else {
                // Bookmark can't resolve — remove and refresh
                removeRecentItem(item)
                return
            }
            RecentFoldersManager.shared.addFolder(resolvedURL)
            coordinator.openFolder(resolvedURL)
            activateOrOpenBrowser()
            dismissWindow(id: "start")
        } else {
            // File: resolve parent folder bookmark, open folder + select file collapsed
            guard let parentPath = item.parentPath else {
                removeRecentItem(item)
                return
            }
            let folders = RecentFoldersManager.shared.getRecentFolders()
            guard let parentFolder = folders.first(where: { $0.path == parentPath }),
                  let resolvedURL = RecentFoldersManager.shared.resolveBookmark(parentFolder) else {
                // Parent folder inaccessible — remove file from recents
                removeRecentItem(item)
                return
            }
            let fileURL = URL(fileURLWithPath: item.path)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                removeRecentItem(item)
                return
            }
            coordinator.openFolder(resolvedURL)
            coordinator.selectFile(fileURL)
            coordinator.requestSidebarCollapsed()
            activateOrOpenBrowser()
            dismissWindow(id: "start")
        }
    }

    private func removeRecentItem(_ item: RecentItem) {
        if item.isFolder {
            RecentFoldersManager.shared.removeFolderByPath(item.path)
        } else {
            RecentFoldersManager.shared.removeRecentFile(item)
        }
        withAnimation {
            recents = RecentFoldersManager.shared.getAllRecents()
        }
    }

    // MARK: - Folder Actions

    private func openStandardFolder(_ directory: FileManager.SearchPathDirectory) {
        SecurityScopedBookmarkManager.shared.getOrRequestAccess(
            to: directory,
            onAccessGranted: { url in
                self.openFolder(url)
            },
            onPermissionNeeded: { url in
                self.showFolderPanel(for: directory, at: url)
            }
        )
    }
    
    #if os(macOS)
    private func showFolderPanel(for directory: FileManager.SearchPathDirectory, at url: URL) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = url
        panel.prompt = "Open"

        let name: String
        switch directory {
        case .desktopDirectory: name = "Desktop"
        case .documentDirectory: name = "Documents"
        case .downloadsDirectory: name = "Downloads"
        default: name = "folder"
        }
        panel.message = "Grant access to \(name)"

        panel.begin { @MainActor response in
            guard response == .OK, let selectedURL = panel.url else { return }

            // Save bookmark via manager
            SecurityScopedBookmarkManager.shared.saveBookmark(selectedURL, for: directory)

            self.openFolder(selectedURL)
        }
    }
    #endif

    private func chooseFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to browse"
        panel.prompt = "Open"

        panel.begin { @MainActor response in
            guard response == .OK, let url = panel.url else { return }
            self.openFolder(url)
        }
        #endif
    }

    private func openFolder(_ url: URL) {
        RecentFoldersManager.shared.addFolder(url)
        coordinator.openFolder(url)
        activateOrOpenBrowser()
        dismissWindow(id: "start")
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first,
              provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

            Task { @MainActor in
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }

                if isDirectory.boolValue {
                    openFolder(url)
                } else {
                    let ext = url.pathExtension.lowercased()
                    guard ext == "md" || ext == "markdown" else { return }
                    let folderURL = url.deletingLastPathComponent()
                    RecentFoldersManager.shared.addFolder(folderURL)
                    coordinator.openFolder(folderURL)
                    coordinator.selectFile(url)
                    coordinator.requestSidebarCollapsed()
                    activateOrOpenBrowser()
                    dismissWindow(id: "start")
                }
            }
        }
        return true
    }

    // MARK: - Welcome Folder (Easter Egg)

    private func openWelcomeFolder() {
        // Ensure Welcome folder exists in Application Support (copy from bundle if needed)
        guard let welcomeURL = WelcomeManager.ensureWelcomeFolder() else {
            return
        }

        coordinator.openFolder(welcomeURL)
        coordinator.setFirstLaunchWelcome(true)
        activateOrOpenBrowser()
        dismissWindow(id: "start")
    }

    // MARK: - Welcome Folder with AI Prompt

    /// Opens Welcome folder with 01-Welcome.md selected and AI chat pre-filled
    /// OOD Pattern: Uses existing infrastructure (openWithFileContext)
    /// Same code path as manual file selection + typing question
    private func openWelcomeFolderWithPrompt() {
        // Ensure Welcome folder exists in Application Support (copy from bundle if needed)
        guard let welcomeURL = WelcomeManager.ensureWelcomeFolder() else {
            showWelcomeError = true
            return
        }

        // Find 01-Welcome.md
        let welcomeFile = welcomeURL.appendingPathComponent("01-Welcome.md")

        // Verify file exists
        guard FileManager.default.fileExists(atPath: welcomeFile.path) else {
            showWelcomeError = true
            return
        }

        // OOD: Use existing infrastructure
        // This is the same code path as if user:
        // 1. Opened folder manually
        // 2. Selected file manually
        // 3. Typed question manually
        coordinator.openWithFileContext(
            fileURL: welcomeFile,
            question: "What is this app and what can I do with it?"
        )

        activateOrOpenBrowser()
        dismissWindow(id: "start")
    }

    // MARK: - Window Management

    /// Activates an existing browser window if one is visible, otherwise opens a new one.
    /// Prevents duplicate browser windows from being created by WindowGroup.
    private func activateOrOpenBrowser() {
        if let browserWindow = NSApp.windows.first(where: {
            $0.identifier?.rawValue.contains("browser") == true && $0.isVisible
        }) {
            browserWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            openWindow(id: "browser")
        }
    }
}

// MARK: - Folder Shortcut Button

struct FolderShortcutButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.blue)
                    .frame(width: 24)

                Text(title)
                    .font(.body)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(FolderButtonStyle())
    }
}

// MARK: - Folder Button Style

struct FolderButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .onHover { isHovered = $0 }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return Color.primary.opacity(0.1)
        } else if isHovered {
            return Color.primary.opacity(0.05)
        }
        return .clear
    }
}

// MARK: - Recent Item Button

struct RecentItemButton: View {
    let item: RecentItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: item.isFolder ? "folder" : "doc.text")
                    .font(.body)
                    .foregroundStyle(item.isFolder ? .blue : .secondary)
                    .frame(width: 24)

                Text(item.name)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(FolderButtonStyle())
    }
}

// MARK: - Mascot Button Style

struct MascotButtonStyle: ButtonStyle {
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.95 : (isHovered ? 1.02 : 1.0)))
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(reduceMotion ? .none : .easeInOut(duration: 0.15), value: configuration.isPressed)
            .animation(reduceMotion ? .none : .easeInOut(duration: 0.15), value: isHovered)
            .onHover { isHovered = $0 }
    }
}
