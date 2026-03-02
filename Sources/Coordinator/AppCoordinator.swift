import SwiftUI
import SwiftData
import Foundation

// MARK: - App Coordinator

/// Central coordinator that owns and manages all application state.
///
/// OOD Pattern: AppCoordinator is the single source of truth for state.
/// Views observe state containers through Environment, and call coordinator
/// methods to mutate state. This provides:
/// 1. Clear ownership hierarchy
/// 2. Testable state management
/// 3. Explicit mutation paths
///
/// State is decomposed into focused containers:
/// - NavigationState: folder/file selection
/// - UIState: panel visibility, appearance
/// - DocumentState: document content, loading
@MainActor
@Observable
public final class AppCoordinator {

    // MARK: - State Containers

    /// Navigation state (folder selection, file selection)
    public let navigation = NavigationState()

    /// UI state (panel visibility, appearance)
    public let ui = UIState()

    /// Document state (content, loading, changes)
    public let document = DocumentState()


    // MARK: - Repositories

    /// File metadata repository for persistence (optional - set after container init)
    public var metadata: FileMetadataRepository?

    /// Watches the open folder for file system changes (new/modified/deleted files)
    private var folderWatcher: FolderWatcher?

    /// Coalesces rapid FSEvent-triggered reloads into a single tree reload
    private var folderReloadTask: Task<Void, Never>?

    /// Debounced scroll save task — coalesces ~60 saves/sec into ~2/sec
    private var scrollSaveTask: Task<Void, Never>?
    private var pendingScrollPosition: (url: URL, position: Double)?

    // MARK: - Initialization

    public init() {}

    /// Initialize with a metadata repository
    public init(metadata: FileMetadataRepository) {
        self.metadata = metadata
    }

    // MARK: - Navigation Actions

    /// Opens a folder and clears previous file selection
    public func openFolder(_ url: URL) {
        navigation.openFolder(url)
        document.clearContent()
        startFolderWatcher(for: url)
    }

    /// Closes the current folder and returns to start screen
    public func closeFolder() {
        flushScrollPosition()
        stopFolderWatcher()
        navigation.closeFolder()
        document.clearContent()
    }

    /// Selects a file for viewing
    public func selectFile(_ url: URL) {
        flushScrollPosition()
        navigation.selectFile(url)
        navigation.clearChanged(for: url)
        document.clearChanges()
    }

    /// Sets the first-launch welcome flag (auto-select first file)
    public func setFirstLaunchWelcome(_ value: Bool) {
        navigation.isFirstLaunchWelcome = value
    }

    /// Updates the sidebar filter query
    public func setSidebarFilter(_ query: String) {
        navigation.sidebarFilterQuery = query
    }

    /// Computed binding for sidebar filter query (two-way binding for TextField)
    public var sidebarFilterQuery: String {
        get { navigation.sidebarFilterQuery }
        set { navigation.sidebarFilterQuery = newValue }
    }

    /// Updates the pre-filtered display items
    func setDisplayItems(_ items: [FolderItem]) {
        navigation.displayItems = items
    }

    // MARK: - Document Actions

    /// Loads (or reloads) the document for the currently selected file
    public func loadDocument() async {
        guard let url = navigation.selectedFile else {
            document.clearContent()
            return
        }
        await document.loadFile(url: url)
        metadata?.updateLastOpened(for: url)
    }

    /// Triggers a reload of the current document
    public func reloadDocument() {
        document.triggerReload()
    }

    /// Marks the document as having external changes
    public func markDocumentChanged() {
        document.markChanged()
    }

    /// Clears the document change indicator
    public func clearDocumentChanges() {
        document.clearChanges()
    }

    // MARK: - UI Actions

    /// Toggles AI chat panel visibility
    public func toggleAIChat() {
        ui.toggleAIChat()
    }

    /// Shows an error in the status bar
    func showError(_ error: AppError) {
        ui.showError(error)
    }

