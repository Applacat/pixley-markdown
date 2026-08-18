import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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

        // G4 runtime AC harness — the swift-markdown-engine editor (both
        // modes). Delegate hook fires even when the app launches inactive
        // from the CLI (scene .task does not). STRESS-PLAIN retired with the
        // old editor in P2; STRESS-ENGINE runs the same checks and more.
        if EngineStressHarness.isRequested {
            NSApp.activate(ignoringOtherApps: true)
            Task { await EngineStressHarness.run() }
        }

        // Debug: open a seeded sample doc through the REAL browser flow, then
        // snapshot the window + dump gutter diagnostics. Verifies the gutter
        // in the actual split-view context the harness can't reproduce.
        if CommandLine.arguments.contains("--open-sample") {
            NSApp.activate(ignoringOtherApps: true)
            Task { await Self.openSampleAndSnapshot() }
        }
    }

    private static func openSampleAndSnapshot() async {
        // Give the start scene time to appear and set openWindowAction.
        try? await Task.sleep(for: .seconds(2))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sample-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("sample.md")
        let body = (1...20).map { "Line \($0): some prose to fill the document." }.joined(separator: "\n\n") + "\n"
        try? body.write(to: file, atomically: true, encoding: .utf8)
        WindowRouter.shared.openBrowser(BrowserOpenRequest(folderURL: dir, fileURL: file, preferSidebarCollapsed: true))
        try? await Task.sleep(for: .seconds(3)) // browser window + MarkdownView + gutter install
        // The browser window is the largest visible one (start launcher is smaller).
        let browser = NSApp.windows
            .filter { $0.isVisible && $0.contentView != nil }
            .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
        if let window = browser,
           let view = window.contentView,
           let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                let path = FileManager.default.temporaryDirectory.appendingPathComponent("real-app-shot.png")
                try? png.write(to: path)
                print("REAL-APP-SHOT \(path.path)")
            }
        }
        print("OPEN-SAMPLE DONE")
        exit(0)
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

// MARK: - App Entry Point

@main
struct PixleyMarkdownApp: App {

    // MARK: - Constants

    static let hasLaunchedBeforeKey = "hasLaunchedBefore"

    // MARK: - State

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
        // Start window - minimal launcher
        Window("Pixley Markdown", id: "start") {
            StartView()
                .environment(\.settings, settings)
                .modelContainer(modelContainer)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
        #if os(macOS)
        .defaultLaunchBehavior(.presented)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)
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

            // Navigate menu (interactive element ⌘]/⌘[ navigation) returns in
            // G4-P3 with the engine's element hit-test seam.

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

        // Settings window (Cmd+,)
        Settings {
            SettingsView()
                .environment(\.settings, settings)
        }
    }

    // MARK: - Find Panel

    #if os(macOS)
    private static func sendFindPanelAction(_ tag: Int) {
        let menuItem = NSMenuItem()
        menuItem.tag = tag

        if let window = NSApp.keyWindow,
           let textView = findMarkdownTextView(in: window.contentView) {
            // The engine's text view doesn't opt into the find bar itself;
            // AppKit's incremental find bar works on any NSTextView (G4-P2).
            textView.usesFindBar = true
            window.makeFirstResponder(textView)
            textView.performFindPanelAction(menuItem)
        }
    }

    private static func findMarkdownTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? NSTextView, textView.isSelectable {
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
