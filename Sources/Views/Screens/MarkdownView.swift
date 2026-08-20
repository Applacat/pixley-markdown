import SwiftUI
import AppKit
import aimdRenderer
import MarkdownEngine

// MARK: - File Load Trigger

/// Combines file selection and reload trigger into a single equatable value.
/// Used with `.task(id:)` to avoid race conditions from separate task modifiers.
private struct FileLoadTrigger: Equatable {
    let file: URL?
    let reload: Int
}

// MARK: - Markdown View

/// The center panel: the swift-markdown-engine editor for BOTH view modes
/// (G4-P2). Enhanced = live styling, Plain = rawSourceMode — one substrate,
/// one write path. Reads document content from DocumentState (the single
/// source of truth); every keystroke routes into MarkdownDocument and the
/// debounced autosave; external changes arbitrate through
/// ExternalChangeArbiter (G3).
///
/// P2 scope notes: interactive elements render styled-but-inert until P3
/// (engine-native checkbox toggling works — it's a text edit through the
/// standard funnel). Gutter, bookmarks, comment indicators, and the
/// reading-progress badge return in P4.
struct MarkdownView: View {

    @Environment(\.coordinator) var coordinator
    @Environment(\.settings) private var settings

    @State var fileWatcher: FileWatcher? = nil
    @State var interactionHandler = InteractionHandler()

    // Gutter (G4-P4): line numbers + bookmark/comment indicators.
    @State private var gutter = GutterController()
    @State private var bookmarkedLines: Set<Int> = []
    @State private var commentedLines: Set<Int> = []
    @State private var readingProgress: Double = 0

    // MARK: - Body