    /// Dismisses the current error
    public func dismissError() {
        ui.dismissError()
    }

    /// Signals that the browser window should open
    public func requestOpenBrowser() {
        ui.shouldOpenBrowser = true
    }

    /// Consumes the browser open flag
    public func consumeOpenBrowser() {
        ui.shouldOpenBrowser = false
    }

    /// Requests sidebar collapsed on next BrowserView appear (single-file open)
    public func requestSidebarCollapsed() {
        ui.prefersSidebarCollapsed = true
    }

    /// Consumes the sidebar-collapsed flag (returns true once, then resets)
    public func consumeSidebarCollapsed() -> Bool {
        guard ui.prefersSidebarCollapsed else { return false }
        ui.prefersSidebarCollapsed = false
        return true
    }

    /// Clears the initial chat question (consumed after use)
    public func consumeInitialChatQuestion() -> String? {
        let question = ui.initialChatQuestion
        ui.initialChatQuestion = nil
        return question
    }

    /// Computed binding for AI chat visibility (two-way binding for inspector)
    public var isAIChatVisible: Bool {
        get { ui.isAIChatVisible }
        set { ui.isAIChatVisible = newValue }
    }

    // MARK: - Quick Switcher Actions

    /// Toggles the Quick Switcher overlay
    public func toggleQuickSwitcher() {
        ui.isQuickSwitcherVisible.toggle()
    }

    /// Dismisses the Quick Switcher overlay
    public func dismissQuickSwitcher() {
        ui.isQuickSwitcherVisible = false
    }

    // MARK: - Composite Actions

    /// Opens browser with a specific file selected and chat ready
    public func openWithFileContext(fileURL: URL, question: String) {
        let parentFolder = fileURL.deletingLastPathComponent()
        navigation.openFolder(parentFolder)
        navigation.selectFile(fileURL)
        ui.initialChatQuestion = question
        ui.isAIChatVisible = true
        document.clearContent()
    }

    // MARK: - Metadata Actions

