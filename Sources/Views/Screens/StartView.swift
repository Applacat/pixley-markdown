import SwiftUI
import UniformTypeIdentifiers

// MARK: - Start View

/// Launcher window with branding, entry points, and recent items panel.
/// Compact (entry points only) when no recents exist; expands side-by-side when recents are available.
/// Click app icon to open Welcome tour (easter egg).
struct StartView: View {

    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    #else
    /// iOS callback — replaces openWindow/dismissWindow since iPhone is single-window.
    /// Provided by iOSRootView to navigate in-place.
    var onOpenBrowser: ((BrowserOpenRequest) -> Void)?
    #endif

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isDropTargeted = false
    @State private var hasPerformedLaunch = false
    @State private var isReady = false
    @State private var showWelcomeError = false
    @State private var recents: [RecentItem] = []
    @State private var hasPruned = false
    #if os(iOS)
    @State private var showFolderPicker = false
    @State private var showFilePicker = false
    #endif

    private var hasRecents: Bool { !recents.isEmpty }

    var body: some View {
        Group {
            if isReady {
                launcherContent
            } else {
                Color.clear
            }
        }
        #if os(macOS)
        .frame(width: hasRecents ? 720 : 480, height: 520)
        #endif
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.25), value: hasRecents)
        .onAppear {
            #if os(macOS)
            // Store openWindow action for AppDelegate bridge
            WindowRouter.shared.openWindowAction = openWindow
            #endif

            // Run launch logic first (only once)
            if !hasPerformedLaunch {
                hasPerformedLaunch = true

                if let request = determineLaunchRequest() {
                    openBrowserAndDismiss(request)
                    return
                }
            }

            // Prune stale items once, then load recents
            if !hasPruned {
                RecentFoldersManager.shared.pruneStaleItems()
                hasPruned = true
            }
            recents = RecentFoldersManager.shared.getAllRecents()
            isReady = true
        }
        #if os(iOS)
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFileImporterResult(result, isFolder: true)
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [
                .init(filenameExtension: "md") ?? .plainText,
                .init(filenameExtension: "markdown") ?? .plainText
            ],
            allowsMultipleSelection: false
        ) { result in
            handleFileImporterResult(result, isFolder: false)
        }
        #endif
    }

    // MARK: - Launch Logic

    private func determineLaunchRequest() -> BrowserOpenRequest? {
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: PixleyMarkdownApp.hasLaunchedBeforeKey)

        if !hasLaunchedBefore {
            UserDefaults.standard.set(true, forKey: PixleyMarkdownApp.hasLaunchedBeforeKey)
            guard let welcomeURL = WelcomeManager.ensureWelcomeFolder() else { return nil }
            return BrowserOpenRequest(folderURL: welcomeURL, isFirstLaunchWelcome: true)
        }

        // Always show StartView — no auto-restore of last session
        return nil
    }

    // MARK: - Launcher Content

    private var launcherContent: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                mascotHeader

                #if os(macOS)
                if hasRecents {
                    HStack(alignment: .top, spacing: 16) {
                        entryPointsColumn
                        Divider().padding(.vertical, 4)
                        recentsColumn
                    }
                } else {
                    entryPointsColumn
                }
                #else
                // iOS: vertical layout — entry points then recents below
                entryPointsColumn
                if hasRecents {
                    recentsColumn
                }
                #endif
            }

            Spacer()

            #if os(macOS)
            Text("or drop a folder or .md file anywhere")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 20)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        #if os(macOS)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDropTargeted {
                dropOverlay
            }
        }
        #endif
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
                Image("Pixley")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                    .accessibilityLabel("Pixley Markdown app icon")

                VStack(spacing: 4) {
                    Text("Pixley Markdown")
                        .font(.title2.bold())

                    Text("Read and Collaborate with your AI's Markdown")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .buttonStyle(MascotButtonStyle())
        .accessibilityLabel("Open tutorial")
        .accessibilityHint("Opens the interactive setup guide")
    }

    // MARK: - Entry Points Column

    private var entryPointsColumn: some View {
        VStack(spacing: 4) {
            #if os(macOS)
            launcherButton("Open File", icon: "doc.text", color: .blue, action: chooseFile)
            launcherButton("Open Folder", icon: "folder", color: .blue, action: chooseFolder)
            launcherButton("Browse iCloud Drive", icon: "icloud", color: .cyan, action: browseICloudDrive)
            #else
            launcherButton("Browse iCloud Drive", icon: "icloud", color: .blue) { showFolderPicker = true }
            launcherButton("Open File", icon: "doc.text", color: .blue) { showFilePicker = true }
            #endif
            launcherButton("Sample Files", icon: "book.circle", color: .orange, action: openWelcomeFolderWithPrompt)
        }
        #if os(macOS)
        .frame(width: 220)
        #else
        .frame(maxWidth: 300)
        .padding(.horizontal, 24)
        #endif
    }

    private func launcherButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                Text(title)
                    .font(.body)
            }
        }
        .buttonStyle(LauncherButtonStyle())
        .accessibilityLabel(title)
    }

    // MARK: - Recents Column

    private var recentsColumn: some View {
        let grouped = RecentFoldersManager.groupedRecents(recents)

        return VStack(alignment: .leading, spacing: 0) {
            Text("Recent")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(grouped, id: \.0) { group, items in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(group.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fontWeight(.medium)
                                .textCase(.uppercase)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 4)
                                .accessibilityAddTraits(.isHeader)

                            ForEach(items) { item in
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
                }
            }

            Divider()
                .padding(.vertical, 4)

            Button("Clear Recents", role: .destructive) {
                withAnimation {
                    RecentFoldersManager.shared.clearAll()
                    recents = []
                }
            }
            .accessibilityHint("Removes all recent files and folders from the list")
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        #if os(macOS)
        .frame(width: 280)
        #else
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        #endif
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
        guard let request = RecentFoldersManager.shared.resolveRecentItem(item) else {
            removeRecentItem(item)
            return
        }
        openBrowserAndDismiss(request)
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

    // MARK: - File/Folder Actions

    #if os(macOS)
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["md", "markdown"].compactMap { UTType(filenameExtension: $0) }
        panel.message = "Choose a markdown file"
        panel.prompt = "Open"

        panel.begin { @MainActor response in
            guard response == .OK, let fileURL = panel.url else { return }
            let folderURL = fileURL.deletingLastPathComponent()
            RecentFoldersManager.shared.addFolder(folderURL)
            openBrowserAndDismiss(BrowserOpenRequest(
                folderURL: folderURL,
                fileURL: fileURL,
                preferSidebarCollapsed: true
            ))
        }
    }

    private func chooseFolder() {
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
    }

    private func browseICloudDrive() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose an iCloud Drive folder"
        panel.prompt = "Open"

        // Point panel at iCloud Drive if available
        if let iCloudURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            panel.directoryURL = iCloudURL.appendingPathComponent("Documents")
        } else {
            // Fall back to user's iCloud Drive via ~/Library/Mobile Documents
            let mobileDocuments = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
            if FileManager.default.fileExists(atPath: mobileDocuments.path) {
                panel.directoryURL = mobileDocuments
            }
        }

        panel.begin { @MainActor response in
            guard response == .OK, let url = panel.url else { return }
            self.openFolder(url)
        }
    }
    #endif

    private func openFolder(_ url: URL) {
        RecentFoldersManager.shared.addFolder(url)
        openBrowserAndDismiss(BrowserOpenRequest(folderURL: url))
    }

    #if os(macOS)
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
                    openBrowserAndDismiss(BrowserOpenRequest(
                        folderURL: folderURL,
                        fileURL: url,
                        preferSidebarCollapsed: true
                    ))
                }
            }
        }
        return true
    }
    #endif

    // MARK: - iOS File Importer

    #if os(iOS)
    /// Handles file/folder selection from iOS fileImporter.
    /// Security-scoped access is started here and released after the coordinator
    /// takes ownership via its own bookmark lifecycle in NavigationState.openFolder().
    private func handleFileImporterResult(_ result: Result<[URL], Error>, isFolder: Bool) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            if isFolder {
                openFolder(url)
            } else {
                let folderURL = url.deletingLastPathComponent()
                guard folderURL.startAccessingSecurityScopedResource() else { return }
                defer { folderURL.stopAccessingSecurityScopedResource() }

                RecentFoldersManager.shared.addFolder(folderURL)
                openBrowserAndDismiss(BrowserOpenRequest(
                    folderURL: folderURL,
                    fileURL: url,
                    preferSidebarCollapsed: true
                ))
            }

        case .failure:
            break // User cancelled or system error
        }
    }
    #endif

    // MARK: - Welcome Folder (Easter Egg)

    private func openWelcomeFolder() {
        guard let welcomeURL = WelcomeManager.ensureWelcomeFolder() else { return }
        openBrowserAndDismiss(BrowserOpenRequest(
            folderURL: welcomeURL,
            isFirstLaunchWelcome: true
        ))
    }

    // MARK: - Welcome Folder with AI Prompt

    private func openWelcomeFolderWithPrompt() {
        guard let welcomeURL = WelcomeManager.ensureWelcomeFolder() else {
            showWelcomeError = true
            return
        }

        let welcomeFile = welcomeURL.appendingPathComponent("01-Welcome.md")
        guard FileManager.default.fileExists(atPath: welcomeFile.path) else {
            showWelcomeError = true
            return
        }

        openBrowserAndDismiss(BrowserOpenRequest(
            folderURL: welcomeURL,
            fileURL: welcomeFile,
            initialChatQuestion: "What is this app and what can I do with it?"
        ))
    }

    // MARK: - Window Management

    private func openBrowserAndDismiss(_ request: BrowserOpenRequest) {
        #if os(macOS)
        openWindow(id: "browser", value: request)
        dismissWindow(id: "start")
        #else
        onOpenBrowser?(request)
        #endif
    }
}

// MARK: - Recent Item Button

private struct RecentItemButton: View {
    let item: RecentItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: item.isFolder ? "folder" : "doc.text")
                    .font(.body)
                    .foregroundStyle(item.isFolder ? .blue : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let parentName = item.parentFolderName {
                        Text(parentName)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("\(item.name)\(item.parentFolderName.map { " in \($0)" } ?? "")")
        .accessibilityHint(item.isFolder ? "Open folder" : "Open file")
        .buttonStyle(LauncherButtonStyle())
    }
}

// MARK: - Launcher Button Style

/// Xcode-welcome-screen style: transparent at rest, subtle fill on hover, darker on press.
/// Uses semantic ShapeStyles (.quaternary/.quinary) for automatic dark mode / vibrancy adaptation.
private struct LauncherButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovering || configuration.isPressed
                          ? AnyShapeStyle(configuration.isPressed ? .quaternary : .quinary)
                          : AnyShapeStyle(.clear))
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { isHovering = $0 }
    }
}

// MARK: - Mascot Button Style

private struct MascotButtonStyle: ButtonStyle {
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
