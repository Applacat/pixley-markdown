import SwiftUI
import UniformTypeIdentifiers

// MARK: - Browser View

/// Main browser layout - shown after a folder is selected.
/// Displays folder navigation, markdown viewer, and AI chat inspector.
struct BrowserView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var isDropTargeted = false

    // MARK: - Body

    var body: some View {
        Group {
            if appState.rootFolderURL != nil {
                browserContent
            } else {
                // Redirect to start window if no folder selected
                noFolderView
            }
        }
        .onDisappear {
            // Invalidate cache for this folder
            if let folderURL = appState.rootFolderURL {
                FolderService.shared.invalidateCache(for: folderURL)
            }
            
            // Clear folder state and reopen start window when browser closes
            appState.closeFolder()
            openWindow(id: "start")
        }
    }

    // MARK: - Browser Content

    private var browserContent: some View {
        @Bindable var appState = appState

        return NavigationSplitView {
            OutlineFileListWrapper()
                .navigationSplitViewColumnWidth(min: 280, ideal: 400, max: 600)
        } detail: {
            if appState.selectedFile != nil {
                MarkdownView()
            } else {
                noSelectionView
            }
        }
        #if os(macOS)
        .inspector(isPresented: $appState.isAIChatVisible) {
            ChatView()
                .inspectorColumnWidth(min: 250, ideal: 280, max: 400)
        }
        .toolbar {
            // Font size controls + AI Chat toggle
            ToolbarItemGroup(placement: .primaryAction) {
                FontSizeControls()
                
                Divider()
                    .frame(height: 16)
                
                Button {
                    withAnimation {
                        appState.isAIChatVisible.toggle()
                    }
                } label: {
                    Label(
                        appState.isAIChatVisible ? "Hide AI Chat" : "Show AI Chat",
                        systemImage: appState.isAIChatVisible
                            ? "bubble.left.and.bubble.right.fill"
                            : "bubble.left.and.bubble.right"
                    )
                }
                .help(appState.isAIChatVisible ? "Hide AI Chat" : "Show AI Chat")
            }
        }
        #endif
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(urls)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .overlay {
            if isDropTargeted {
                dropOverlay
            }
        }
    }

    // MARK: - No Folder View

    private var noFolderView: some View {
        Color.clear
            .onAppear {
                // Auto-redirect to start screen
                openWindow(id: "start")
                dismissWindow(id: "browser")
            }
    }

    // MARK: - No Selection View

    private var noSelectionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tertiary)

            Text("Select a markdown file")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Drop Overlay

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 4]))
            .background(Color.accentColor.opacity(0.1))
            .padding(8)
            .allowsHitTesting(false)
    }

    // MARK: - Actions

    private func closeAndReturnToStart() {
        appState.closeFolder()
        openWindow(id: "start")
        dismissWindow(id: "browser")
    }

    private func handleDrop(_ urls: [URL]) -> Bool {
        guard let url = urls.first else { return false }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }

        if isDirectory.boolValue {
            RecentFoldersManager.shared.addFolder(url)
            appState.setRootFolder(url)
            return true
        } else if url.pathExtension.lowercased() == "md" || url.pathExtension.lowercased() == "markdown" {
            let folderURL = url.deletingLastPathComponent()
            RecentFoldersManager.shared.addFolder(folderURL)
            appState.setRootFolder(folderURL)
            appState.selectFile(url)
            return true
        }

        return false
    }
}

// MARK: - Outline File List Wrapper

/// Wrapper for OutlineFileList that handles loading and filtering
struct OutlineFileListWrapper: View {
    
    @Environment(AppState.self) private var appState
    @State private var rootItems: [FolderItem] = []
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                OutlineFileList(
                    items: filteredItems(rootItems),
                    selection: Binding(
                        get: { appState.selectedFile },
                        set: { newValue in
                            if let url = newValue {
                                appState.selectFile(url)
                                RecentFoldersManager.shared.addRecentFile(url, parentFolder: appState.rootFolderURL)
                            }
                        }
                    )
                )
            }
        }
        .task(id: appState.rootFolderURL) {
            await loadRootFolder()
        }
    }
    
    private func loadRootFolder() async {
        guard let rootURL = appState.rootFolderURL else { return }
        isLoading = true
        FolderService.shared.invalidateCache(for: rootURL)
        rootItems = await FolderService.shared.loadTree(at: rootURL)
        
        // First launch welcome: select first markdown
        if appState.isFirstLaunchWelcome {
            if let firstMarkdown = findFirstMarkdown(in: rootItems) {
                appState.selectFile(firstMarkdown.url)
            }
            appState.isFirstLaunchWelcome = false
        }
        
        isLoading = false
    }
    
    // Always filter to markdown-only (recursive, preserves filtered children)
    private func filteredItems(_ items: [FolderItem]) -> [FolderItem] {
        items.compactMap { item in
            if item.isFolder {
                // Keep folder if it has markdown files
                let filteredChildren = filteredItems(item.children ?? [])
                if filteredChildren.isEmpty {
                    return nil
                }
                // Create new FolderItem with filtered children
                return FolderItem(
                    url: item.url,
                    isFolder: true,
                    markdownCount: filteredChildren.reduce(0) { $0 + $1.markdownCount },
                    children: filteredChildren
                )
            } else {
                // Only keep markdown files
                return item.isMarkdown ? item : nil
            }
        }
    }
    
    private func findFirstMarkdown(in items: [FolderItem]) -> FolderItem? {
        for item in items {
            if item.isMarkdown { return item }
            if let children = item.children,
               let found = findFirstMarkdown(in: children) {
                return found
            }
        }
        return nil
    }
}

// MARK: - Font Size Controls

/// Toolbar controls for adjusting markdown display settings
struct FontSizeControls: View {
    
    @AppStorage("fontSize") private var fontSize: Double = 14.0
    
    var body: some View {
        HStack(spacing: 4) {
            // Decrease font size
            Button {
                fontSize = max(10, fontSize - 1)
            } label: {
                Image(systemName: "minus")
            }
            .help("Decrease font size")
            .disabled(fontSize <= 10)
            
            // Increase font size
            Button {
                fontSize = min(32, fontSize + 1)
            } label: {
                Image(systemName: "plus")
            }
            .help("Increase font size")
            .disabled(fontSize >= 32)
        }
        .controlSize(.small)
    }
}