    var body: some View {
        ZStack {
            if coordinator.navigation.selectedFile == nil {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            } else if coordinator.document.isLoading {
                loadingView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            } else if let error = coordinator.document.errorMessage {
                errorView(error)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            } else {
                markdownContent
            }

            // Clash pill (G3): same-region conflict needs a user decision
            if coordinator.document.externalClash != nil {
                VStack {
                    Spacer()
                    ClashPill(
                        onKeepMine: { resolveClash(takeTheirs: false) },
                        onTakeTheirs: { resolveClash(takeTheirs: true) }
                    )
                    .padding(.bottom, 20)
                }
            } else if coordinator.document.hasChanges {
                // Fallback reload pill: external change we couldn't arbitrate
                // (unreadable mid-write) — manual reload
                VStack {
                    Spacer()
                    ReloadPill {
                        coordinator.reloadDocument()
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: FileLoadTrigger(file: coordinator.navigation.selectedFile, reload: coordinator.document.reloadTrigger)) {
            await loadFile()
        }
    }

    // MARK: - Engine Editor (G4-P2)

    /// One engine view for both modes. The wrapper is NOT `.id()`-keyed on the
    /// file: the engine's `documentId` handles switching internally and keeps
    /// per-document undo stacks and scroll offsets alive across switches.
    private var markdownContent: some View {
        NativeTextViewWrapper(
            text: Binding(
                get: { coordinator.document.content },
                set: { newText in
                    let previous = coordinator.document.content
                    handleTextEdited(newText, previous: previous)
                }
            ),
            configuration: MarkdownEditorConfiguration(
                services: MarkdownEditorServices(
                    syntaxHighlighter: PixleyCodeHighlighter(
                        palette: settings.rendering.syntaxTheme
                            .rendererTheme(for: settings.appearance.colorScheme).palette,
                        fontSize: CGFloat(settings.rendering.fontSize))),
                leftContentInset: PixleyGutterView.width,
                rawSourceMode: settings.behavior.interactiveMode == .plain,
                extensions: []
            ),
            fontSize: CGFloat(settings.rendering.fontSize),
            documentId: coordinator.navigation.selectedFile?.path ?? "no-document",
            isEditable: true,
            onBuildContextMenu: { menu, selection in
                buildContextMenu(menu, selection: selection)
            },
            onPersistScrollOffset: { path, offset in
                coordinator.persistEditorScroll(Double(offset), path: path)
            },
            restoreScrollOffset: { path in
                coordinator.restoredEditorScroll(path: path).map { CGFloat($0) }
            },
            onInteractiveOverlay: { storage, range in
                PixleyElementStyler.overlay(storage: storage, range: range)
            },
            onInteractiveElementClick: { identifier, windowRect in
                handleElementClick(identifier, windowRect: windowRect)
            },
            onScrollViewReady: { scrollView, textView in
                gutter.install(on: scrollView, textView: textView) { line in
                    toggleBookmark(at: line)
                }
                gutter.update(bookmarked: bookmarkedLines, commented: commentedLines)
                gutter.onProgress = { progress in readingProgress = progress }
            }
        )
        .overlay(alignment: .topTrailing) {
            ReadingProgressBadge(progress: readingProgress)
                .padding(8)
        }
        .background {
            // ⌘S forces an immediate save of the live document (US-2.3)
            Button("") { forceSave() }
                .keyboardShortcut("s", modifiers: .command)
                .hidden()
            // ⌘G go-to-line (US-P4.2)
            Button("") { presentGoToLine() }
                .keyboardShortcut("g", modifiers: .command)
                .hidden()
        }
        .onChange(of: bookmarkedLines) { gutter.update(bookmarked: bookmarkedLines, commented: commentedLines) }
        .onChange(of: commentedLines) { gutter.update(bookmarked: bookmarkedLines, commented: commentedLines) }
    }

    // MARK: - Bookmarks & Comments (G4-P4)

    /// Adds an "Add Comment…" item to the editor's right-click menu (US-P4.2).
    private func buildContextMenu(_ menu: NSMenu, selection: NSRange) -> NSMenu {
        let item = NSMenuItem(title: "Add Comment…", action: nil, keyEquivalent: "")
        item.target = CommentMenuTarget.shared
        item.action = #selector(CommentMenuTarget.add(_:))
        CommentMenuTarget.shared.onAdd = { addCommentAtCaret(selection: selection) }
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }

    private func addCommentAtCaret(selection: NSRange) {
        guard let url = coordinator.navigation.selectedFile else { return }
        let text = coordinator.document.content
        let ns = text as NSString
        // 1-based line number of the selection/caret location.
        var line = 1
        ns.enumerateSubstrings(in: NSRange(location: 0, length: min(selection.location, ns.length)),
                               options: [.byLines, .substringNotRequired]) { _, _, _, _ in line += 1 }

        let alert = NSAlert()
        alert.messageText = "Add Comment"
        alert.informativeText = "Attach a note to line \(line)."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return }

        let commentText = field.stringValue
        let handler = interactionHandler, watcher = fileWatcher
        Task { @MainActor in
            do {
                try await handler.setGutterComment(
                    lineNumber: line, commentText: commentText,
                    displayedContent: text, in: url, fileWatcher: watcher
                ) { newContent in
                    coordinator.updateDocumentContent(newContent)
                    refreshCommentedLines(in: newContent)
                }
            } catch {
                coordinator.showError(.error(message: error.localizedDescription))
            }
        }
    }

    private func toggleBookmark(at line: Int) {
        let existing = coordinator.getBookmarks()
        if let bookmark = existing.first(where: { $0.lineNumber == line }) {
            coordinator.deleteBookmark(bookmark.id)
        } else {
            coordinator.addBookmark(lineNumber: line)
        }
        bookmarkedLines = Set(coordinator.getBookmarks().map(\.lineNumber))
    }

    private func refreshBookmarks() {
        bookmarkedLines = Set(coordinator.getBookmarks().map(\.lineNumber))
    }

    /// Scans for `<!-- feedback -->` and CriticMarkup highlight comments,
    /// mapping them to 1-based line numbers for gutter indicators.
    func refreshCommentedLines(in content: String) {
        var result: Set<Int> = []
        for (index, line) in content.components(separatedBy: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("<!-- feedback") && trimmed.hasSuffix("-->") && index > 0 {
                result.insert(index) // the line BEFORE the comment
            }
            if line.contains("{==") && line.contains("{>>") {
                result.insert(index + 1)
            }
        }
        commentedLines = result
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle.weight(.light))
                .imageScale(.large)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text("Select a file to view")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Choose a markdown file from the sidebar")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding()
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView("Loading...")
            Spacer()
        }
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle.weight(.light))
                .imageScale(.large)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Error loading file")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    // MARK: - Editing (G2/G4)