    /// Saves scroll position for the currently selected file (debounced 500ms).
    /// Coalesces ~60 scroll events/sec into at most 2 disk writes/sec.
    public func saveScrollPosition(_ position: Double) {
        guard let url = navigation.selectedFile else { return }
        pendingScrollPosition = (url: url, position: position)
        scrollSaveTask?.cancel()
        scrollSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.flushScrollPosition()
        }
    }

    /// Flushes any pending scroll position save immediately.
    /// Call on file switch or app termination.
    public func flushScrollPosition() {
        scrollSaveTask?.cancel()
        scrollSaveTask = nil
        guard let pending = pendingScrollPosition else { return }
        pendingScrollPosition = nil
        metadata?.saveScrollPosition(pending.position, for: pending.url)
    }

    /// Gets scroll position for a file
    public func getScrollPosition(for url: URL) -> Double {
        metadata?.getMetadata(for: url)?.scrollPosition ?? 0.0
    }

    /// Toggles favorite status for a file
    public func toggleFavorite(for url: URL) {
        guard let repo = metadata else { return }
        let current = repo.isFavorite(url)
        repo.setFavorite(!current, for: url)
    }

    /// Checks if a file is favorited
    public func isFavorite(_ url: URL) -> Bool {
        metadata?.isFavorite(url) ?? false
    }

    /// Gets all favorite files
    public func getFavorites() -> [URL] {
        metadata?.getFavorites() ?? []
    }

    /// Adds a bookmark at the specified line
    public func addBookmark(lineNumber: Int, note: String? = nil) {
        guard let url = navigation.selectedFile else { return }
        metadata?.addBookmark(for: url, lineNumber: lineNumber, note: note)
    }

    /// Gets bookmarks for current file
    public func getBookmarks() -> [Bookmark] {
        guard let url = navigation.selectedFile else { return [] }
        return metadata?.getBookmarks(for: url) ?? []
    }

    /// Deletes a bookmark
    public func deleteBookmark(_ id: UUID) {
        metadata?.deleteBookmark(id)
    }

    // MARK: - Folder Watcher

    /// Suspend folder watcher when app resigns active (saves energy).
    public func suspendFolderWatcher() {
        folderWatcher?.suspend()
    }

    /// Resume folder watcher when app becomes active.
    /// Also triggers a quiet tree diff to catch any changes that occurred while suspended.
    public func resumeFolderWatcher() {
        folderWatcher?.resume()

        // Safety net: diff tree to catch events missed during suspend
        guard let rootURL = navigation.rootFolderURL else { return }
        folderReloadTask?.cancel()
        folderReloadTask = Task { [weak self] in
            guard let self else { return }

            // Invalidate root cache so loadTreeWithDiff does a fresh scan
            FolderService.shared.invalidateCache(for: rootURL)
            let newTree = await FolderService.shared.loadTreeWithDiff(at: rootURL)
            guard !Task.isCancelled, self.navigation.rootFolderURL != nil else { return }

            let newDisplay = FolderTreeFilter.filterMarkdownOnly(newTree)

            // Only update if tree actually changed (avoids reloadData flicker)
            let oldPaths = Self.collectFilePaths(from: self.navigation.displayItems)
            let newPaths = Self.collectFilePaths(from: newDisplay)
            guard oldPaths != newPaths else { return }

            let addedPaths = newPaths.subtracting(oldPaths)
            if let selected = self.navigation.selectedFile {
                // Don't dot the currently open file
                self.navigation.markPathsChanged(addedPaths.subtracting([selected.path]))
            } else {
                self.navigation.markPathsChanged(addedPaths)
            }
            self.navigation.displayItems = newDisplay
        }
    }

    private func startFolderWatcher(for url: URL) {
        stopFolderWatcher()
        let watcher = FolderWatcher { [weak self] changedDirs in
            self?.handleFolderChanges(changedDirs)
        }
        watcher.watch(url)
        folderWatcher = watcher
    }

    private func stopFolderWatcher() {
        folderReloadTask?.cancel()
        folderReloadTask = nil
        folderWatcher?.stop()
        folderWatcher = nil
        navigation.changedPaths.removeAll()
    }

    /// Responds to FSEvents: invalidates cache, reloads tree, marks changed paths.
    /// Coalesces rapid events — cancels any in-flight reload before starting a new one.
    private func handleFolderChanges(_ changedDirs: Set<String>) {
        guard let rootURL = navigation.rootFolderURL else { return }

        // Invalidate cache for each changed directory
        for dir in changedDirs {
            FolderService.shared.invalidateCache(for: URL(fileURLWithPath: dir))
        }

        // Cancel any in-flight reload to coalesce rapid FSEvent bursts
        folderReloadTask?.cancel()
        folderReloadTask = Task { [weak self] in
            guard let self else { return }
            let oldItems = self.navigation.displayItems
            let newTree = await FolderService.shared.loadTreeWithDiff(at: rootURL)

            // Guard: folder may have been closed during async reload
            guard !Task.isCancelled, self.navigation.rootFolderURL != nil else { return }

            let newDisplay = FolderTreeFilter.filterMarkdownOnly(newTree)

            // Identify new or modified files by diffing old vs new
            let oldPaths = Self.collectFilePaths(from: oldItems)
            let newPaths = Self.collectFilePaths(from: newDisplay)

            // New files = paths in new that weren't in old
            let addedPaths = newPaths.subtracting(oldPaths)
            // Modified files = files in changed directories (exclude currently open file)
            var modifiedPaths = Set<String>()
            for dir in changedDirs {
                Self.collectFilePathsUnder(dir, from: newDisplay, into: &modifiedPaths)
            }

            // Don't mark the currently open file (user is already seeing it)
            if let selected = self.navigation.selectedFile {
                modifiedPaths.remove(selected.path)
            }

            self.navigation.markPathsChanged(addedPaths.union(modifiedPaths))
            self.navigation.displayItems = newDisplay
        }
    }

    /// Collects all file (non-folder) paths from a tree.
    private static func collectFilePaths(from items: [FolderItem]) -> Set<String> {
        var paths = Set<String>()
        func walk(_ items: [FolderItem]) {
            for item in items {
                if !item.isFolder {
                    paths.insert(item.url.path)
                }
                if let children = item.children {
                    walk(children)
                }
            }
        }
        walk(items)
        return paths
    }

    /// Collects file paths that are descendants of a given directory path.
    private static func collectFilePathsUnder(_ dirPath: String, from items: [FolderItem], into result: inout Set<String>) {
        for item in items {
            if !item.isFolder && item.url.deletingLastPathComponent().path == dirPath {
                result.insert(item.url.path)
            }
            if let children = item.children {
                collectFilePathsUnder(dirPath, from: children, into: &result)
            }
        }
    }
}

