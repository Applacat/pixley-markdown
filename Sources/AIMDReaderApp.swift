import SwiftUI
import SwiftData
import UniformTypeIdentifiers

#if os(macOS)
// MARK: - App Delegate

/// Handles file/folder opens from Finder (double-click, "Open With", drag to Dock icon).
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply saved mascot direction to Dock icon
        let direction = UserDefaultsSettingsRepository.shared.appearance.mascotDirection
        if let image = NSImage(named: direction.assetName) {
            NSApp.applicationIconImage = image
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        CoordinatorRegistry.shared.flushAll()
        FolderService.shared.flushCacheIfNeeded()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }

        if isDirectory.boolValue {
            RecentFoldersManager.shared.addFolder(url)
            let request = BrowserOpenRequest(folderURL: url)
            WindowRouter.shared.openBrowser(request)
        } else {
            let ext = url.pathExtension.lowercased()
            guard ext == "md" || ext == "markdown" else { return }
            openMarkdownFileWithFolderAccess(url)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    private func openMarkdownFileWithFolderAccess(_ fileURL: URL) {
        let parentFolder = fileURL.deletingLastPathComponent()
        let parentPath = parentFolder.path

        // Check for a saved bookmark
        if let savedFolder = RecentFoldersManager.shared.getRecentFolders()
            .first(where: { $0.path == parentPath }),
           let resolvedURL = RecentFoldersManager.shared.resolveBookmark(savedFolder) {
            let request = BrowserOpenRequest(
                folderURL: resolvedURL,
                fileURL: fileURL,
                preferSidebarCollapsed: true
            )
            WindowRouter.shared.openBrowser(request)
            return
        }

        // No bookmark — ask for folder access
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = parentFolder
        panel.message = "Grant access to this folder to browse its contents"
        panel.prompt = "Open"

        panel.begin { @MainActor response in
            guard response == .OK, let grantedURL = panel.url else { return }
            RecentFoldersManager.shared.addFolder(grantedURL)
            let request = BrowserOpenRequest(
                folderURL: grantedURL,
                fileURL: fileURL,
                preferSidebarCollapsed: true
            )
            WindowRouter.shared.openBrowser(request)
        }
    }
}
#endif

// MARK: - App Entry Point

@main
struct PixleyMarkdownApp: App {

    // MARK: - Constants

    static let hasLaunchedBeforeKey = "hasLaunchedBefore"

    // MARK: - State

    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @FocusedValue(\.activeCoordinator) private var activeCoordinator

    /// Settings repository — injected into Environment for all views
    private let settings = UserDefaultsSettingsRepository.shared

    /// SwiftData container for file metadata persistence
    private let modelContainer: ModelContainer

    // MARK: - Initialization

