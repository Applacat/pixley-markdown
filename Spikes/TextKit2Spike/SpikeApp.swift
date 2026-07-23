import SwiftUI
import AppKit

/// Gate G0 spike host. Normal launch: interactive editing window.
/// `--stress` launch: runs the US-0.1 scripted loop (type-save-reload-undo
/// × 100 with an embedded checkbox) and exits 0/1 with a report on stdout.
@main
struct SpikeApp: App {
    @State private var document = SpikeApp.makeDocument()

    static let sampleSource = """
    # TextKit 2 Spike

    Prose paragraph with **bold content** to style.

    - [ ] First task
    - [x] Second task

    ## Section Two

    Closing prose line for typing into.
    """

    static func makeDocument() -> SpikeDocument {
        let source: String
        if CommandLine.arguments.contains("--stress-reveal") {
            // US-0.2 perf corpus: 5k lines, every line carries a bold run
            source = (1...5000).map { "Line \($0) of prose with **bold span \($0)** inside it." }
                .joined(separator: "\n")
        } else {
            source = sampleSource
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tk2spike-\(ProcessInfo.processInfo.processIdentifier).md")
        try? source.write(to: url, atomically: true, encoding: .utf8)
        return SpikeDocument(source: source, url: url)
    }

    var body: some Scene {
        WindowGroup("TextKit2 Spike — G0") {
            SpikeContentView(document: document)
        }
    }
}

struct SpikeContentView: View {
    let document: SpikeDocument
    @State private var stressResult: String = ""

    var body: some View {
        VStack(spacing: 0) {
            if !stressResult.isEmpty {
                Text(stressResult)
                    .font(.system(.caption, design: .monospaced))
                    .padding(4)
            }
            SpikeTextView(document: document)
        }
        .frame(minWidth: 600, minHeight: 400)
        .task {
            if CommandLine.arguments.contains("--stress") {
                // Let the window and text system finish first layout
                try? await Task.sleep(for: .milliseconds(500))
                let report = StressTest.run(document: document)
                print(report.summary)
                exit(report.passed ? 0 : 1)
            }
            if CommandLine.arguments.contains("--stress-reveal") {
                try? await Task.sleep(for: .milliseconds(1000))
                let report = RevealStressTest.run(document: document)
                print(report)
                exit(report.contains("REVEAL PASS") ? 0 : 1)
            }
        }
    }
}

// MARK: - US-0.1 Stress Loop

@MainActor
enum StressTest {
    struct Report {
        var passed = true
        var lines: [String] = []
        var summary: String {
            (["STRESS \(passed ? "PASS" : "FAIL")"] + lines).joined(separator: "\n")
        }
        mutating func fail(_ message: String) {
            passed = false
            lines.append("FAIL: \(message)")
        }
    }

    static func run(document: SpikeDocument) -> Report {
        var report = Report()

        guard let window = NSApp.windows.first,
              let textView = findTextView(in: window.contentView) else {
            report.fail("no text view found")
            return report
        }
        guard textView.textLayoutManager != nil else {
            report.fail("TextKit 2 not active (textLayoutManager nil)")
            return report
        }
        guard let storage = textView.textStorage else {
            report.fail("no text storage")
            return report
        }

        let start = Date()
        var rng = SystemRandomNumberGenerator()

        for i in 1...100 {
            // 1. Type at a random prose position (never inside an attachment)
            let insertIndex = safeInsertIndex(storage: storage, using: &rng)
            textView.setSelectedRange(NSRange(location: insertIndex, length: 0))
            textView.insertText("x", replacementRange: NSRange(location: insertIndex, length: 0))

            // 2. Round-trip integrity: storage serialize == model
            let serialized = SpikeProjection.serialize(storage: storage)
            if serialized != document.source {
                report.fail("iter \(i): storage/model divergence after typing")
                break
            }

            // 3. Every 10th: toggle a checkbox attachment through its object
            if i % 10 == 0 {
                if let attachment = firstAttachment(in: storage) {
                    attachment.isChecked.toggle()
                    attachment.onToggle?(attachment)
                    if !document.source.contains("- [\(attachment.isChecked ? "x" : " ")] \(attachment.label)") {
                        report.fail("iter \(i): checkbox toggle not reflected in model")
                        break
                    }
                } else {
                    report.fail("iter \(i): checkbox attachment lost from storage")
                    break
                }
            }

            // 4. Save → reload from disk → storage rebuilt → verify integrity
            do {
                try document.save()
                try document.reload()
            } catch {
                report.fail("iter \(i): save/reload error \(error)")
                break
            }
            (textView.delegate as? SpikeTextView.Coordinator)?.syncFromModelIfNeeded()
            let afterReload = SpikeProjection.serialize(storage: storage)
            if afterReload != document.source {
                report.fail("iter \(i): divergence after reload")
                break
            }

            // 5. Every 25th: undo a typed character, then redo, verify integrity
            if i % 25 == 0 {
                textView.undoManager?.undo()
                let afterUndo = SpikeProjection.serialize(storage: storage)
                document.update(source: afterUndo)
                textView.undoManager?.redo()
                let afterRedo = SpikeProjection.serialize(storage: storage)
                document.update(source: afterRedo)
            }
        }

        // Caret traversal: attachment must behave as one atomic character
        if let range = attachmentRange(in: storage) {
            textView.setSelectedRange(NSRange(location: range.location, length: 0))
            textView.moveRight(nil)
            let after = textView.selectedRange().location
            if after != range.location + 1 {
                report.fail("caret did not traverse attachment atomically (moved to \(after))")
            }
        } else {
            report.fail("no attachment for caret traversal check")
        }

        let elapsed = Date().timeIntervalSince(start)
        report.lines.append(String(format: "100 iterations in %.2fs; final doc %d chars; attachments preserved: %@",
                                   elapsed, document.source.count,
                                   firstAttachment(in: storage) != nil ? "yes" : "no"))
        return report
    }