// MARK: - Navigation State

/// State container for folder and file navigation.
@MainActor
@Observable
public final class NavigationState {

    /// Root folder selected by user (nil until user selects one)
    public private(set) var rootFolderURL: URL? = nil

    /// Currently selected file to view
    public private(set) var selectedFile: URL? = nil

    /// Flag for first-launch welcome (auto-select first file)
    public internal(set) var isFirstLaunchWelcome: Bool = false

    /// Sidebar search/filter query
    internal var sidebarFilterQuery: String = ""

    /// Pre-filtered display items (shared with Quick Switcher)
    internal var displayItems: [FolderItem] = []

    /// Paths of files that are new or modified since last viewed (for blue dot indicator)
    internal var changedPaths: Set<String> = []

    /// Sidebar expansion state — persists across NSViewRepresentable Coordinator recreation.
    /// SwiftUI can destroy and recreate the OutlineFileList Coordinator at any time
    /// (e.g., NavigationSplitView column management, view identity changes).
    /// Storing expansion state here ensures it survives those recreations.
    internal var sidebarExpandedPaths = Set<String>()

    // MARK: - Actions

    func openFolder(_ url: URL) {
        // Stop accessing previous folder if any
        rootFolderURL?.stopAccessingSecurityScopedResource()

        // Start accessing new folder's security scope
        _ = url.startAccessingSecurityScopedResource()

        rootFolderURL = url
        selectedFile = nil
        sidebarFilterQuery = ""
        sidebarExpandedPaths.removeAll()
    }

    func closeFolder() {
        rootFolderURL?.stopAccessingSecurityScopedResource()
        rootFolderURL = nil
        selectedFile = nil
        changedPaths.removeAll()
        sidebarExpandedPaths.removeAll()
    }

    func selectFile(_ url: URL) {
        selectedFile = url
    }

    // MARK: - Change Tracking

    /// Adds paths to the changed set (new or modified files).
    func markPathsChanged(_ paths: Set<String>) {
        changedPaths.formUnion(paths)
    }

    /// Removes a file's path from the changed set (user opened/viewed it).
    func clearChanged(for url: URL) {
        changedPaths.remove(url.path)
    }

    /// Checks if a file path is in the changed set.
    func isChanged(_ url: URL) -> Bool {
        changedPaths.contains(url.path)
    }

    /// Checks if any descendant of a folder has changes (for folder dot indicators).
    func hasChangedDescendant(_ folderURL: URL) -> Bool {
        let prefix = folderURL.path + "/"
        return changedPaths.contains { $0.hasPrefix(prefix) }
    }
}

// MARK: - UI State

/// State container for UI presentation.
@MainActor
@Observable
public final class UIState {

    /// Whether the AI Chat panel is visible
    public internal(set) var isAIChatVisible: Bool = false

