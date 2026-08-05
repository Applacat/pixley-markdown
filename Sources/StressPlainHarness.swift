import AppKit
import SwiftUI
import aimdRenderer

/// G2 runtime AC harness (US-2.2/US-2.3). Launch the app with
/// `--stress-plain` to drive the REAL Plain-mode editor programmatically:
/// 500 keystrokes of markdown, per-keystroke integrity + selection checks,
/// autosave-to-disk verification, undo, and the external-write/undo rule.
/// Prints a report to stdout and exits 0/1.
@MainActor
enum StressPlainHarness {

    static var isRequested: Bool {
        CommandLine.arguments.contains("--stress-plain")
    }

    private final class HarnessState: ObservableObject {
        @Published var text: String = ""
    }

    private struct HarnessView: View {
        @ObservedObject var state: HarnessState
        let onEdited: (String) -> Void

        var body: some View {
            MarkdownEditor(
                text: .constant(state.text),
                onTextEdited: { onEdited($0) }
            )
            .frame(minWidth: 700, minHeight: 500)
        }
    }

    static func run(settings: UserDefaultsSettingsRepository) async {
        var failures: [String] = []
        func fail(_ message: String) { failures.append(message) }

        // Seed document on disk + in the model registry
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("plain-stress-\(ProcessInfo.processInfo.processIdentifier).md")
        let seed = "# Stress Doc\n\nProse paragraph to type into.\n\n- [ ] a task\n\nEnd.\n"
        try? seed.write(to: url, atomically: true, encoding: .utf8)
        MarkdownDocumentRegistry.release(url: url)
        let document = MarkdownDocumentRegistry.obtain(url: url, initialSource: seed)

        let fileWatcher = FileWatcher {}
        fileWatcher.watch(url)

        let state = HarnessState()
        state.text = seed

        // Mirror MarkdownView.handleTextEdited wiring exactly
        let view = HarnessView(state: state) { newText in
            document.update(source: newText)
            state.text = newText
            SaveCoordinator.shared.scheduleSave(for: document, fileWatcher: fileWatcher)
        }
        .environment(\.settings, settings)

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 720, height: 520),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)

        try? await Task.sleep(for: .milliseconds(700)) // first layout + highlight

        guard let textView = findTextView(in: window.contentView) else {
            print("STRESS-PLAIN FAIL\nno text view"); exit(1)
        }
        guard textView.isEditable else {
            print("STRESS-PLAIN FAIL\ntext view not editable"); exit(1)
        }

        // ── US-2.2: 500 keystrokes with per-keystroke integrity ──
        let insertion = "Typed: **bold** and `code` plus [ ] brackets. "
        var shadow = textView.string
        var dropped = 0, selectionErrors = 0
        var typedCount = 0

        outer: while typedCount < 500 {
            for character in insertion {
                if typedCount >= 500 { break outer }
                // Type at the end of the prose paragraph region (stable target)
                let position = (shadow as NSString).range(of: "\n\n- [ ]").location
                let insertAt = position == NSNotFound ? (shadow as NSString).length : position
                textView.setSelectedRange(NSRange(location: insertAt, length: 0))
                textView.insertText(String(character), replacementRange: NSRange(location: insertAt, length: 0))
                shadow = (shadow as NSString).replacingCharacters(in: NSRange(location: insertAt, length: 0), with: String(character))
                typedCount += 1

                if textView.string != shadow { dropped += 1; shadow = textView.string }
                if textView.selectedRange().location != insertAt + String(character).utf16.count {
                    selectionErrors += 1
                }
            }
        }
        if dropped > 0 { fail("US-2.2: \(dropped) keystroke integrity mismatches") }
        if selectionErrors > 0 { fail("US-2.2: \(selectionErrors) selection drift events") }
        if document.source != textView.string { fail("US-2.2: model diverged from storage after typing") }

        // Highlight correctness spot check after debounce settles
        try? await Task.sleep(for: .milliseconds(500))
        if let storage = textView.textStorage, storage.length > 2 {
            let headingFont = storage.attribute(.font, at: 1, effectiveRange: nil) as? NSFont
            let bodyProbeIndex = (storage.string as NSString).range(of: "Prose").location
            if bodyProbeIndex != NSNotFound,
               let bodyFont = storage.attribute(.font, at: bodyProbeIndex, effectiveRange: nil) as? NSFont,
               let headingFont, headingFont.pointSize <= bodyFont.pointSize {
                fail("US-2.2: heading not highlighted larger than body after debounce")
            }
        }
        if textView.string != shadow { fail("US-2.2: re-highlight mutated the text (string changed post-debounce)") }

        // ── US-2.3: autosave lands on disk within the debounce window ──
        try? await Task.sleep(for: .seconds(2.2))
        let diskContent = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if diskContent != document.source { fail("US-2.3: autosave missing — disk != model after 2.2s") }

        // ── US-2.3: undo reverts typing, syncs the model ──
        let beforeUndo = textView.string
        textView.undoManager?.undo()
        if textView.string == beforeUndo { fail("US-2.3: undo had no effect on typed text") }
        if document.source != textView.string { fail("US-2.3: model out of sync after undo") }
        textView.undoManager?.redo()

        // ── US-2.3: external write clears undo — ⌘Z never reverts a merge ──
        let externalContent = "# External\n\nThe AI rewrote everything.\n\n- [x] a task\n"
        try? externalContent.write(to: url, atomically: true, encoding: .utf8)
        MarkdownDocumentRegistry.syncFromDisk(url: url, content: externalContent)
        state.text = externalContent // drives updateNSView's external branch
        try? await Task.sleep(for: .milliseconds(700))

        if textView.string != externalContent {
            fail("US-2.3: external content not applied to editor")
        }
        textView.undoManager?.undo() // must be a no-op: stack cleared on merge
        if textView.string != externalContent {
            fail("US-2.3: undo restored pre-merge text — D8 violated")
        }

        // ── G3: AI-write-during-typing — arbiter auto-merge in the live editor ──
        // Type into the editor so the model is dirty…
        let endOfDoc = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: endOfDoc, length: 0))
        textView.insertText("G3-MINE typed tail.", replacementRange: NSRange(location: endOfDoc, length: 0))
        if !document.source.contains("G3-MINE") {
            fail("G3: typed text did not reach the document model")
        }
        // …while an external writer changes a disjoint region on disk.
        let g3Theirs = externalContent.replacingOccurrences(of: "# External", with: "# External THEIRS-G3")
        try? g3Theirs.write(to: url, atomically: true, encoding: .utf8)
        let outcome = ExternalChangeArbiter.arbitrate(document: document, diskContent: g3Theirs)
        guard case .merged = outcome else {
            fail("G3: disjoint typing + external write did not auto-merge (got \(outcome))")
            print("STRESS-PLAIN FAIL\nG3 arbiter outcome: \(outcome)")
            exit(1)
        }
        state.text = document.source // what MarkdownView does on .merged
        try? await Task.sleep(for: .milliseconds(400))
        if !(textView.string.contains("G3-MINE") && textView.string.contains("THEIRS-G3")) {
            fail("G3: merge lost a side — editor shows: mine=\(textView.string.contains("G3-MINE")) theirs=\(textView.string.contains("THEIRS-G3"))")
        }
        if textView.string != document.source {
            fail("G3: editor and model diverged after merge")
        }
        textView.undoManager?.undo() // merge cleared typed undo (D8) — must be a no-op
        if !(textView.string.contains("G3-MINE") && textView.string.contains("THEIRS-G3")) {
            fail("G3: undo after merge dropped a side — D8 violated")
        }

        let verdict = failures.isEmpty ? "PASS" : "FAIL"
        var report = "STRESS-PLAIN \(verdict)\n"
        report += "typed 500 keystrokes; dropped=\(dropped) selectionErrors=\(selectionErrors)\n"
        report += failures.map { "FAIL: \($0)\n" }.joined()
        print(report, terminator: "")
        // Pipe buffering can eat stdout from a CLI-launched GUI app — the
        // file is the reliable channel for the harness caller.
        try? report.write(toFile: "/tmp/stress-plain-report.txt", atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(at: url)
        exit(failures.isEmpty ? 0 : 1)
    }

    private static func findTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let tv = view as? NSTextView { return tv }
        for sub in view.subviews {
            if let found = findTextView(in: sub) { return found }
        }
        return nil
    }
}
