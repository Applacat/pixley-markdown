import SwiftUI

// MARK: - Launch State

/// Determines what to show on app launch
enum LaunchState {
    case firstLaunch        // Show Welcome folder in browser
    case sessionRestore     // Restore last opened folder
    case minimalLauncher    // Show minimal launcher (no folder context)
}

// MARK: - App Entry Point

/// AI.md Reader - A native macOS markdown reader for AI-generated files.
/// Watch what AI writes, ask questions about it, stay in flow.
@main
struct AIMDReaderApp: App {

    // MARK: - Constants

    static let hasLaunchedBeforeKey = "hasLaunchedBefore"

    // MARK: - State

    @State private var appState = AppState()
    @State private var launchState: LaunchState = .minimalLauncher

    // MARK: - Welcome Folder Location

    /// Welcome folder in Application Support (persists reliably, backed up)
    private static var welcomeFolderURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AIMDReader")
            .appendingPathComponent("Welcome")
    }

    /// Ensures Welcome folder exists in Application Support, copying from bundle if needed
    private static func ensureWelcomeFolder() -> URL? {
        guard let targetURL = welcomeFolderURL else { return nil }

        // Already exists - use it
        if FileManager.default.fileExists(atPath: targetURL.path) {
            return targetURL
        }

        // Copy from bundle
        guard let bundleURL = Bundle.main.url(forResource: "Welcome", withExtension: nil) else {
            return nil
        }

        do {
            let parentDir = targetURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: bundleURL, to: targetURL)
            return targetURL
        } catch {
            return nil  // Silent fallback
        }
    }

    var body: some Scene {
        // Start window - minimal launcher
        Window("AI.md Reader", id: "start") {
            StartView(performLaunchIfNeeded: performLaunchIfNeeded)
                .environment(appState)
                .preferredColorScheme(.dark)
        }
        #if os(macOS)
        .defaultLaunchBehavior(.presented)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)  // Always open centered, don't remember position
        #endif

        #if DEBUG
        // AI Test window - for experimenting with Foundation Models (DEBUG ONLY)
        Window("AI Test", id: "ai-test") {
            AITestView()
                .preferredColorScheme(.dark)
        }
        #if os(macOS)
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentSize)
        #endif
        #endif

        // Browser window - shown after folder selection
        WindowGroup("AI.md Reader", id: "browser") {
            BrowserView()
                .environment(appState)
                .applyColorSchemePreference()
        }
        #if os(macOS)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(after: .newItem) {
                Button(appState.rootFolderURL == nil ? "Choose Folder..." : "Change Folder...") {
                    openFolderPanel()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Divider()

                Button("Reload") {
                    appState.triggerReload()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(appState.selectedFile == nil)
            }
            
            // Help menu
            CommandGroup(replacing: .help) {
                Button("AI.md Reader Help") {
                    openWelcomeToPage("01-Welcome.md")
                }
                .keyboardShortcut("/", modifiers: [.command])
                
                Button("Browsing Folders") {
                    openWelcomeToPage("02-Browsing-Folders.md")
                }
                
                Button("Ask AI") {
                    openWelcomeToPage("03-Ask-AI.md")
                }
                
                Button("Keyboard Shortcuts") {
                    openWelcomeToPage("05-Keyboard-Shortcuts.md")
                }
                
                Divider()
                
                Link("Report a Bug", destination: URL(string: "https://github.com")!)
            }
            
            // About menu
            CommandGroup(replacing: .appInfo) {
                Button("About AI.md Reader") {
                    openWelcomeToPage("01-Welcome.md")
                }
            }
        }
        #endif
    }

    // MARK: - Launch Logic

    /// Determines and executes the appropriate launch behavior
    private func performLaunchIfNeeded() {
        launchState = determineLaunchState()

        switch launchState {
        case .firstLaunch:
            performFirstLaunch()
        case .sessionRestore:
            performSessionRestore()
        case .minimalLauncher:
            // Already showing launcher, nothing to do
            break
        }
    }

    /// Determines what launch state the app should use
    private func determineLaunchState() -> LaunchState {
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: Self.hasLaunchedBeforeKey)

        if !hasLaunchedBefore {
            return .firstLaunch
        }

        // Check if we have a valid session to restore
        if let lastFolder = RecentFoldersManager.shared.lastSessionFolder(),
           let url = RecentFoldersManager.shared.resolveBookmark(lastFolder) {
            // Store for use in performSessionRestore
            appState.setRootFolder(url)
            return .sessionRestore
        }

        return .minimalLauncher
    }

    /// First launch: open Welcome folder and mark as launched
    private func performFirstLaunch() {
        // Ensure Welcome folder exists in Application Support (copy from bundle if needed)
        guard let welcomeURL = Self.ensureWelcomeFolder() else {
            // No welcome folder available, fall back to launcher
            UserDefaults.standard.set(true, forKey: Self.hasLaunchedBeforeKey)
            return
        }

        appState.setRootFolder(welcomeURL)
        appState.isFirstLaunchWelcome = true  // Flag to auto-select first file

        // Mark as launched
        UserDefaults.standard.set(true, forKey: Self.hasLaunchedBeforeKey)

        // Open browser window (StartView will handle the redirect)
    }

    /// Session restore: folder already set in determineLaunchState
    private func performSessionRestore() {
        // Folder is already set in appState by determineLaunchState
        // StartView will detect rootFolderURL and redirect to browser
    }

    #if os(macOS)
    // MARK: - Open Folder (macOS)

    private func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to browse markdown files"
        panel.prompt = "Choose"

        panel.begin { response in
            guard response == .OK, let folderURL = panel.url else { return }
            self.appState.setRootFolder(folderURL)
        }
    }
    
    // MARK: - Open Welcome Tutorial

    /// Opens the Welcome folder to a specific page
    /// Used for Help menu items and About screen
    private func openWelcomeToPage(_ fileName: String) {
        // Ensure Welcome folder exists in Application Support (copy from bundle if needed)
        guard let welcomeURL = Self.ensureWelcomeFolder() else {
            return
        }

        // Find the requested file
        let targetFile = welcomeURL.appendingPathComponent(fileName)

        // Verify file exists
        guard FileManager.default.fileExists(atPath: targetFile.path) else {
            // Fallback to opening the folder without file selection
            appState.setRootFolder(welcomeURL)
            return
        }

        // Open with file context
        appState.setRootFolder(welcomeURL)
        appState.selectFile(targetFile)

        // The browser window will automatically open via AppState changes
    }
    #endif
}