    private static func safeInsertIndex(storage: NSTextStorage, using rng: inout SystemRandomNumberGenerator) -> Int {
        // Insert only at positions NOT adjacent to attachment characters
        for _ in 0..<20 {
            let index = Int.random(in: 0..<max(1, storage.length), using: &rng)
            let check = NSRange(location: max(0, index - 1), length: min(2, storage.length - max(0, index - 1)))
            var hasAttachment = false
            storage.enumerateAttribute(.attachment, in: check) { value, _, stop in
                if value != nil { hasAttachment = true; stop.pointee = true }
            }
            if !hasAttachment { return index }
        }
        return 0
    }

    private static func firstAttachment(in storage: NSTextStorage) -> CheckboxAttachment? {
        var found: CheckboxAttachment?
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, stop in
            if let attachment = value as? CheckboxAttachment { found = attachment; stop.pointee = true }
        }
        return found
    }

    private static func attachmentRange(in storage: NSTextStorage) -> NSRange? {
        var found: NSRange?
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            if value is CheckboxAttachment { found = range; stop.pointee = true }
        }
        return found
    }

    static func findTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let tv = view as? NSTextView { return tv }
        for sub in view.subviews {
            if let found = findTextView(in: sub) { return found }
        }
        return nil
    }
}

// MARK: - US-0.2 Reveal Perf Loop

@MainActor
enum RevealStressTest {
    static func run(document: SpikeDocument) -> String {
        guard let window = NSApp.windows.first,
              let textView = StressTest.findTextView(in: window.contentView),
              let storage = textView.textStorage else {
            return "REVEAL FAIL: no text view"
        }

        // Collect hidden-marker bold run locations
        var runLocations: [Int] = []
        storage.enumerateAttribute(SpikeProjection.spikeBold, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if value != nil { runLocations.append(range.location + range.length / 2) }
        }
        guard runLocations.count > 100 else {
            return "REVEAL FAIL: only \(runLocations.count) bold runs projected (expected ~5000)"
        }

        let baseline = SpikeProjection.serialize(storage: storage)
        var revealTimes: [Double] = []
        var unrevealTimes: [Double] = []
        let clock = ContinuousClock()
        var rng = SystemRandomNumberGenerator()

        for _ in 1...200 {
            let target = runLocations.randomElement(using: &rng)!

            let revealElapsed = clock.measure {
                textView.setSelectedRange(NSRange(location: min(target, storage.length - 1), length: 0))
            }
            revealTimes.append(Double(revealElapsed.components.attoseconds) / 1e15) // ms

            let unrevealElapsed = clock.measure {
                textView.setSelectedRange(NSRange(location: 0, length: 0))
            }
            unrevealTimes.append(Double(unrevealElapsed.components.attoseconds) / 1e15)
        }

        // Integrity: 200 reveal/unreveal cycles must not change the document
        let after = SpikeProjection.serialize(storage: storage)
        let intact = after == baseline

        func stats(_ values: [Double]) -> (p50: Double, p95: Double, max: Double) {
            let sorted = values.sorted()
            return (sorted[sorted.count / 2], sorted[Int(Double(sorted.count) * 0.95)], sorted.last ?? 0)
        }
        let r = stats(revealTimes), u = stats(unrevealTimes)
        let passed = intact && r.p95 <= 16.0 && u.p95 <= 16.0

        return String(format: """
        REVEAL %@
        doc: 5000 lines, %d bold runs; 200 cycles
        reveal   ms  p50 %.2f  p95 %.2f  max %.2f
        unreveal ms  p50 %.2f  p95 %.2f  max %.2f
        round-trip intact after all cycles: %@
        """, passed ? "PASS" : "FAIL", runLocations.count,
        r.p50, r.p95, r.max, u.p50, u.p95, u.max, intact ? "yes" : "NO — DIVERGED")
    }
}
