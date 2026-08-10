import SwiftUI
import AppKit
import aimdRenderer

// MARK: - File Load Trigger

/// Combines file selection and reload trigger into a single equatable value.
/// Used with `.task(id:)` to avoid race conditions from separate task modifiers.
private struct FileLoadTrigger: Equatable {
    let file: URL?
    let reload: Int
}

// MARK: - Markdown View

/// The center panel displaying markdown content with syntax highlighting.
/// Reads document content from DocumentState (the single source of truth).
struct MarkdownView: View {

    @Environment(\.coordinator) private var coordinator
    @Environment(\.settings) private var settings

    @State private var pendingScrollPosition: Double? = nil
    @State private var fileWatcher: FileWatcher? = nil
    @State private var readingProgress: Double = 0
    @State private var bookmarkedLines: Set<Int> = []
    @State private var commentedLines: Set<Int> = []
    @State private var interactionHandler = InteractionHandler()
    @State private var interactionTask: Task<Void, Never>?

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
                // No SwiftUI background — NSTextView draws its own
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

    // MARK: - Markdown Content

    @ViewBuilder
    private var markdownContent: some View {
        switch settings.behavior.interactiveMode {
        case .enhanced:
            nativeRendererContent
        case .plain:
            plainEditorContent
        }
    }

    private var plainEditorContent: some View {
        MarkdownEditor(
            text: .constant(coordinator.document.content),
            onError: { error in coordinator.showError(error) },
            onScrollPositionChanged: { position in
                readingProgress = position
                coordinator.saveScrollPosition(position)
            },
            restoreScrollPosition: pendingScrollPosition,
            bookmarkedLines: bookmarkedLines,
            onToggleBookmark: { lineNumber in
                toggleBookmark(at: lineNumber)
            },
            commentedLines: commentedLines,
            onGutterAction: { lineNumber, shouldBookmark, commentText in
                handleGutterAction(lineNumber: lineNumber, shouldBookmark: shouldBookmark, commentText: commentText)
            },
            onInteractiveElementClicked: { element, optionIndex, point in
                handleInteractiveClick(element, optionIndex: optionIndex)
            },
            onStatusSelected: { status, state in
                submitStatusAdvance(status: status, to: state)
            },
            onInputSubmitted: { element, optionIndex, fieldName, value in
                handleInputSubmitted(element, optionIndex: optionIndex, fieldName: fieldName, value: value)
            },
            onAddComment: { selectedText, nsRange in
                handleAddComment(selectedText: selectedText, nsRange: nsRange)
            },
            onTextEdited: { newText, previousText in
                handleTextEdited(newText, previous: previousText)
            }
        )
        .overlay(alignment: .topTrailing) {
            if coordinator.navigation.selectedFile != nil {
                ReadingProgressBadge(progress: readingProgress)
                    .padding(8)
            }
        }
        .background {
            // ⌘S forces an immediate save of the live document (US-2.3)
            Button("") { forceSave() }
                .keyboardShortcut("s", modifiers: .command)
                .hidden()
        }
    }

    // MARK: - Editing (G2)

    /// Routes a Plain-mode edit into the document model and schedules the
    /// debounced autosave. DocumentState stays in sync so Enhanced mode and
    /// chat see the same content.
    ///
    /// `previous` is the editor's pre-edit text. If it no longer matches the
    /// model, an external merge landed in the one-runloop window before the
    /// editor could display it — fold the keystroke into the merged text
    /// instead of clobbering it (G3 review fix). On a same-region collision
    /// within that window the keystroke wins (guardrail 1: never lose a
    /// keystroke), accepting loss of the colliding external region.
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

    private var nativeRendererContent: some View {
        let palette = settings.rendering.syntaxTheme
            .rendererTheme(for: settings.appearance.colorScheme)
            .palette
        return NativeDocumentView(
            content: coordinator.document.content,
            palette: palette,
            fontSize: settings.rendering.fontSize,
            bookmarkedLines: bookmarkedLines,
            commentedLines: commentedLines,
            onInteractiveElementChanged: { element, optionIndex, fieldName, value in
                handleInputSubmitted(element, optionIndex: optionIndex, fieldName: fieldName, value: value)
            },
            onInteractiveElementClicked: { element, optionIndex in
                handleInteractiveClick(element, optionIndex: optionIndex)
            },
            onStatusSelected: { status, state in
                submitStatusAdvance(status: status, to: state)
            },
            onToggleBookmark: { lineNumber in
                toggleBookmark(at: lineNumber)
            },
            onAddComment: { lineNumber, commentText in
                handleGutterAction(lineNumber: lineNumber, shouldBookmark: false, commentText: commentText)
            },
            onScrollProgressChanged: { progress in
                readingProgress = progress
                coordinator.saveScrollPosition(progress)
            },
            restoreScrollProgress: pendingScrollPosition
        )
        // Fresh view state (scroll restore, search, parse cache) per document
        .id(coordinator.navigation.selectedFile)
    }

