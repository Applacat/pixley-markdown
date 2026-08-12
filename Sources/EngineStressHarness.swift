import AppKit
import SwiftUI
import aimdRenderer
import MarkdownEngine

/// G4-P1 runtime AC harness (US-P1.2 / US-P1.3). Launch with
/// `--stress-engine` to drive the REAL swift-markdown-engine editor:
/// corpus byte-fidelity through engine storage (both modes), 500 keystrokes
/// against the MarkdownDocument wiring in rawSourceMode, autosave, undo,
/// D8 external-write undo clear (fork patch), G3 merge + clash-hold, and
/// the 16ms per-keystroke restyle budget on a 5,000-line document.
/// Prints a report to stdout and exits 0/1.
@MainActor
enum EngineStressHarness {

    static var isRequested: Bool {
        CommandLine.arguments.contains("--stress-engine")
    }

    private final class HarnessState: ObservableObject {
        @Published var text: String = ""
    }

    private struct HostView: View {
        @ObservedObject var state: HarnessState
        let rawSource: Bool
        let documentId: String
        let onEdited: ((String, String) -> Void)?

        var body: some View {
            NativeTextViewWrapper(
                text: Binding(
                    get: { state.text },
                    set: { new in
                        let previous = state.text
                        state.text = new
                        onEdited?(new, previous)
                    }
                ),
                configuration: MarkdownEditorConfiguration(rawSourceMode: rawSource),
                documentId: documentId,
                isEditable: true
            )
            .frame(minWidth: 720, minHeight: 520)
        }
    }