    /// Routes an edit into the document model and schedules the debounced
    /// autosave. `previous` is the editor's pre-edit text: if it no longer
    /// matches the model, an external merge landed in the window before the
    /// editor displayed it — fold the keystroke into the merged text instead
    /// of clobbering it (G3). On a same-region collision within that window
    /// the keystroke wins (guardrail 1), accepting loss of the colliding
    /// external region.
    private func handleTextEdited(_ newText: String, previous: String) {
        guard let url = coordinator.navigation.selectedFile else { return }
        let document = MarkdownDocumentRegistry.obtain(url: url, initialSource: newText)
        if previous != document.source, document.source != newText,
           case .merged(let folded) = ThreeWayMerge.merge(
               base: previous, mine: newText, theirs: document.source) {
            document.update(source: folded)
        } else {
            document.update(source: newText)
        }
        coordinator.updateDocumentContent(document.source)
        refreshCommentedLines(in: document.source)
        SaveCoordinator.shared.scheduleSave(for: document, fileWatcher: fileWatcher)
    }

    private func forceSave() {
        guard let url = coordinator.navigation.selectedFile else { return }
        guard coordinator.document.externalClash == nil else {
            coordinator.showError(.error(
                message: "Resolve the conflicting external changes first (Keep Mine / Take Theirs)."))
            return
        }
        let document = MarkdownDocumentRegistry.obtain(url: url, initialSource: coordinator.document.content)
        Task {
            do {
                try await SaveCoordinator.shared.saveNow(document, fileWatcher: fileWatcher)
            } catch {
                coordinator.showError(.error(message: error.localizedDescription))
            }
        }
    }

    // MARK: - Load File

    /// Delegates file loading to DocumentState (the single source of truth),
    /// then starts watching for external changes.
    private func loadFile() async {
        guard let fileURL = coordinator.navigation.selectedFile else { return }
        await coordinator.loadDocument()
        if coordinator.document.errorMessage == nil {
            startWatching(fileURL)
            refreshBookmarks()
            refreshCommentedLines(in: coordinator.document.content)
        }
    }

    // MARK: - Go To Line (⌘G, US-P4.2)

    private func presentGoToLine() {
        let alert = NSAlert()
        alert.messageText = "Go to Line"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = "Line number"
        alert.accessoryView = field
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, let line = Int(field.stringValue), line > 0 else { return }
        scrollToLine(line)
    }

