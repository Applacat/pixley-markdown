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

    @Environment(\.coordinator) private var coordinator
    @Environment(\.settings) private var settings

    @State private var fileWatcher: FileWatcher? = nil

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
                rawSourceMode: settings.behavior.interactiveMode == .plain
            ),
            fontSize: CGFloat(settings.rendering.fontSize),
            documentId: coordinator.navigation.selectedFile?.path ?? "no-document",
            isEditable: true
        )
        .background {
            // ⌘S forces an immediate save of the live document (US-2.3)
            Button("") { forceSave() }
                .keyboardShortcut("s", modifiers: .command)
                .hidden()
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
        }
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