    init() {
        do {
            modelContainer = try MetadataContainerConfiguration.makeContainer()
        } catch {
            fatalError("Failed to initialize SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        #if os(macOS)
        // Start window - minimal launcher (macOS uses single Window)
        Window("Pixley Markdown", id: "start") {
            StartView()
                .environment(\.settings, settings)
                .modelContainer(modelContainer)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
        .defaultLaunchBehavior(.presented)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)
        #else
        // iOS uses WindowGroup
        WindowGroup("Pixley Markdown", id: "start") {
            StartView()
                .environment(\.settings, settings)
                .modelContainer(modelContainer)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
        #endif

        // Browser window — per-window coordinator via BrowserWindowRoot
        WindowGroup("Pixley Markdown", id: "browser", for: BrowserOpenRequest.self) { $request in
            BrowserWindowRoot(request: request)
                .environment(\.settings, settings)
                .modelContainer(modelContainer)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
        #if os(macOS)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    openStartWindow()
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("Open File...") {
                    openFilePanelForNewWindow()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Open Folder...") {
                    openFolderPanelForNewWindow()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                // Open Recent submenu
                Menu("Open Recent") {
                    let recents = RecentFoldersManager.shared.getAllRecents()
                    if recents.isEmpty {
                        Text("No Recent Items")
                    } else {
                        ForEach(recents) { item in
                            Button {
                                openRecentItem(item)
                            } label: {
                                Label(item.name, systemImage: item.isFolder ? "folder" : "doc.text")
                            }
                        }

                        Divider()

                        Button("Clear Menu") {
                            RecentFoldersManager.shared.clearAll()
                        }
                    }
                }

                Divider()

                Button("Reload") {
                    activeCoordinator?.reloadDocument()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(activeCoordinator?.navigation.selectedFile == nil)

                Button("Close Folder") {
                    activeCoordinator?.closeFolder()
                }
                .keyboardShortcut("w", modifiers: [.command])
                .disabled(activeCoordinator?.navigation.rootFolderURL == nil)
            }

            CommandGroup(after: .textEditing) {
                Button("Go to File...") {
                    activeCoordinator?.toggleQuickSwitcher()
                }
                .keyboardShortcut("p", modifiers: [.command])
                .disabled(activeCoordinator == nil)
            }

            // Find menu
            CommandGroup(after: .textEditing) {
                Button("Find...") {
                    Self.sendFindPanelAction(NSTextFinder.Action.showFindInterface.rawValue)
                }
                .keyboardShortcut("f", modifiers: [.command])

                Button("Find Next") {
                    Self.sendFindPanelAction(NSTextFinder.Action.nextMatch.rawValue)
                }
                .keyboardShortcut("g", modifiers: [.command])

                Button("Find Previous") {
                    Self.sendFindPanelAction(NSTextFinder.Action.previousMatch.rawValue)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            }

            // Navigate menu — interactive element navigation
            CommandGroup(before: .toolbar) {
                Button("Next Interactive Element") {
                    Self.sendNavigateAction(forward: true)
                }
                .keyboardShortcut("]", modifiers: [.command])
                .disabled(activeCoordinator?.navigation.selectedFile == nil)

                Button("Previous Interactive Element") {
                    Self.sendNavigateAction(forward: false)
                }
                .keyboardShortcut("[", modifiers: [.command])
                .disabled(activeCoordinator?.navigation.selectedFile == nil)
            }

            // View menu — font size + Pixley Chat toggle
            CommandGroup(after: .toolbar) {
                if #available(macOS 26, *) {
                    Button(activeCoordinator?.ui.isAIChatVisible == true ? "Hide Pixley Chat" : "Show Pixley Chat") {
                        withAnimation {
                            activeCoordinator?.toggleAIChat()
                        }
                    }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(activeCoordinator == nil)

                    Divider()
                }

                Button("Increase Font Size") {
                    settings.rendering.fontSize = min(32, settings.rendering.fontSize + 1)
                }
                .keyboardShortcut("=", modifiers: [.command])

                Button("Decrease Font Size") {
                    settings.rendering.fontSize = max(10, settings.rendering.fontSize - 1)
                }
                .keyboardShortcut("-", modifiers: [.command])
            }

            // Help menu
            CommandGroup(replacing: .help) {
                Button("Pixley Markdown Help") {
                    openWelcomeToPage("01-Welcome.md")
                }
                .keyboardShortcut("/", modifiers: [.command])

                Button("Reading & Browsing") {
                    openWelcomeToPage("02-Reading-and-Browsing.md")
                }

                Button("Interactive Controls") {
                    openWelcomeToPage("03-Interactive-Controls.md")
                }

                if #available(macOS 26, *) {
                    Button("AI Chat") {
                        openWelcomeToPage("04-AI-Chat.md")
                    }
                }

                Button("Quick Reference") {
                    openWelcomeToPage("05-Quick-Reference.md")
                }

                Divider()

                Link("Report a Bug", destination: URL(string: "https://github.com")!)
            }

            // About menu
            CommandGroup(replacing: .appInfo) {
                Button("About Pixley Markdown") {
                    showAboutPanel()
                }
            }
        }
        #endif

        #if os(macOS)
        // Settings window (Cmd+,)
        Settings {
            SettingsView()
                .environment(\.settings, settings)
        }
        #endif
    }

    // MARK: - Find Panel

    #if os(macOS)
    private static func sendFindPanelAction(_ tag: Int) {
        let menuItem = NSMenuItem()
        menuItem.tag = tag

        if let window = NSApp.keyWindow,
           let textView = findMarkdownTextView(in: window.contentView) {
            window.makeFirstResponder(textView)
            textView.performFindPanelAction(menuItem)
        }
    }

    private static func sendNavigateAction(forward: Bool) {
        if let window = NSApp.keyWindow,
           let textView = findMarkdownTextView(in: window.contentView) as? MarkdownNSTextView {
            window.makeFirstResponder(textView)
            textView.navigateToElement(forward: forward)
        }
    }

    private static func findMarkdownTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? NSTextView, textView.usesFindBar {
            return textView
        }
        for subview in view.subviews {
            if let found = findMarkdownTextView(in: subview) {
                return found
            }
        }
        return nil
    }

    // MARK: - Open Recent Item

    private func openRecentItem(_ item: RecentItem) {
        guard let request = RecentFoldersManager.shared.resolveRecentItem(item) else { return }
        WindowRouter.shared.openBrowser(request)
    }

    // MARK: - Window Management

    private func openStartWindow() {
        // Show (or activate) the start window with the mascot launcher
        if let startWindow = NSApp.windows.first(where: {
            $0.identifier?.rawValue.contains("start") == true && $0.isVisible
        }) {
            startWindow.makeKeyAndOrderFront(nil)
        } else {
            WindowRouter.shared.openWindowAction?(id: "start")
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openFilePanelForNewWindow() {
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
            WindowRouter.shared.openBrowser(BrowserOpenRequest(
                folderURL: folderURL,
                fileURL: fileURL,
                preferSidebarCollapsed: true
            ))
        }
    }

    private func openFolderPanelForNewWindow() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to browse markdown files"
        panel.prompt = "Choose"

        panel.begin { @MainActor response in
            guard response == .OK, let folderURL = panel.url else { return }
            RecentFoldersManager.shared.addFolder(folderURL)
            WindowRouter.shared.openBrowser(BrowserOpenRequest(folderURL: folderURL))
        }
    }

    // MARK: - About Panel

    private func showAboutPanel() {
        let credits = NSMutableAttributedString()

        let bodyFont = NSFont.systemFont(ofSize: 11)
        let boldFont = NSFont.boldSystemFont(ofSize: 11)
        let bodyColor = NSColor.secondaryLabelColor
        let headingColor = NSColor.labelColor

        let bodyAttrs: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: bodyColor]
        let headingAttrs: [NSAttributedString.Key: Any] = [.font: boldFont, .foregroundColor: headingColor]

        credits.append(NSAttributedString(string: "Syntax Theme Color Schemes\n", attributes: headingAttrs))
        credits.append(NSAttributedString(string: "Used under MIT License\n\n", attributes: bodyAttrs))

        let themes: [(String, String)] = [
            ("Solarized", "Ethan Schoonover"),
            ("Dracula", "Zeno Rocha"),
            ("Monokai", "Wimer Hazenberg"),
            ("Nord", "Arctic Ice Studio"),
            ("One Dark", "Atom / GitHub"),
            ("GitHub", "GitHub Primer"),
        ]

        for (name, author) in themes {
            credits.append(NSAttributedString(string: "\(name)", attributes: headingAttrs))
            credits.append(NSAttributedString(string: " by \(author)\n", attributes: bodyAttrs))
        }

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.paragraphSpacing = 2
        credits.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: credits.length))

        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits
        ])
    }

    // MARK: - Open Welcome Tutorial

    private func openWelcomeToPage(_ fileName: String) {
        guard let welcomeURL = WelcomeManager.ensureWelcomeFolder() else { return }
        let targetFile = welcomeURL.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: targetFile.path) else {
            WindowRouter.shared.openBrowser(BrowserOpenRequest(folderURL: welcomeURL))
            return
        }
        WindowRouter.shared.openBrowser(BrowserOpenRequest(
            folderURL: welcomeURL,
            fileURL: targetFile
        ))
    }

    #endif
}