// MARK: - App State

/// Central application state.
@MainActor
@Observable
final class AppState {

    /// Root folder selected by user (nil until user selects one)
    var rootFolderURL: URL? = nil

    /// Currently selected file to view
    var selectedFile: URL? = nil

    /// Whether the AI Chat panel is visible
    var isAIChatVisible: Bool = false

    /// Whether the current file has unseen changes
    var fileHasChanges: Bool = false

    /// Flag for first-launch welcome (auto-select first file, auto-expand)
    var isFirstLaunchWelcome: Bool = false

    /// Reload trigger (incremented to force reload)
    var reloadTrigger: Int = 0

    /// Current document content (loaded from selectedFile)
    var documentContent: String = ""

    /// Initial question for chat (set from start screen, cleared after use)
    var initialChatQuestion: String? = nil

    // MARK: - Actions

    func setRootFolder(_ url: URL) {
        // Stop accessing previous folder if any
        rootFolderURL?.stopAccessingSecurityScopedResource()

        // Start accessing new folder's security scope
        // This grants access to the folder AND all its descendants
        _ = url.startAccessingSecurityScopedResource()

        rootFolderURL = url
        selectedFile = nil
        documentContent = ""
        fileHasChanges = false
    }

    func closeFolder() {
        // Stop accessing security-scoped resource if needed
        rootFolderURL?.stopAccessingSecurityScopedResource()

        rootFolderURL = nil
        selectedFile = nil
        documentContent = ""
        fileHasChanges = false
    }

    func selectFile(_ url: URL) {
        selectedFile = url
        fileHasChanges = false
    }

    func triggerReload() {
        reloadTrigger += 1
        fileHasChanges = false
    }

    func markFileChanged() {
        fileHasChanges = true
    }

    func clearChanges() {
        fileHasChanges = false
    }

    /// Open browser with a specific file selected and chat ready
    func openWithFileContext(fileURL: URL, question: String) {
        let parentFolder = fileURL.deletingLastPathComponent()

        // Stop accessing previous folder if any
        rootFolderURL?.stopAccessingSecurityScopedResource()

        // Start accessing new folder's security scope
        _ = parentFolder.startAccessingSecurityScopedResource()

        rootFolderURL = parentFolder
        selectedFile = fileURL
        initialChatQuestion = question
        isAIChatVisible = true
        fileHasChanges = false
    }
}
// MARK: - Color Scheme Preference Helper

extension View {
    func applyColorSchemePreference() -> some View {
        self.modifier(ColorSchemePreferenceModifier())
    }
}

struct ColorSchemePreferenceModifier: ViewModifier {
    @AppStorage("colorScheme") private var colorScheme: String = "system"
    
    func body(content: Content) -> some View {
        content.preferredColorScheme(preferredColorScheme)
    }
    
    private var preferredColorScheme: ColorScheme? {
        switch colorScheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

