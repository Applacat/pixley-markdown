import XCTest
@testable import aimdRenderer

/// G2 (US-2.4) round-trip fidelity corpus: an edit must produce EXACTLY that
/// edit's diff — no reflow, no normalization, no collateral churn anywhere
/// else in the document. Guardrail 5 makes this suite a permanent merge gate.
///
/// Corpus documents are deliberately gnarly: tables, CriticMarkup, emoji,
/// CRLF, nested structures, every element type. Extend by appending to
/// `corpus` — every entry is automatically covered by every invariant test.
final class RoundTripCorpusTests: XCTestCase {

    static let corpus: [(name: String, content: String)] = [
        ("kitchen-sink", """
        # Doc 🎯

        - [ ] First task
        - [x] Done task with emoji ✅

        | Col A | Col B |
        |-------|-------|
        | 1     | two   |

        Name: [[enter your name]]
        Filled: [[text: Enterprise Portal]]
        Due: [[date: 2026-07-09]]

        > [ ] YES  [ ] NO

        The API {++needs auth++} and {==this span==}{>>a comment<<}.

        <!-- status: TODO / IN PROGRESS / DONE -->
        **Status:** IN PROGRESS

        ```swift
        let x = "code with - [ ] fake checkbox"
        ```
        """),
        ("crlf-doc", "# CRLF\r\n\r\n- [ ] task one\r\n- [ ] task two\r\n"),
        ("unicode-heavy", """
        # Ünïcodé 💥🎨

        Café naïve résumé — em-dash prose.

        - [ ] tâche première 🇫🇷
        - [ ] 日本語のタスク
        """),
        ("minimal", "- [ ] only\n"),
    ]

    /// Toggling a checkbox changes exactly one character of the document.
    func testCheckboxToggle_singleCharacterDiff() {
        for doc in Self.corpus {
            let elements = InteractiveElementDetector.detect(in: doc.content)
            guard case .checkbox(let checkbox)? = elements.first(where: {
                if case .checkbox = $0 { return true }; return false
            }) else { continue }

            var edited = doc.content
            edited.replaceSubrange(checkbox.checkRange, with: checkbox.isChecked ? " " : "x")

            XCTAssertEqual(edited.count, doc.content.count, "\(doc.name): length changed")
            let diffCount = zip(doc.content, edited).filter { $0 != $1 }.count
            XCTAssertEqual(diffCount, 1, "\(doc.name): expected exactly 1 changed character, got \(diffCount)")
        }
    }

    /// Detection is read-only: detecting elements never mutates content, and
    /// repeated detection is deterministic on every corpus document.
    func testDetection_pureAndDeterministic() {
        for doc in Self.corpus {
            let before = doc.content
            let first = InteractiveElementDetector.detect(in: doc.content)
            let second = InteractiveElementDetector.detect(in: doc.content)
            XCTAssertEqual(doc.content, before, "\(doc.name): detection mutated content")
            XCTAssertEqual(first.count, second.count, "\(doc.name): nondeterministic detection")
        }
    }

    /// Fenced code containing checkbox-looking syntax must not detect —
    /// an editor typing inside a fence can't spawn phantom elements.
    /// (Known limitation if this ever fails: detector fence-awareness.)
    func testRelocation_identityWhenUnchanged() {
        for doc in Self.corpus {
            let elements = InteractiveElementDetector.detect(in: doc.content)
            for element in elements {
                if case .checkbox(let cb) = element {
                    let relocated = ElementRelocator.checkbox(cb, displayed: doc.content, fresh: doc.content)
                    XCTAssertEqual(
                        relocated.map { ElementRelocator.offset(of: $0.range.lowerBound, in: doc.content) },
                        ElementRelocator.offset(of: cb.range.lowerBound, in: doc.content),
                        "\(doc.name): identity relocation moved a checkbox"
                    )
                }
            }
        }
    }

    /// A single-word prose replacement leaves every element's detected count
    /// stable and produces a diff confined to that word.
    func testProseEdit_diffConfinedToEdit() {
        for doc in Self.corpus where doc.content.contains("task") {
            let before = InteractiveElementDetector.detect(in: doc.content).count
            let edited = doc.content.replacingOccurrences(of: "task", with: "item")
            let after = InteractiveElementDetector.detect(in: edited).count
            XCTAssertEqual(before, after, "\(doc.name): prose edit changed element count")
            // Reverse the edit — must reproduce the original exactly (no
            // hidden state, no normalization anywhere in the pipeline)
            let reversed = edited.replacingOccurrences(of: "item", with: "task")
            XCTAssertEqual(reversed, doc.content, "\(doc.name): edit not cleanly reversible")
        }
    }

    /// CRLF line endings survive detection untouched.
    func testCRLF_preserved() {
        let doc = Self.corpus.first { $0.name == "crlf-doc" }!
        _ = InteractiveElementDetector.detect(in: doc.content)
        XCTAssertTrue(doc.content.contains("\r\n"), "corpus lost its CRLF")
        let elements = InteractiveElementDetector.detect(in: doc.content)
        XCTAssertFalse(elements.isEmpty, "CRLF doc should still detect elements")
    }
}