    private func scrollToLine(_ line: Int) {
        guard let window = NSApp.keyWindow,
              let textView = firstTextView(in: window.contentView) else { return }
        let ns = textView.string as NSString
        var current = 1, location = 0
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length),
                               options: [.byLines, .substringNotRequired]) { _, lineRange, _, stop in
            if current == line { location = lineRange.location; stop.pointee = true }
            current += 1
        }
        textView.scrollRangeToVisible(NSRange(location: min(location, ns.length), length: 0))
        textView.setSelectedRange(NSRange(location: min(location, ns.length), length: 0))
        window.makeFirstResponder(textView)
    }

    private func firstTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let tv = view as? NSTextView { return tv }
        for sub in view.subviews {
            if let found = firstTextView(in: sub) { return found }
        }
        return nil
    }

    // MARK: - External Changes (G3)

    /// The watched file changed under us. Clean documents silently reload,
    /// dirty documents 3-way merge (D7), and same-region clashes raise the
    /// keep-mine / take-theirs pill — never a silent overwrite in either
    /// direction.
    private func handleExternalChange() {
        guard let url = coordinator.navigation.selectedFile else { return }
        Task { @MainActor in
            guard let diskContent = try? String(contentsOf: url, encoding: .utf8) else {
                // Unreadable (mid-write, encoding, gone) — fall back to the
                // manual reload pill rather than guessing.
                coordinator.markDocumentChanged()
                return
            }
            let document = MarkdownDocumentRegistry.obtain(
                url: url, initialSource: coordinator.document.content)
            switch ExternalChangeArbiter.arbitrate(document: document, diskContent: diskContent) {
            case .noChange:
                break
            case .reloaded:
                coordinator.updateDocumentContent(document.source)
            case .merged:
                coordinator.updateDocumentContent(document.source)
                SaveCoordinator.shared.scheduleSave(for: document, fileWatcher: fileWatcher)
            case .clash(let theirs):
                // Hold the debounced autosave — it must not decide the clash
                SaveCoordinator.shared.cancelPendingSave(for: document)
                coordinator.document.raiseClash(theirs: theirs)
            }
        }
    }

    /// Clash pill resolution (G3, US-3.2).
    private func resolveClash(takeTheirs: Bool) {
        guard let url = coordinator.navigation.selectedFile,
              let theirs = coordinator.document.externalClash else {
            coordinator.document.clearClash()
            return
        }
        let document = MarkdownDocumentRegistry.obtain(
            url: url, initialSource: coordinator.document.content)
        if takeTheirs {
            ExternalChangeArbiter.takeTheirs(document: document, theirs: theirs)
            coordinator.updateDocumentContent(document.source)
        } else {
            ExternalChangeArbiter.keepMine(document: document, theirs: theirs)
            SaveCoordinator.shared.scheduleSave(for: document, fileWatcher: fileWatcher)
        }
        coordinator.document.clearClash()
    }

    // MARK: - File Watching

    private func startWatching(_ url: URL) {
        if fileWatcher == nil {
            fileWatcher = FileWatcher {
                handleExternalChange()
            }
        }
        fileWatcher?.watch(url)
        // Expose to other write paths (AI chat edits) for suppression
        coordinator.activeFileWatcher = fileWatcher
    }
}

// MARK: - Reload Pill

/// Floating pill showing "Content updated" with a Reload button.
struct ReloadPill: View {

    let onReload: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.clockwise")
                .font(.callout.weight(.medium))
                .accessibilityHidden(true)

            Text("Content updated")
                .font(.callout)

            Button("Reload") {
                onReload()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 4, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Content updated. Reload to see changes.")
    }
}

// MARK: - Clash Pill (G3)

/// Floating pill for same-region external-change clashes: the user's unsaved
/// text and the external content both touched the same region — the user
/// picks a side (D7). Nothing is applied until they do.
struct ClashPill: View {

    let onKeepMine: () -> Void
    let onTakeTheirs: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.callout.weight(.medium))
                .accessibilityHidden(true)

            Text("Conflicting changes")
                .font(.callout)

            Button("Keep Mine") {
                onKeepMine()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("Take Theirs") {
                onTakeTheirs()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.orange.opacity(0.5), lineWidth: 1))
        .shadow(radius: 4, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Conflicting external changes. Choose Keep Mine or Take Theirs.")
    }
}

// MARK: - Comment menu target (NSMenu needs an ObjC target)

@MainActor
private final class CommentMenuTarget: NSObject {
    static let shared = CommentMenuTarget()
    var onAdd: (() -> Void)?
    @objc func add(_ sender: NSMenuItem) { onAdd?() }
}

// MARK: - Reading Progress Badge (G4-P4)

/// Small overlay showing how far through the document the reader has scrolled.
struct ReadingProgressBadge: View {
    let progress: Double

    var body: some View {
        if progress > 0.001 {
            Text("\(Int((progress * 100).rounded()))%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.regularMaterial, in: Capsule())
                .accessibilityLabel("Reading progress \(Int((progress * 100).rounded())) percent")
        }
    }
}