    /// Flag to trigger browser window opening (consumed by views)
    public internal(set) var shouldOpenBrowser: Bool = false

    /// Initial question for chat (set from start screen, cleared after use)
    public internal(set) var initialChatQuestion: String? = nil

    /// Current error to display in the status bar
    private(set) var currentError: AppError? = nil

    /// Color scheme override for the session (nil = follow system)
    public internal(set) var colorSchemeOverride: ColorScheme? = nil

    /// Whether the Quick Switcher overlay is visible
    public internal(set) var isQuickSwitcherVisible: Bool = false

    /// Consume-once flag: sidebar should start collapsed (single-file open)
    public internal(set) var prefersSidebarCollapsed: Bool = false

    // MARK: - Actions

    func toggleAIChat() {
        isAIChatVisible.toggle()
    }

    func showError(_ error: AppError) {
        currentError = error
    }

    func dismissError() {
        currentError = nil
    }
}

// MARK: - Document State

/// State container for document content and loading.
/// DocumentState is the single source of truth for document text.
/// It owns file loading — views read from it, never load independently.
@MainActor
@Observable
public final class DocumentState {

    /// Current document content (loaded from file)
    public private(set) var content: String = ""

    /// Whether the document is currently loading
    public private(set) var isLoading: Bool = false

    /// File load error message (nil = no error)
    public private(set) var errorMessage: String? = nil

    /// Whether the current file has unseen external changes
    public private(set) var hasChanges: Bool = false

    /// Reload trigger (incremented to force reload)
    public private(set) var reloadTrigger: Int = 0

    // MARK: - File Loading

    /// Loads file content from disk. This is the authoritative load path.
    /// MarkdownView and ChatView both read from `content` after this completes.
    func loadFile(url: URL) async {
        isLoading = true
        errorMessage = nil

        do {
            let text = try await Task.detached(priority: .userInitiated) {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize = attributes[.size] as? Int ?? 0

                guard fileSize <= MarkdownConfig.maxTextSize else {
                    throw FileLoadError.fileTooLarge(size: fileSize)
                }

                let data = try Data(contentsOf: url)
                guard let text = String(data: data, encoding: .utf8) else {
                    throw FileLoadError.invalidEncoding
                }
                return text
            }.value

            content = text
            hasChanges = false
        } catch {
            errorMessage = error.localizedDescription
            content = ""
        }

        isLoading = false
    }

    // MARK: - Actions

    func clearContent() {
        content = ""
        hasChanges = false
        errorMessage = nil
    }

    func markChanged() {
        hasChanges = true
    }

    func clearChanges() {
        hasChanges = false
    }

    func triggerReload() {
        reloadTrigger += 1
        hasChanges = false
    }
}

// MARK: - File Load Errors

enum FileLoadError: LocalizedError {
    case fileTooLarge(size: Int)
    case invalidEncoding

    var errorDescription: String? {
        switch self {
        case .fileTooLarge(let size):
            let mb = Double(size) / 1_048_576
            return "File is too large (\(String(format: "%.1f", mb)) MB). Maximum supported size is 10 MB."
        case .invalidEncoding:
            return "Unable to decode file as UTF-8 text"
        }
    }
}

// MARK: - Environment Key

/// Environment key for injecting AppCoordinator into the view hierarchy.
/// The shared instance provides a default for views that don't have a coordinator injected.
/// In practice, the app always injects a coordinator explicitly via .environment(\.coordinator, coordinator).
// @preconcurrency required: EnvironmentKey.defaultValue lacks @MainActor annotation.
// Safe because SwiftUI accesses this on @MainActor view update path.
private struct AppCoordinatorKey: @preconcurrency EnvironmentKey {
    @MainActor static var defaultValue = AppCoordinator()
}

extension EnvironmentValues {
    public var coordinator: AppCoordinator {
        get { self[AppCoordinatorKey.self] }
        set { self[AppCoordinatorKey.self] = newValue }
    }
}
