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

    @State private var pendingScrollPosition: Double? = nil
    @State private var fileWatcher: FileWatcher? = nil
    @State private var readingProgress: Double = 0
    @State private var bookmarkedLines: Set<Int> = []
    @State private var interactionHandler = InteractionHandler()
    @State private var showingFillInPopover = false
    @State private var showingFeedbackPopover = false
    @State private var showingReviewNotesSheet = false
    @State private var showingStatusMenu = false
    @State private var showingChallengeSheet = false
    @State private var popoverText = ""
    @State private var activeFillIn: FillInElement? = nil
    @State private var activeFeedback: FeedbackElement? = nil
    @State private var activeReview: ReviewElement? = nil
    @State private var activeReviewOptionIndex: Int? = nil
    @State private var activeStatus: StatusElement? = nil
    @State private var activeConfidence: ConfidenceElement? = nil
    @State private var activeSuggestion: SuggestionElement? = nil
    @State private var showingSuggestionSheet = false
    @State private var showingDatePicker = false

    // MARK: - Body

    var body: some View {
        ZStack {
            if coordinator.navigation.selectedFile == nil {
                emptyState
            } else if coordinator.document.isLoading {
                loadingView
            } else if let error = coordinator.document.errorMessage {
                errorView(error)
            } else {
                markdownContent
            }

            // Reload pill overlay
            if coordinator.document.hasChanges {
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
        .background(.ultraThinMaterial)
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

    private var markdownContent: some View {
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
            onInteractiveElementClicked: { element, optionIndex, point in
                handleInteractiveClick(element, optionIndex: optionIndex)
            }
        )
        .overlay(alignment: .topTrailing) {
            if coordinator.navigation.selectedFile != nil {
                ReadingProgressBadge(progress: readingProgress)
                    .padding(8)
            }
        }
        .sheet(isPresented: $showingFillInPopover) {
            FillInSheet(
                hint: activeFillIn?.hint ?? "",
                text: $popoverText,
                onSubmit: {
                    submitFillIn()
                },
                onCancel: {
                    showingFillInPopover = false
                }
            )
        }
        .sheet(isPresented: $showingFeedbackPopover) {
            FeedbackSheet(
                text: $popoverText,
                onSubmit: {
                    submitFeedback()
                },
                onCancel: {
                    showingFeedbackPopover = false
                }
            )
        }
        .sheet(isPresented: $showingReviewNotesSheet) {
            ReviewNotesSheet(
                status: activeReview.flatMap { rv in
                    activeReviewOptionIndex.map { rv.options[$0].status }
                } ?? .fail,
                text: $popoverText,
                onSubmit: {
                    submitReviewNotes()
                },
                onCancel: {
                    showingReviewNotesSheet = false
                }
            )
        }
        .sheet(isPresented: $showingStatusMenu) {
            if let status = activeStatus {
                StatusPickerSheet(
                    currentState: status.currentState,
                    nextStates: status.nextStates,
                    onSelect: { newState in
                        submitStatusAdvance(to: newState)
                    },
                    onCancel: {
                        showingStatusMenu = false
                    }
                )
            }
        }
        .sheet(isPresented: $showingDatePicker) {
            DatePickerSheet(
                onSubmit: { dateString in
                    popoverText = dateString
                    submitFillIn()
                    showingDatePicker = false
                },
                onCancel: {
                    showingDatePicker = false
                    activeFillIn = nil
                }
            )
        }
        .sheet(isPresented: $showingSuggestionSheet) {
            if let suggestion = activeSuggestion {
                SuggestionSheet(
                    suggestion: suggestion,
                    onAccept: { submitSuggestion(accept: true) },
                    onReject: { submitSuggestion(accept: false) },
                    onCancel: { showingSuggestionSheet = false }
                )
            }
        }
        .sheet(isPresented: $showingChallengeSheet) {
            FeedbackSheet(
                text: $popoverText,
                onSubmit: {
                    submitChallenge()
                },
                onCancel: {
                    showingChallengeSheet = false
                }
            )
        }
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
            startWatching(fileURL)
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

    // MARK: - Interactive Element Handling

    private func handleInteractiveClick(_ element: InteractiveElement, optionIndex: Int? = nil) {
        guard let fileURL = coordinator.navigation.selectedFile else { return }

        Task {
            do {
                switch element {
                case .checkbox(let cb):
                    try await interactionHandler.toggleCheckbox(
                        cb, in: fileURL, fileWatcher: fileWatcher
                    ) { newContent in
                        coordinator.updateDocumentContent(newContent)
                    }

                case .choice(let ch):
                    let targetIndex = optionIndex ?? 0
                    try await interactionHandler.selectChoice(
                        optionIndex: targetIndex, in: ch, url: fileURL, fileWatcher: fileWatcher
                    ) { newContent in
                        coordinator.updateDocumentContent(newContent)
                    }

                case .review(let rv):
                    let targetIndex = optionIndex ?? 0
                    let targetOption = rv.options[targetIndex]
                    if targetOption.status.promptsForNotes {
                        // Show notes sheet for FAIL, PASS WITH NOTES, BLOCKED
                        activeReview = rv
                        activeReviewOptionIndex = targetIndex
                        popoverText = ""
                        showingReviewNotesSheet = true
                    } else {
                        // Direct selection: APPROVED, PASS, N/A
                        try await interactionHandler.selectReview(
                            optionIndex: targetIndex, in: rv, url: fileURL, fileWatcher: fileWatcher
                        ) { newContent in
                            coordinator.updateDocumentContent(newContent)
                        }
                    }

                case .fillIn(let fi):
                    switch fi.type {
                    case .file:
                        openFilePicker(for: fi)
                    case .folder:
                        openFolderPicker(for: fi)
                    case .text:
                        activeFillIn = fi
                        popoverText = fi.value ?? ""
                        showingFillInPopover = true
                    case .date:
                        activeFillIn = fi
                        showingDatePicker = true
                    }

                case .feedback(let fb):
                    activeFeedback = fb
                    popoverText = fb.existingText ?? ""
                    showingFeedbackPopover = true

                case .suggestion(let s):
                    activeSuggestion = s
                    showingSuggestionSheet = true

                case .status(let st):
                    let nextStates = st.nextStates
                    if nextStates.count == 1 {
                        // Single next state: advance directly
                        try await interactionHandler.advanceStatus(
                            st, to: nextStates[0], in: fileURL, fileWatcher: fileWatcher
                        ) { newContent in
                            coordinator.updateDocumentContent(newContent)
                        }
                    } else if nextStates.count > 1 {
                        // Multiple next states: show picker
                        activeStatus = st
                        showingStatusMenu = true
                    }
                    // No next states = terminal, ignore click

                case .confidence(let conf):
                    if conf.level == .high {
                        // Confirm high confidence
                        try await interactionHandler.confirmConfidence(
                            conf, in: fileURL, fileWatcher: fileWatcher
                        ) { newContent in
                            coordinator.updateDocumentContent(newContent)
                        }
                    } else if conf.level == .low {
                        // Challenge low confidence: open sheet to append feedback comment
                        activeConfidence = conf
                        popoverText = ""
                        showingChallengeSheet = true
                    }
                    // medium/confirmed: no action on click

                case .conditional, .collapsible:
                    // Handled at the rendering level, not click-through
                    break
                }
            } catch {
                coordinator.showError(.error(message: error.localizedDescription))
            }
        }
    }

    private func submitFillIn() {
        guard let fillIn = activeFillIn,
              let fileURL = coordinator.navigation.selectedFile,
              !popoverText.isEmpty else {
            showingFillInPopover = false
            return
        }

        Task {
            do {
                try await interactionHandler.fillIn(
                    fillIn, value: popoverText, in: fileURL, fileWatcher: fileWatcher
                ) { newContent in
                    coordinator.updateDocumentContent(newContent)
                }
            } catch {
                coordinator.showError(.error(message: error.localizedDescription))
            }
            showingFillInPopover = false
            activeFillIn = nil
            popoverText = ""
        }
    }

    private func submitFeedback() {
        guard let feedback = activeFeedback,
              let fileURL = coordinator.navigation.selectedFile,
              !popoverText.isEmpty else {
            showingFeedbackPopover = false
            return
        }

        Task {
            do {
                try await interactionHandler.setFeedback(
                    feedback, text: popoverText, in: fileURL, fileWatcher: fileWatcher
                ) { newContent in
                    coordinator.updateDocumentContent(newContent)
                }
            } catch {
                coordinator.showError(.error(message: error.localizedDescription))
            }
            showingFeedbackPopover = false
            activeFeedback = nil
            popoverText = ""
        }
    }

    // MARK: - Review Notes Submit

    private func submitReviewNotes() {
        guard let review = activeReview,
              let optionIndex = activeReviewOptionIndex,
              let fileURL = coordinator.navigation.selectedFile else {
            showingReviewNotesSheet = false
            return
        }

        Task {
            do {
                try await interactionHandler.selectReview(
                    optionIndex: optionIndex,
                    notes: popoverText.isEmpty ? nil : popoverText,
                    in: review,
                    url: fileURL,
                    fileWatcher: fileWatcher
                ) { newContent in
                    coordinator.updateDocumentContent(newContent)
                }
            } catch {
                coordinator.showError(.error(message: error.localizedDescription))
            }
            showingReviewNotesSheet = false
            activeReview = nil
            activeReviewOptionIndex = nil
            popoverText = ""
        }
    }

    // MARK: - Status Advance Submit

    private func submitStatusAdvance(to newState: String) {
        guard let status = activeStatus,
              let fileURL = coordinator.navigation.selectedFile else {
            showingStatusMenu = false
            return
        }

        Task {
            do {
                try await interactionHandler.advanceStatus(
                    status, to: newState, in: fileURL, fileWatcher: fileWatcher
                ) { newContent in
                    coordinator.updateDocumentContent(newContent)
                }
            } catch {
                coordinator.showError(.error(message: error.localizedDescription))
            }
            showingStatusMenu = false
            activeStatus = nil
        }
    }

    private func submitSuggestion(accept: Bool) {
        guard let suggestion = activeSuggestion,
              let fileURL = coordinator.navigation.selectedFile else {
            showingSuggestionSheet = false
            return
        }

        Task {
            do {
                if accept {
                    try await interactionHandler.acceptSuggestion(
                        suggestion, in: fileURL, fileWatcher: fileWatcher
                    ) { newContent in
                        coordinator.updateDocumentContent(newContent)
                    }
                } else {
                    try await interactionHandler.rejectSuggestion(
                        suggestion, in: fileURL, fileWatcher: fileWatcher
                    ) { newContent in
                        coordinator.updateDocumentContent(newContent)
                    }
                }
            } catch {
                coordinator.showError(.error(message: error.localizedDescription))
            }
            showingSuggestionSheet = false
            activeSuggestion = nil
        }
    }

    private func submitChallenge() {
        guard let confidence = activeConfidence,
              let fileURL = coordinator.navigation.selectedFile,
              !popoverText.isEmpty else {
            showingChallengeSheet = false
            return
        }

        Task {
            do {
                try await interactionHandler.challengeConfidence(
                    confidence, feedback: popoverText, in: fileURL, fileWatcher: fileWatcher
                ) { newContent in
                    coordinator.updateDocumentContent(newContent)
                }
            } catch {
                coordinator.showError(.error(message: error.localizedDescription))
            }
            showingChallengeSheet = false
            activeConfidence = nil
            popoverText = ""
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

        panel.begin { response in
            guard response == .OK, let selectedURL = panel.url else { return }
            Task { @MainActor in
                do {
                    try await interactionHandler.fillIn(
                        fillIn, value: selectedURL.path, in: fileURL, fileWatcher: fileWatcher
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

        panel.begin { response in
            guard response == .OK, let selectedURL = panel.url else { return }
            Task { @MainActor in
                do {
                    try await interactionHandler.fillIn(
                        fillIn, value: selectedURL.path, in: fileURL, fileWatcher: fileWatcher
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
            fileWatcher = FileWatcher { [weak coordinator] in
                coordinator?.markDocumentChanged()
            }
        }
        fileWatcher?.watch(url)
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