    // MARK: - Load File

    /// Delegates file loading to DocumentState (the single source of truth).
    /// MarkdownView handles view-level concerns: scroll restoration, bookmarks, file watching.
    private func loadFile() async {
        guard let fileURL = coordinator.navigation.selectedFile else {
            pendingScrollPosition = nil
            return
        }

        // Look up saved scroll position before loading
        let savedPosition = coordinator.getScrollPosition(for: fileURL)

        // Delegate loading to coordinator (DocumentState owns the content)
        await coordinator.loadDocument()

        // View-level concerns after successful load
        if coordinator.document.errorMessage == nil {
            pendingScrollPosition = savedPosition > 0 ? savedPosition : nil
            refreshBookmarks()
            refreshCommentedLines(in: coordinator.document.content)
            startWatching(fileURL)
            
            // Clear pending scroll position after a brief delay to prevent it from
            // being re-applied during subsequent content updates (interactive edits).
            // The MarkdownEditor will have already consumed it by this point.
            if pendingScrollPosition != nil {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    pendingScrollPosition = nil
                }
            }
        }
    }

    // MARK: - Bookmarks

    private func toggleBookmark(at lineNumber: Int) {
        let existing = coordinator.getBookmarks()
        if let bookmark = existing.first(where: { $0.lineNumber == lineNumber }) {
            coordinator.deleteBookmark(bookmark.id)
        } else {
            coordinator.addBookmark(lineNumber: lineNumber)
        }
        // Fetch bookmarks once after mutation (avoids double-fetch via refreshBookmarks)
        let updated = coordinator.getBookmarks()
        bookmarkedLines = Set(updated.map(\.lineNumber))
    }

    private func refreshBookmarks() {
        let bookmarks = coordinator.getBookmarks()
        bookmarkedLines = Set(bookmarks.map(\.lineNumber))
    }

    // MARK: - Gutter Comments

    /// Handles gutter popover submissions: bookmark toggle + comment write/remove.
    private func handleGutterAction(lineNumber: Int, shouldBookmark: Bool, commentText: String?) {
        guard let fileURL = coordinator.navigation.selectedFile else { return }

        Task {
            do {
                try await interactionHandler.setGutterComment(
                    lineNumber: lineNumber,
                    commentText: commentText,
                    displayedContent: coordinator.document.content,
                    in: fileURL,
                    fileWatcher: fileWatcher
                ) { newContent in
                    coordinator.updateDocumentContent(newContent)
                    refreshCommentedLines(in: newContent)
                }
            } catch {
                coordinator.showError(.error(message: error.localizedDescription))
            }
        }
    }

    /// Scans content for `<!-- feedback -->` tags and CriticMarkup highlight comments,
    /// mapping them to line numbers for gutter indicators.
    private func refreshCommentedLines(in content: String) {
        var result: Set<Int> = []
        let lines = content.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // HTML feedback comments: indicate the preceding line
            if trimmed.hasPrefix("<!-- feedback") && trimmed.hasSuffix("-->") && index > 0 {
                result.insert(index) // 1-based line number of the line BEFORE the comment
            }
            // CriticMarkup highlight comments: {==text==}{>>comment<<}
            if line.contains("{==") && line.contains("{>>") {
                result.insert(index + 1) // 1-based line number
            }
        }
        commentedLines = result
    }

    // MARK: - Interactive Element Handling (Direct Actions)

    /// Handles direct-action clicks (checkbox toggle, choice select, etc.).
    /// Popover-based interactions (fill-in, feedback, suggestion, etc.) are routed
    /// through showElementPopover in MarkdownNSTextView → onInputSubmitted.
    private func handleInteractiveClick(_ element: InteractiveElement, optionIndex: Int? = nil) {
        guard let fileURL = coordinator.navigation.selectedFile else { return }
        let content = coordinator.document.content

        interactionTask?.cancel()
        interactionTask = Task {
            do {
                switch element {
                case .checkbox(let cb):
                    try await interactionHandler.toggleCheckbox(
                        cb, displayedContent: content, in: fileURL, fileWatcher: fileWatcher
                    ) { newContent in
                        coordinator.updateDocumentContent(newContent)
                    }

                case .choice(let ch):
                    try await interactionHandler.selectChoice(
                        optionIndex: optionIndex ?? 0, in: ch, displayedContent: content, url: fileURL, fileWatcher: fileWatcher
                    ) { newContent in
                        coordinator.updateDocumentContent(newContent)
                    }

                case .review(let rv):
                    // Only non-notes options reach here (notes options are handled by popover)
                    let idx = optionIndex ?? 0
                    if idx < rv.options.count && rv.options[idx].isSelected {
                        // Already selected — deselect (clear all)
                        try await interactionHandler.clearReview(
                            in: rv, displayedContent: content, url: fileURL, fileWatcher: fileWatcher
                        ) { newContent in
                            coordinator.updateDocumentContent(newContent)
                        }
                    } else {
                        try await interactionHandler.selectReview(
                            optionIndex: idx, in: rv, displayedContent: content, url: fileURL, fileWatcher: fileWatcher
                        ) { newContent in
                            coordinator.updateDocumentContent(newContent)
                        }
                    }

                case .fillIn(let fi):
                    // Only file/folder pickers reach here (text/date handled by popover)
                    switch fi.type {
                    case .file: openFilePicker(for: fi)
                    case .folder: openFolderPicker(for: fi)
                    default: break
                    }

                case .status(let st):
                    if let nextState = st.nextStates.first, st.nextStates.count == 1 {
                        try await interactionHandler.advanceStatus(
                            st, to: nextState, displayedContent: content, in: fileURL, fileWatcher: fileWatcher
                        ) { newContent in
                            coordinator.updateDocumentContent(newContent)
                        }
                    }

                case .confidence(let conf):
                    if conf.level == .high {
                        try await interactionHandler.confirmConfidence(
                            conf, displayedContent: content, in: fileURL, fileWatcher: fileWatcher
                        ) { newContent in
                            coordinator.updateDocumentContent(newContent)
                        }
                    }

                case .auditableCheckbox(let ac):
                    // Simple toggle from Plain mode: if currently checked, uncheck. Otherwise check with no note.
                    let action = ac.isChecked ? "uncheck" : "check"
                    try await interactionHandler.toggleAuditableCheckbox(
                        ac, action: action, note: "", displayedContent: content, in: fileURL, fileWatcher: fileWatcher
                    ) { newContent in
                        coordinator.updateDocumentContent(newContent)
                    }

                case .slider, .stepper, .toggle, .colorPicker:
                    // Plain mode no-op — use Enhanced mode for these controls
                    break

                default:
                    break
                }
            } catch {
                coordinator.showError(.error(message: error.localizedDescription))
            }
        }
    }

    // MARK: - Add Comment

    /// Handles the "Add Comment" action from context menu, Cmd+Shift+C, or selection popover.
    /// Triggers an inline input popover via the text view's existing popover system.
    private func handleAddComment(selectedText: String, nsRange: NSRange) {
        guard let fileURL = coordinator.navigation.selectedFile else { return }
        let content = coordinator.document.content

        // Convert NSRange to String.Index range
        guard let swiftRange = Range(nsRange, in: content) else { return }

        // Check for overlap with existing highlights off the main thread
        Task.detached(priority: .userInitiated) {
            let elements = InteractiveElementDetector.detect(in: content)
            let hasOverlap = elements.contains { element in
                if case .suggestion(let s) = element, s.type == .highlight {
                    return s.range.overlaps(swiftRange)
                }
                return false
            }
            await MainActor.run {
                if hasOverlap {
                    coordinator.showError(.error(message: "This text already has a comment."))
                    return
                }
                showAddCommentPopover(selectedText: selectedText, swiftRange: swiftRange, in: content, nsRange: nsRange, fileURL: fileURL)
            }
        }
    }

    private func showAddCommentPopover(selectedText: String, swiftRange: Range<String.Index>, in content: String, nsRange: NSRange, fileURL: URL) {
        // Store context for the comment submission
        pendingCommentRange = swiftRange
        pendingCommentText = selectedText
        pendingCommentFileURL = fileURL
        pendingCommentContent = content

        // Show inline input popover at the selection (reuses existing InputPopoverController pattern)
        if let textView = findMarkdownTextView() {
            textView.showInputPopover(
                for: .feedback(FeedbackElement(range: swiftRange, existingText: nil)),
                at: nsRange,
                config: InputPopoverConfig(
                    title: "Add Comment",
                    subtitle: "on: \"\(selectedText.prefix(40))\(selectedText.count > 40 ? "..." : "")\"",
                    fieldName: "addComment",
                    placeholder: "Type your comment..."
                )
            )
        }
    }

    /// State for pending comment (between popover show and submit)
    @State private var pendingCommentRange: Range<String.Index>?
    @State private var pendingCommentText: String?
    @State private var pendingCommentFileURL: URL?
    /// Content snapshot the pending range was computed against — the document
    /// may update between popover show and submit, and the range's indices are
    /// only meaningful in the string that produced them.
    @State private var pendingCommentContent: String?

    /// Finds the MarkdownNSTextView in the view hierarchy
    private func findMarkdownTextView() -> MarkdownNSTextView? {
        guard let window = NSApp.keyWindow else { return nil }
        return findTextView(in: window.contentView)
    }

    private func findTextView(in view: NSView?) -> MarkdownNSTextView? {
        guard let view else { return nil }
        if let tv = view as? MarkdownNSTextView { return tv }
        for sub in view.subviews {
            if let found = findTextView(in: sub) { return found }
        }
        return nil
    }

    // MARK: - Popover Input Handling

    /// Handles submissions from inline NSPopovers (fill-in, feedback, suggestion, review notes, challenge).
    private func handleInputSubmitted(_ element: InteractiveElement, optionIndex: Int?, fieldName: String, value: String) {
        // Intercept "addComment" submissions from the Add Comment popover
        if fieldName == "addComment",
           let range = pendingCommentRange,
           let selectedText = pendingCommentText,
           let url = pendingCommentFileURL {
            pendingCommentRange = nil
            pendingCommentText = nil
            pendingCommentFileURL = nil
            let commentSnapshot = pendingCommentContent
            pendingCommentContent = nil
            Task {
                do {
                    try await interactionHandler.addComment(
                        selectedText: selectedText,
                        comment: value,
                        range: range,
                        displayedContent: commentSnapshot ?? coordinator.document.content,
                        in: url,
                        fileWatcher: fileWatcher
                    ) { newContent in
                        coordinator.updateDocumentContent(newContent)
                    }
                } catch {
                    coordinator.showError(.error(message: error.localizedDescription))
                }
            }
            return
        }

        guard let fileURL = coordinator.navigation.selectedFile else { return }
        let content = coordinator.document.content

        Task {
            do {
                switch element {
                case .fillIn(let fi):
                    try await interactionHandler.fillIn(
                        fi, value: value, displayedContent: content, in: fileURL, fileWatcher: fileWatcher
                    ) { newContent in
                        coordinator.updateDocumentContent(newContent)
                    }

                case .feedback(let fb):
                    try await interactionHandler.setFeedback(
                        fb, text: value, displayedContent: content, in: fileURL, fileWatcher: fileWatcher
                    ) { newContent in
                        coordinator.updateDocumentContent(newContent)
                    }

                case .suggestion(let s):
                    if fieldName == "editComment" {
                        try await interactionHandler.editComment(
                            s, newComment: value, displayedContent: content, in: fileURL, fileWatcher: fileWatcher
                        ) { newContent in
                            coordinator.updateDocumentContent(newContent)
                        }
                    } else if value == "accept" {
                        try await interactionHandler.acceptSuggestion(
                            s, displayedContent: content, in: fileURL, fileWatcher: fileWatcher
                        ) { newContent in
                            coordinator.updateDocumentContent(newContent)
                        }
                    } else {
                        try await interactionHandler.rejectSuggestion(
                            s, displayedContent: content, in: fileURL, fileWatcher: fileWatcher
                        ) { newContent in
                            coordinator.updateDocumentContent(newContent)
                        }
                    }

                case .review(let rv):
                    if fieldName == "clearReview" {
                        try await interactionHandler.clearReview(
                            in: rv,
                            displayedContent: content,
                            url: fileURL,
                            fileWatcher: fileWatcher
                        ) { newContent in
                            coordinator.updateDocumentContent(newContent)
                        }
                    } else {
                        guard let optionIndex else { return }
                        try await interactionHandler.selectReview(
                            optionIndex: optionIndex,
                            notes: value.isEmpty ? nil : value,
                            in: rv,
                            displayedContent: content,
                            url: fileURL,
                            fileWatcher: fileWatcher
                        ) { newContent in
                            coordinator.updateDocumentContent(newContent)
                        }
                    }

                case .confidence(let conf):
                    try await interactionHandler.challengeConfidence(
                        conf, feedback: value, displayedContent: content, in: fileURL, fileWatcher: fileWatcher
                    ) { newContent in
                        coordinator.updateDocumentContent(newContent)
                    }

                case .slider, .stepper, .toggle, .colorPicker:
                    try await interactionHandler.replaceSpec4Element(
                        element, with: value, displayedContent: content, in: fileURL, fileWatcher: fileWatcher
                    ) { newContent in
                        coordinator.updateDocumentContent(newContent)
                    }

                case .auditableCheckbox(let ac):
                    try await interactionHandler.toggleAuditableCheckbox(
                        ac, action: fieldName, note: value, displayedContent: content, in: fileURL, fileWatcher: fileWatcher
                    ) { newContent in
                        coordinator.updateDocumentContent(newContent)
                    }

                default:
                    break
                }
            } catch {
                coordinator.showError(.error(message: error.localizedDescription))
            }
        }
    }

    // MARK: - Status Advance Submit

    private func submitStatusAdvance(status: StatusElement, to newState: String) {
        guard let fileURL = coordinator.navigation.selectedFile else { return }

        Task {
            do {
                try await interactionHandler.advanceStatus(
                    status, to: newState, displayedContent: coordinator.document.content, in: fileURL, fileWatcher: fileWatcher
                ) { newContent in
                    coordinator.updateDocumentContent(newContent)
                }
            } catch {
                coordinator.showError(.error(message: error.localizedDescription))
            }
        }
    }

    // MARK: - File/Folder Pickers

    private func openFilePicker(for fillIn: FillInElement) {
        guard let fileURL = coordinator.navigation.selectedFile else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = fillIn.hint

        // Spec 4: Re-pick — seed with current path's parent directory
        if let currentPath = fillIn.value, !currentPath.isEmpty {
            let currentURL = URL(fileURLWithPath: currentPath)
            panel.directoryURL = currentURL.deletingLastPathComponent()
            panel.nameFieldStringValue = currentURL.lastPathComponent
        }

        panel.begin { response in
            guard response == .OK, let selectedURL = panel.url else { return }
            Task { @MainActor in
                do {
                    try await interactionHandler.fillIn(
                        fillIn, value: selectedURL.path, displayedContent: coordinator.document.content,
                        in: fileURL, fileWatcher: fileWatcher
                    ) { newContent in
                        coordinator.updateDocumentContent(newContent)
                    }
                } catch {
                    coordinator.showError(.error(message: error.localizedDescription))
                }
            }
        }
    }

    private func openFolderPicker(for fillIn: FillInElement) {
        guard let fileURL = coordinator.navigation.selectedFile else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = fillIn.hint

        // Spec 4: Re-pick — seed with current folder path
        if let currentPath = fillIn.value, !currentPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: currentPath)
        }

        panel.begin { response in
            guard response == .OK, let selectedURL = panel.url else { return }
            Task { @MainActor in
                do {
                    try await interactionHandler.fillIn(
                        fillIn, value: selectedURL.path, displayedContent: coordinator.document.content,
                        in: fileURL, fileWatcher: fileWatcher
                    ) { newContent in
                        coordinator.updateDocumentContent(newContent)
                    }
                } catch {
                    coordinator.showError(.error(message: error.localizedDescription))
                }
            }
        }
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
                refreshCommentedLines(in: document.source)
            case .merged:
                coordinator.updateDocumentContent(document.source)
                refreshCommentedLines(in: document.source)
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
            refreshCommentedLines(in: document.source)
        } else {
            ExternalChangeArbiter.keepMine(document: document, theirs: theirs)
            SaveCoordinator.shared.scheduleSave(for: document, fileWatcher: fileWatcher)
        }
        coordinator.document.clearClash()
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
                .font(.callout.weight(.medium))

            Button("Reload") {
                onReload()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(
            reduceMotion
                ? .none
                : .spring(response: 0.4, dampingFraction: 0.8),
            value: true
        )
    }
}

// MARK: - Reading Progress Badge

/// Small progress badge showing scroll percentage in top-right corner.
struct ReadingProgressBadge: View {
    let progress: Double

    var body: some View {
        Text("\(Int(progress * 100))%")
            .font(.caption2.monospacedDigit().weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
    }
}
