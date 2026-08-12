import Foundation

/// The round-trip fidelity corpus (editor epic, guardrail 5): deliberately
/// gnarly documents that every editing surface must round-trip byte-exactly.
/// Lives in the main target (G4-P1) so both the package test suite
/// (`RoundTripCorpusTests`) and the app's runtime harnesses assert against
/// the SAME documents. Extend by appending — every consumer picks it up.
public enum RoundTripCorpus {

    public static let documents: [(name: String, content: String)] = [
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
}
