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
        /// Runtime-flippable (US-P2.1): the mode flip must be byte-exact and
        /// drop the document's undo stack.
        @Published var rawSource: Bool = true
    }

    private struct HostView: View {
        @ObservedObject var state: HarnessState
        let documentId: String
        let onEdited: ((String, String) -> Void)?
        var onReady: ((NSScrollView, NSTextView) -> Void)? = nil

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
                configuration: MarkdownEditorConfiguration(
                    leftContentInset: onReady != nil ? PixleyGutterView.width : 0,
                    rawSourceMode: state.rawSource,
                    extensions: CriticMarkupExtensions.all()),
                documentId: documentId,
                isEditable: true,
                // Same production overlay so the harness exercises the real seam.
                onInteractiveOverlay: { storage, range in
                    PixleyElementStyler.overlay(storage: storage, range: range)
                },
                onScrollViewReady: onReady
            )
            .frame(minWidth: 720, minHeight: 520)
        }
    }

    private static func makeWindow(_ state: HarnessState, rawSource: Bool,
                                   documentId: String,
                                   onEdited: ((String, String) -> Void)? = nil) -> NSWindow {
        state.rawSource = rawSource
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 740, height: 540),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        // ARC owns the window; close() must not release it a second time.
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: HostView(
            state: state, documentId: documentId, onEdited: onEdited))
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

        // ── US-P3.2: interactive core four — overlay attributes, byte-exact
        //    writes through InteractionHandler, and hit-test identifier mapping ──
        await runInteractiveChecks(fail: fail)

        // ── US-P2.1: runtime mode flip is byte-exact and drops undo ──
        let flipDoc = RoundTripCorpus.documents[0].content // kitchen-sink
        let flipState = HarnessState()
        flipState.text = flipDoc
        let flipWindow = makeWindow(flipState, rawSource: false, documentId: "mode-flip")
        try? await Task.sleep(for: .milliseconds(500))
        if let flipTV = findTextView(in: flipWindow.contentView) {
            flipWindow.makeFirstResponder(flipTV)
            let end = (flipTV.string as NSString).length
            flipTV.setSelectedRange(NSRange(location: end, length: 0))
            flipTV.insertText("\nFLIP-TYPED", replacementRange: NSRange(location: end, length: 0))
            try? await Task.sleep(for: .milliseconds(400))
            let preFlip = flipTV.string
            flipState.rawSource = true // Enhanced → Plain at runtime
            try? await Task.sleep(for: .milliseconds(500))
            if flipTV.string != preFlip {
                fail("US-P2.1: mode flip mutated content (live→raw)")
            }
            flipTV.breakUndoCoalescing()
            flipTV.undoManager?.undo() // stack dropped on flip — must be a no-op
            if flipTV.string != preFlip {
                fail("US-P2.1: undo after mode flip changed text — stack not dropped")
            }
            flipState.rawSource = false // and back
            try? await Task.sleep(for: .milliseconds(500))
            if flipTV.string != preFlip {
                fail("US-P2.1: mode flip mutated content (raw→live)")
            }
        } else {
            fail("US-P2.1: no text view in mode-flip window")
        }
        flipWindow.close()

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

    // MARK: - Interactive core four (US-P3.2)

    private static let interactiveSeed = """
    > [ ] YES  [ ] NO

    <!-- status: TODO / IN PROGRESS / DONE -->
    **Status:** IN PROGRESS

    Name: [[enter your name]]
    """

    private static func runInteractiveChecks(fail: (String) -> Void) async {
        // Part A: overlay applies the seam attributes + hit-test maps a click.
        let state = HarnessState()
        state.text = interactiveSeed
        let window = makeWindow(state, rawSource: false, documentId: "interactive")
        try? await Task.sleep(for: .milliseconds(600))
        if let tv = findTextView(in: window.contentView) as? NSTextView,
           let storage = tv.textStorage {
            let ns = storage.string as NSString
            // Choice options carry a glyph; the two `[ ]` become interactive.
            var glyphCount = 0
            storage.enumerateAttribute(.interactiveGlyph,
                                       in: NSRange(location: 0, length: storage.length)) { v, _, _ in
                if v != nil { glyphCount += 1 }
            }
            if glyphCount < 2 { fail("US-P3.2: choice options did not receive interactive glyphs (\(glyphCount))") }

            // Choice carries a clickable "+" accessory to add options.
            var hasAddAccessory = false
            storage.enumerateAttribute(.interactiveAccessory,
                                       in: NSRange(location: 0, length: storage.length)) { v, _, _ in
                if let a = v as? InteractiveAccessory, a.identifier?.hasPrefix("choice-add") == true { hasAddAccessory = true }
            }
            if !hasAddAccessory { fail("G5-add: choice missing the '+' add-option accessory") }

            // Visual confirmation of the '+' on the choice.
            if CommandLine.arguments.contains("--shot"), let view = window.contentView,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) {
                    let path = FileManager.default.temporaryDirectory.appendingPathComponent("choice-shot.png")
                    try? png.write(to: path)
                    print("CHOICE-SHOT \(path.path)")
                }
            }

            // Status label + fill-in become interactive zones.
            var zoneIds: Set<String> = []
            storage.enumerateAttribute(.interactiveZone,
                                       in: NSRange(location: 0, length: storage.length)) { v, _, _ in
                if let id = v as? String { zoneIds.insert(String(id.split(separator: ":").first ?? "")) }
            }
            if !zoneIds.contains("status") { fail("US-P3.2: status did not receive an interactive zone") }
            if !zoneIds.contains("fillin") { fail("US-P3.2: fill-in did not receive an interactive zone") }

            // Fill-in displays cleanly: the `text:` storage prefix is hidden
            // (collapsed to clear ink), so the zone sits on the VALUE only.
            let filledSeed = "Filled: [[text: Enterprise Portal]]\n"
            let fs = HarnessState(); fs.text = filledSeed
            let fw = makeWindow(fs, rawSource: false, documentId: "fillin-clean")
            try? await Task.sleep(for: .milliseconds(400))
            if let ftv = findTextView(in: fw.contentView) as? NSTextView, let fstore = ftv.textStorage {
                let fstr = fstore.string as NSString
                // The `text:` prefix chars must be clear-inked (hidden).
                let prefixLoc = fstr.range(of: "text:").location
                if prefixLoc != NSNotFound {
                    let ink = fstore.attribute(.foregroundColor, at: prefixLoc, effectiveRange: nil) as? NSColor
                    if ink != NSColor.clear { fail("US-P3.2: fill-in `text:` prefix is visible, not hidden") }
                }
                // The value ("Enterprise Portal") carries the zone.
                let valueLoc = fstr.range(of: "Enterprise").location
                if valueLoc != NSNotFound,
                   fstore.attribute(.interactiveZone, at: valueLoc, effectiveRange: nil) as? String == nil {
                    fail("US-P3.2: fill-in value is not the clickable zone")
                }
            }
            fw.close()
            _ = ns
            // (Hit-test → identifier mapping is proven in the fork's own
            // InteractiveElementSeamTests; NativeTextView is internal there.)
        } else {
            fail("US-P3.2: interactive editor produced no text storage")
        }
        window.close()

        // US-P3.4: CriticMarkup styles (has a background) but is INERT — no
        // interactive glyph/zone under it, so no hover cursor / click.
        let criticState = HarnessState()
        criticState.text = "The API {++needs auth++} and {==a span==}{>>note<<}.\n"
        let criticWindow = makeWindow(criticState, rawSource: false, documentId: "critic")
        try? await Task.sleep(for: .milliseconds(500))
        if let tv = findTextView(in: criticWindow.contentView) as? NSTextView,
           let storage = tv.textStorage {
            let str = storage.string as NSString
            let insertionRange = str.range(of: "needs auth")
            if insertionRange.location != NSNotFound {
                let hasBackground = storage.attribute(.backgroundColor, at: insertionRange.location, effectiveRange: nil) != nil
                    || storage.attribute(.markdownBlockBackground, at: insertionRange.location, effectiveRange: nil) != nil
                if !hasBackground { fail("US-P3.4: CriticMarkup addition not styled (no background)") }
                let isInteractive = storage.attribute(.interactiveZone, at: insertionRange.location, effectiveRange: nil) != nil
                    || storage.attribute(.interactiveGlyph, at: insertionRange.location, effectiveRange: nil) != nil
                if isInteractive { fail("US-P3.4: CriticMarkup is interactive — must be inert until G5") }
            }
        } else {
            fail("US-P3.4: critic editor produced no text storage")
        }
        criticWindow.close()

        // US-P4.1: the TextKit 2 gutter enumerates the right line numbers.
        await runGutterCheck(fail: fail)

        // G5/#109: every Insert-menu snippet is detector-recognized.
        runInsertMenuChecks(fail: fail)

        // Part B: byte-exact writes through InteractionHandler (the same path
        // clicks route to), independent of presentation.
        await runInteractiveWriteChecks(fail: fail)
    }

    private static func runInsertMenuChecks(fail: (String) -> Void) {
        func detects(_ text: String, _ match: (InteractiveElement) -> Bool) -> Bool {
            InteractiveElementDetector.detect(in: text).contains(where: match)
        }
        for element in InsertElement.allCases {
            let text = element.snippet(selectedText: "sample").text
            let ok: Bool
            switch element {
            case .checkbox:   ok = detects(text) { if case .checkbox = $0 { return true }; return false }
            case .choice:     ok = detects(text) { if case .choice = $0 { return true }; return false }
            case .fillInText: ok = detects(text) { if case .fillIn(let f) = $0 { return f.type == .text }; return false }
            case .fillInDate: ok = detects(text) { if case .fillIn(let f) = $0 { return f.type == .date }; return false }
            case .status:     ok = detects(text) { if case .status = $0 { return true }; return false }
            case .review:     ok = detects(text) { if case .review = $0 { return true }; return false }
            case .feedback:   ok = detects(text) { if case .feedback = $0 { return true }; return false }
            case .addComment: ok = text.contains("{==") || text.contains("<!-- feedback") // wrap or feedback
            }
            if !ok { fail("G5-insert: \(element.rawValue) markdown not detected — \(text.debugDescription)") }
        }
    }

    private static func runGutterCheck(fail: (String) -> Void) async {
        // Heading + wrapped paragraph + normal lines: verify the number aligns
        // to the FIRST visual line of tall/wrapped fragments, not their center.
        let doc = """
        # Big Heading

        Short line one.

        This is a very long paragraph that must wrap across at least two visual lines within the harness window so the gutter number's vertical alignment can be checked against a tall wrapped fragment instead of a single row of text here.

        Short line two.

        - [ ] a task
        - [ ] another
        End line.
        """
        let state = HarnessState(); state.text = doc
        let gutter = GutterController()
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 740, height: 900),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: HostView(
            state: state, documentId: "gutter",
            onEdited: nil, onReady: { sv, tv in gutter.install(on: sv, textView: tv) { _ in } }))
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(700))

        gutter.update(bookmarked: [3], commented: [6])
        try? await Task.sleep(for: .milliseconds(200))
        let lines = gutter.visibleLineNumbers()
        if lines.isEmpty { fail("US-P4.1: gutter produced no line numbers") }
        else if lines.first != 1 { fail("US-P4.1: gutter first line is \(lines.first!), expected 1") }
        else if lines != lines.sorted() { fail("US-P4.1: gutter line numbers not monotonic: \(lines)") }
        else if !lines.contains(11) { fail("US-P4.1: gutter missing line 11 (got \(lines.count) lines: \(lines))") }

        // Snapshot for visual confirmation (a gutter is a visual feature).
        if CommandLine.arguments.contains("--shot"), let view = window.contentView,
           let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                let path = FileManager.default.temporaryDirectory
                    .appendingPathComponent("gutter-shot.png")
                try? png.write(to: path)
                print("GUTTER-SHOT \(path.path)")
            }
        }
        window.close()
    }

    private static func runInteractiveWriteChecks(fail: (String) -> Void) async {
        let handler = InteractionHandler()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("interactive-\(ProcessInfo.processInfo.processIdentifier).md")
        defer { try? FileManager.default.removeItem(at: url) }

        func write(_ seed: String, _ body: @MainActor (InteractionHandler, URL, @escaping (String) -> Void) async throws -> Void) async -> String? {
            try? seed.write(to: url, atomically: true, encoding: .utf8)
            MarkdownDocumentRegistry.release(url: url)
            _ = MarkdownDocumentRegistry.obtain(url: url, initialSource: seed)
            var result: String?
            do { try await body(handler, url) { result = $0 } }
            catch { fail("US-P3.2 write threw: \(error)"); return nil }
            return result
        }

        // Choice: selecting option 0 checks the first box only (radio).
        let choiceSeed = "> [ ] YES  [ ] NO\n"
        if let out = await write(choiceSeed, { h, u, cb in
            let elements = InteractiveElementDetector.detect(in: choiceSeed)
            guard case .choice(let c)? = elements.first(where: { if case .choice = $0 { return true }; return false }) else {
                fail("US-P3.2: choice not detected in seed"); return
            }
            try await h.selectChoice(optionIndex: 0, in: c, displayedContent: choiceSeed, url: u, onContentUpdated: cb)
        }) {
            if out != "> [x] YES  [ ] NO\n" {
                fail("US-P3.2: selectChoice(0) bytes wrong: \(out.debugDescription)")
            }
            // Radio: selecting the other option moves the mark, never adds one.
            if let out2 = await write(out, { h, u, cb in
                let elements = InteractiveElementDetector.detect(in: out)
                guard case .choice(let c)? = elements.first(where: { if case .choice = $0 { return true }; return false }) else { return }
                try await h.selectChoice(optionIndex: 1, in: c, displayedContent: out, url: u, onContentUpdated: cb)
            }), out2 != "> [ ] YES  [x] NO\n" {
                fail("US-P3.2: radio reselect bytes wrong: \(out2.debugDescription)")
            }
        }

        // "+" affordance: appending an option grows the choice to 3 (no cap).
        let addSeed = "> [ ] YES  [ ] NO\n"
        if let out = await write(addSeed, { h, u, cb in
            let elements = InteractiveElementDetector.detect(in: addSeed)
            guard case .choice(let c)? = elements.first(where: { if case .choice = $0 { return true }; return false }) else {
                fail("G5-add: choice not detected in seed"); return
            }
            try await h.addChoiceOption(c, displayedContent: addSeed, url: u, onContentUpdated: cb)
        }) {
            if case .choice(let c)? = InteractiveElementDetector.detect(in: out).first(where: {
                if case .choice = $0 { return true }; return false
            }) {
                if c.options.count != 3 { fail("G5-add: choice did not grow to 3 options (\(c.options.count))") }
            } else {
                fail("G5-add: choice no longer detects after adding an option: \(out.debugDescription)")
            }
        }

        // Status: advancing preserves the `**Status:**` prefix.
        let statusSeed = "<!-- status: TODO / IN PROGRESS / DONE -->\n**Status:** IN PROGRESS\n"
        if let out = await write(statusSeed, { h, u, cb in
            let elements = InteractiveElementDetector.detect(in: statusSeed)
            guard case .status(let s)? = elements.first(where: { if case .status = $0 { return true }; return false }) else {
                fail("US-P3.2: status not detected in seed"); return
            }
            try await h.advanceStatus(s, to: "DONE", displayedContent: statusSeed, in: u, onContentUpdated: cb)
        }) {
            if !out.contains("**Status:** DONE") {
                fail("US-P3.2: advanceStatus lost the prefix or state: \(out.debugDescription)")
            }
        }

        // Fill-in: value is wrapped with its typed prefix (re-detectable).
        let fillSeed = "Name: [[enter your name]]\n"
        if let out = await write(fillSeed, { h, u, cb in
            let elements = InteractiveElementDetector.detect(in: fillSeed)
            guard case .fillIn(let f)? = elements.first(where: { if case .fillIn = $0 { return true }; return false }) else {
                fail("US-P3.2: fill-in not detected in seed"); return
            }
            try await h.fillIn(f, value: "Jose Duarte", displayedContent: fillSeed, in: u, onContentUpdated: cb)
        }) {
            if !out.contains("[[text: Jose Duarte]]") {
                fail("US-P3.2: fillIn wrapping wrong: \(out.debugDescription)")
            }
            // Re-detectable: the filled value parses back as a fill-in.
            let redetected = InteractiveElementDetector.detect(in: out)
            if !redetected.contains(where: { if case .fillIn = $0 { return true }; return false }) {
                fail("US-P3.2: filled value no longer detects as a fill-in")
            }
        }

        // US-P4.4 identity (automated equivalent of the #81 manual checks,
        // Tests 1/2/5): a filled value survives an insertion ABOVE it and stays
        // itself. In the engine the element IS its source text — an edit above
        // only shifts offsets, so its value cannot transplant to a neighbor
        // (the class the old ForEach-identity renderer got wrong is gone).
        let idSeed = "Intro paragraph.\n\nName: [[text: DRAFT-JOSE]]\n\n- [ ] task\n"
        if let out = await write(idSeed, { h, u, cb in
            // Insert a comment on line 1 — a line lands above the fill-in and
            // the whole document reparses (the #81 trigger).
            try await h.setGutterComment(lineNumber: 1, commentText: "note",
                                         displayedContent: idSeed, in: u, onContentUpdated: cb)
        }) {
            let elements = InteractiveElementDetector.detect(in: out)
            let fill = elements.compactMap { e -> FillInElement? in
                if case .fillIn(let f) = e { return f }; return nil
            }
            if fill.count != 1 || fill.first?.value != "DRAFT-JOSE" {
                fail("US-P4.4 identity: fill-in value did not survive an insertion above (\(fill.map { $0.value ?? "nil" }))")
            }
            // Exactly one checkbox too — no element duplicated/transplanted.
            let checks = elements.filter { if case .checkbox = $0 { return true }; return false }
            if checks.count != 1 {
                fail("US-P4.4 identity: checkbox count changed after insert (\(checks.count))")
            }
        }
    }
}