    private static func makeWindow(_ state: HarnessState, rawSource: Bool,
                                   documentId: String,
                                   onEdited: ((String, String) -> Void)? = nil) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 740, height: 540),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        // ARC owns the window; close() must not release it a second time.
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: HostView(
            state: state, rawSource: rawSource, documentId: documentId, onEdited: onEdited))
        window.makeKeyAndOrderFront(nil)
        return window
    }

    static func run() async {
        var failures: [String] = []
        func fail(_ message: String) { failures.append(message) }

        // ── US-P1.2: corpus byte-fidelity through engine storage, BOTH modes ──
        for rawSource in [true, false] {
            let modeName = rawSource ? "raw" : "live"
            for doc in RoundTripCorpus.documents {
                let state = HarnessState()
                state.text = doc.content
                let window = makeWindow(state, rawSource: rawSource,
                                        documentId: "corpus-\(modeName)-\(doc.name)")
                try? await Task.sleep(for: .milliseconds(350))
                guard let textView = findTextView(in: window.contentView) else {
                    fail("corpus/\(modeName)/\(doc.name): no text view"); window.close(); continue
                }
                if textView.string != doc.content {
                    fail("corpus/\(modeName)/\(doc.name): engine STORAGE diverged from source bytes")
                }
                if state.text != doc.content {
                    fail("corpus/\(modeName)/\(doc.name): binding mutated on load")
                }
                window.close()
            }
        }

        // ── US-P1.3: rawSourceMode editor wired to MarkdownDocument ──
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-stress-\(ProcessInfo.processInfo.processIdentifier).md")
        let seed = "# Stress Doc\n\nProse paragraph to type into.\n\n- [ ] a task\n\nEnd.\n"
        try? seed.write(to: url, atomically: true, encoding: .utf8)
        MarkdownDocumentRegistry.release(url: url)
        let document = MarkdownDocumentRegistry.obtain(url: url, initialSource: seed)
        let fileWatcher = FileWatcher {}
        fileWatcher.watch(url)

        let state = HarnessState()
        state.text = seed
        // Mirror the P2 MarkdownView wiring: engine binding → model + autosave,
        // with the G3 fold-in when the model moved underneath the editor.
        let window = makeWindow(state, rawSource: true, documentId: url.path) { new, previous in
            if previous != document.source, document.source != new,
               case .merged(let folded) = ThreeWayMerge.merge(
                   base: previous, mine: new, theirs: document.source) {
                document.update(source: folded)
            } else {
                document.update(source: new)
            }
            SaveCoordinator.shared.scheduleSave(for: document, fileWatcher: fileWatcher)
        }
        try? await Task.sleep(for: .milliseconds(500))

        guard let textView = findTextView(in: window.contentView) else {
            print("STRESS-ENGINE FAIL\nno text view"); exit(1)
        }
        guard textView.isEditable else {
            print("STRESS-ENGINE FAIL\ntext view not editable"); exit(1)
        }
        window.makeFirstResponder(textView)

        // 500 keystrokes with per-keystroke integrity + selection checks
        let insertion = "Typed: **bold** and `code` plus [ ] brackets. "
        var shadow = textView.string
        var dropped = 0, selectionErrors = 0, typedCount = 0
        var keystrokeMillis: [Double] = []
        let clock = ContinuousClock()

        outer: while typedCount < 500 {
            for character in insertion {
                if typedCount >= 500 { break outer }
                let position = (shadow as NSString).range(of: "\n\n- [ ]").location
                let insertAt = position == NSNotFound ? (shadow as NSString).length : position
                textView.setSelectedRange(NSRange(location: insertAt, length: 0))
                let start = clock.now
                textView.insertText(String(character), replacementRange: NSRange(location: insertAt, length: 0))
                keystrokeMillis.append(Double((clock.now - start).components.attoseconds) / 1e15)
                shadow = (shadow as NSString).replacingCharacters(
                    in: NSRange(location: insertAt, length: 0), with: String(character))
                typedCount += 1
                if textView.string != shadow { dropped += 1; shadow = textView.string }
                if textView.selectedRange().location != insertAt + String(character).utf16.count {
                    selectionErrors += 1
                }
                // Yield the runloop periodically: realistic undo grouping and
                // binding publishes (real typing never lands 500 keys in one turn).
                if typedCount % 50 == 0 { try? await Task.sleep(for: .milliseconds(5)) }
            }
        }
        if dropped > 0 { fail("US-P1.3: \(dropped) keystroke integrity mismatches") }
        if selectionErrors > 0 { fail("US-P1.3: \(selectionErrors) selection drift events") }

        // Engine publishes the binding a beat after typing — settle, then check model sync
        try? await Task.sleep(for: .milliseconds(600))
        if document.source != textView.string {
            fail("US-P1.3: model diverged from engine storage after typing")
        }

        // Autosave lands on disk within the debounce window
        try? await Task.sleep(for: .seconds(2.2))
        let diskContent = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if diskContent != document.source { fail("US-P1.3: autosave missing — disk != model after 2.2s") }

        // Undo reverts typing; model follows via the binding
        // Undo replay does NOT post textDidChange (AppKit bypasses
        // didChangeText) — fork patch #2 syncs the binding via
        // NSUndoManagerDidUndoChange instead; the model check below proves it.
        let beforeUndo = textView.string
        textView.breakUndoCoalescing()
        textView.undoManager?.undo()
        if textView.string == beforeUndo { fail("US-P1.3: undo had no effect on typed text") }
        try? await Task.sleep(for: .milliseconds(800))
        if document.source != textView.string {
            let src = document.source, tv = textView.string
            let srcTail = String(src.suffix(60)).replacingOccurrences(of: "\n", with: "⏎")
            let tvTail = String(tv.suffix(60)).replacingOccurrences(of: "\n", with: "⏎")
            fail("US-P1.3: model out of sync after undo — model(\(src.count))…\(srcTail) vs storage(\(tv.count))…\(tvTail) binding(\(state.text.count))")
        }
        textView.undoManager?.redo()
        try? await Task.sleep(for: .milliseconds(400))

        // D8 (fork patch): external replacement clears undo — ⌘Z is a no-op
        let externalContent = "# External\n\nThe AI rewrote everything.\n\n- [x] a task\n"
        try? externalContent.write(to: url, atomically: true, encoding: .utf8)
        MarkdownDocumentRegistry.syncFromDisk(url: url, content: externalContent)
        state.text = externalContent
        try? await Task.sleep(for: .milliseconds(700))
        if textView.string != externalContent {
            fail("D8: external content not applied to engine editor")
        }
        textView.undoManager?.undo()
        if textView.string != externalContent {
            fail("D8: undo restored pre-replacement text — fork patch not effective")
        }

        // G3 auto-merge: typing + disjoint external write both survive
        let mergeBase = document.source
        textView.setSelectedRange(NSRange(location: (mergeBase as NSString).length, length: 0))
        textView.insertText("G3-MINE typed tail.", replacementRange:
            NSRange(location: (mergeBase as NSString).length, length: 0))
        try? await Task.sleep(for: .milliseconds(400)) // binding publish
        if !document.source.contains("G3-MINE") { fail("G3: typed text did not reach the model") }
        let g3Theirs = externalContent.replacingOccurrences(of: "# External", with: "# External THEIRS-G3")
        try? g3Theirs.write(to: url, atomically: true, encoding: .utf8)
        guard case .merged = ExternalChangeArbiter.arbitrate(document: document, diskContent: g3Theirs) else {
            fail("G3: disjoint typing + external write did not auto-merge")
            report(failures, dropped: dropped, selectionErrors: selectionErrors, perf: keystrokeMillis, perfBudgetMet: true)
        }
        state.text = document.source
        try? await Task.sleep(for: .milliseconds(500))
        if !(textView.string.contains("G3-MINE") && textView.string.contains("THEIRS-G3")) {
            fail("G3: merge lost a side in the engine editor")
        }
        textView.undoManager?.undo() // cleared by the merge replacement — must be a no-op
        if !(textView.string.contains("G3-MINE") && textView.string.contains("THEIRS-G3")) {
            fail("G3: undo after merge dropped a side — D8 violated")
        }

        // G3 clash-hold: same-region clash holds every save until resolution
        let clashBase = document.source
        let clashMine = clashBase.replacingOccurrences(of: "# External", with: "# External CLASH-MINE")
        let clashTheirs = clashBase.replacingOccurrences(of: "# External", with: "# External CLASH-THEIRS")
        document.update(source: clashMine)
        try? clashTheirs.write(to: url, atomically: true, encoding: .utf8)
        guard case .clash = ExternalChangeArbiter.arbitrate(document: document, diskContent: clashTheirs) else {
            fail("G3-hold: same-region edits did not clash")
            report(failures, dropped: dropped, selectionErrors: selectionErrors, perf: keystrokeMillis, perfBudgetMet: true)
        }
        SaveCoordinator.shared.cancelPendingSave(for: document)
        try? await SaveCoordinator.shared.saveNow(document, fileWatcher: fileWatcher)
        if (try? String(contentsOf: url, encoding: .utf8)) != clashTheirs {
            fail("G3-hold: a save landed during a pending clash")
        }
        ExternalChangeArbiter.keepMine(document: document, theirs: clashTheirs)
        try? await SaveCoordinator.shared.saveNow(document, fileWatcher: fileWatcher)
        if (try? String(contentsOf: url, encoding: .utf8)) != clashMine {
            fail("G3-hold: keep-mine did not lift the hold")
        }
        window.close()

        // ── Perf: live-mode restyle on a 5,000-line document ──
        // Realistic markdown: blank-line separated so the block parser sees
        // ~2,500 small blocks (a single giant paragraph is pathological —
        // block-scoped incremental restyle degrades to whole-block cost;
        // measured ~460ms/keystroke on one 258KB paragraph. Noted for G6.)
        let bigDoc = (0..<2500).map { i in
            "Line \(i) with **bold**, `code`, and - [ ] markers.\n"
        }.joined(separator: "\n")
        let perfState = HarnessState()
        perfState.text = bigDoc
        let perfWindow = makeWindow(perfState, rawSource: false, documentId: "perf-5000")
        try? await Task.sleep(for: .milliseconds(1500)) // initial full format
        var perfMillis: [Double] = []
        var perfBudgetMet = true
        if let perfTV = findTextView(in: perfWindow.contentView) {
            let mid = ((perfTV.string as NSString).length) / 2
            for i in 0..<100 {
                let at = mid + i
                perfTV.setSelectedRange(NSRange(location: at, length: 0))
                let start = clock.now
                perfTV.insertText("x", replacementRange: NSRange(location: at, length: 0))
                perfMillis.append(Double((clock.now - start).components.attoseconds) / 1e15)
            }
            let sorted = perfMillis.sorted()
            let p95 = sorted[Int(Double(sorted.count) * 0.95) - 1]
            perfBudgetMet = p95 <= 16.0
            if !perfBudgetMet {
                fail("PERF: keystroke restyle p95 \(String(format: "%.2f", p95))ms > 16ms on 5,000-line doc")
            }
        } else {
            fail("PERF: no text view in perf window")
        }
        perfWindow.close()
        try? FileManager.default.removeItem(at: url)

        report(failures, dropped: dropped, selectionErrors: selectionErrors,
               perf: perfMillis.isEmpty ? keystrokeMillis : perfMillis, perfBudgetMet: perfBudgetMet)
    }

    private static func report(_ failures: [String], dropped: Int, selectionErrors: Int,
                               perf: [Double], perfBudgetMet: Bool) -> Never {
        let verdict = failures.isEmpty ? "PASS" : "FAIL"
        let sorted = perf.sorted()
        let p95 = sorted.isEmpty ? 0 : sorted[max(0, Int(Double(sorted.count) * 0.95) - 1)]
        var out = "STRESS-ENGINE \(verdict)\n"
        out += "typed 500 keystrokes; dropped=\(dropped) selectionErrors=\(selectionErrors)\n"
        out += String(format: "restyle p95 %.2fms (budget 16ms) — %@\n", p95, perfBudgetMet ? "OK" : "OVER")
        out += failures.map { "FAIL: \($0)\n" }.joined()
        print(out, terminator: "")
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
