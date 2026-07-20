import Foundation

// MARK: - Element Relocator

/// Re-locates an interactive element in freshly-read file content before a
/// write-back is applied.
///
/// Ranges captured at render time (`String.Index` into the *displayed* content)
/// must never be applied to a different string: the file may have changed on
/// disk since detection (AI edits are this app's core use case), and Swift
/// does not define cross-instance index use at all. Instead, every write path
/// re-detects against the current content and finds the element that best
/// corresponds to the one the user interacted with.
///
/// Matching strategy, in order:
/// 1. **Ordinal** — among candidates with the same identity signature, the
///    element's position in document order. If the user clicked the 2nd of
///    3 "Deploy" checkboxes and the fresh content still has 3, target the
///    2nd. Ordinals are invariant under upstream insertions/deletions, which
///    defeat offset proximity.
/// 2. **Nearest offset** — when the candidate count changed (an element was
///    added or removed), fall back to smallest |offset delta| from the
///    element's displayed position.
///
/// All functions are pure — (stale element, displayed content, fresh content)
/// in, candidate out — so the exact relocation behavior is unit-testable with
/// the real detector.
public enum ElementRelocator {

    /// Character offset of an index within the content that produced it.
    public static func offset(of index: String.Index, in content: String) -> Int {
        content.distance(from: content.startIndex, to: index)
    }

    // MARK: - Per-Type Relocation

    /// Checkbox: signature = label + checked state.
    public static func checkbox(
        _ stale: CheckboxElement,
        displayed: String,
        fresh: String
    ) -> CheckboxElement? {
        relocate(
            stale: stale, displayed: displayed, fresh: fresh,
            extract: { if case .checkbox(let e) = $0 { return e } else { return nil } },
            signatureMatches: { $0.label == stale.label && $0.isChecked == stale.isChecked },
            position: { $0.range.lowerBound }
        )
    }

    /// Auditable checkbox: signature = label + checked state.
    public static func auditableCheckbox(
        _ stale: AuditableCheckboxElement,
        displayed: String,
        fresh: String
    ) -> AuditableCheckboxElement? {
        relocate(
            stale: stale, displayed: displayed, fresh: fresh,
            extract: { if case .auditableCheckbox(let e) = $0 { return e } else { return nil } },
            signatureMatches: { $0.label == stale.label && $0.isChecked == stale.isChecked },
            position: { $0.range.lowerBound }
        )
    }

    /// Choice: signature = option count.
    public static func choice(
        _ stale: ChoiceElement,
        displayed: String,
        fresh: String
    ) -> ChoiceElement? {
        relocate(
            stale: stale, displayed: displayed, fresh: fresh,
            extract: { if case .choice(let e) = $0 { return e } else { return nil } },
            signatureMatches: { $0.options.count == stale.options.count },
            position: { $0.blockquoteRange.lowerBound }
        )
    }

    /// Review: signature = option count.
    public static func review(
        _ stale: ReviewElement,
        displayed: String,
        fresh: String
    ) -> ReviewElement? {
        relocate(
            stale: stale, displayed: displayed, fresh: fresh,
            extract: { if case .review(let e) = $0 { return e } else { return nil } },
            signatureMatches: { $0.options.count == stale.options.count },
            position: { $0.blockquoteRange.lowerBound }
        )
    }

    /// Fill-in: signature = type + hint.
    public static func fillIn(
        _ stale: FillInElement,
        displayed: String,
        fresh: String
    ) -> FillInElement? {
        relocate(
            stale: stale, displayed: displayed, fresh: fresh,
            extract: { if case .fillIn(let e) = $0 { return e } else { return nil } },
            signatureMatches: { $0.type == stale.type && $0.hint == stale.hint },
            position: { $0.range.lowerBound }
        )
    }

    /// Feedback: signature = existing text.
    public static func feedback(
        _ stale: FeedbackElement,
        displayed: String,
        fresh: String
    ) -> FeedbackElement? {
        relocate(
            stale: stale, displayed: displayed, fresh: fresh,
            extract: { if case .feedback(let e) = $0 { return e } else { return nil } },
            signatureMatches: { $0.existingText == stale.existingText },
            position: { $0.range.lowerBound }
        )
    }

    /// Suggestion (CriticMarkup): signature = type + old/new text.
    public static func suggestion(
        _ stale: SuggestionElement,
        displayed: String,
        fresh: String
    ) -> SuggestionElement? {
        relocate(
            stale: stale, displayed: displayed, fresh: fresh,
            extract: { if case .suggestion(let e) = $0 { return e } else { return nil } },
            signatureMatches: { $0.type == stale.type && $0.oldText == stale.oldText && $0.newText == stale.newText },
            position: { $0.range.lowerBound }
        )
    }

    /// Status machine: signature = state list.
    public static func status(
        _ stale: StatusElement,
        displayed: String,
        fresh: String
    ) -> StatusElement? {
        relocate(
            stale: stale, displayed: displayed, fresh: fresh,
            extract: { if case .status(let e) = $0 { return e } else { return nil } },
            signatureMatches: { $0.states == stale.states },
            position: { $0.labelRange.lowerBound }
        )
    }

    /// Confidence: signature = level + text.
    public static func confidence(
        _ stale: ConfidenceElement,
        displayed: String,
        fresh: String
    ) -> ConfidenceElement? {
        relocate(
            stale: stale, displayed: displayed, fresh: fresh,
            extract: { if case .confidence(let e) = $0 { return e } else { return nil } },
            signatureMatches: { $0.level == stale.level && $0.text == stale.text },
            position: { $0.range.lowerBound }
        )
    }

    /// Spec-4 control (slider/stepper/toggle/color picker): signature = kind.
    public static func spec4(
        _ stale: InteractiveElement,
        displayed: String,
        fresh: String
    ) -> InteractiveElement? {
        func sameKind(_ candidate: InteractiveElement) -> Bool {
            switch (candidate, stale) {
            case (.slider, .slider), (.stepper, .stepper),
                 (.toggle, .toggle), (.colorPicker, .colorPicker):
                return true
            default:
                return false
            }
        }
        return relocate(
            stale: stale, displayed: displayed, fresh: fresh,
            extract: { sameKind($0) ? $0 : nil },
            signatureMatches: { _ in true },
            position: { $0.range.lowerBound }
        )
    }

    // MARK: - Free-Text Anchors

    /// Re-locates a text selection by ordinal among occurrences of the same
    /// text, falling back to nearest offset when the occurrence count changed.
    /// Used by Add Comment, where the anchor is arbitrary selected prose.
    public static func selection(
        text: String,
        staleRange: Range<String.Index>,
        displayed: String,
        fresh: String
    ) -> Range<String.Index>? {
        guard !text.isEmpty else { return nil }
        let staleOffset = offset(of: staleRange.lowerBound, in: displayed)

        let displayedOccurrences = occurrences(of: text, in: displayed)
        let freshOccurrences = occurrences(of: text, in: fresh)
        guard !freshOccurrences.isEmpty else { return nil }

        if displayedOccurrences.count == freshOccurrences.count,
           let ordinal = displayedOccurrences.firstIndex(where: {
               offset(of: $0.lowerBound, in: displayed) == staleOffset
           }) {
            return freshOccurrences[ordinal]
        }

        return freshOccurrences.min { a, b in
            abs(offset(of: a.lowerBound, in: fresh) - staleOffset)
                < abs(offset(of: b.lowerBound, in: fresh) - staleOffset)
        }
    }

    /// Re-locates a line anchor by its text: same ordinal among matching lines
    /// when the match count is unchanged, else the matching line nearest the
    /// stale index. Used by gutter comments, which attach to a line number.
    public static func anchorLine(
        text: String,
        staleIndex: Int,
        displayedLines: [String],
        freshLines: [String]
    ) -> Int? {
        let displayedMatches = displayedLines.indices.filter { displayedLines[$0] == text }
        let freshMatches = freshLines.indices.filter { freshLines[$0] == text }
        guard !freshMatches.isEmpty else { return nil }

        if displayedMatches.count == freshMatches.count,
           let ordinal = displayedMatches.firstIndex(of: staleIndex) {
            return freshMatches[ordinal]
        }

        return freshMatches.min { abs($0 - staleIndex) < abs($1 - staleIndex) }
    }

    // MARK: - Private

    /// Shared strategy: ordinal among same-signature candidates when counts
    /// match, else nearest offset to the element's displayed position.
    private static func relocate<T>(
        stale: T,
        displayed: String,
        fresh: String,
        extract: (InteractiveElement) -> T?,
        signatureMatches: (T) -> Bool,
        position: (T) -> String.Index
    ) -> T? {
        let staleOffset = offset(of: position(stale), in: displayed)

        let displayedCandidates = InteractiveElementDetector.detect(in: displayed)
            .compactMap(extract).filter(signatureMatches)
        let freshCandidates = InteractiveElementDetector.detect(in: fresh)
            .compactMap(extract).filter(signatureMatches)
        guard !freshCandidates.isEmpty else { return nil }

        if displayedCandidates.count == freshCandidates.count,
           let ordinal = displayedCandidates.firstIndex(where: {
               offset(of: position($0), in: displayed) == staleOffset
           }) {
            return freshCandidates[ordinal]
        }

        return freshCandidates.min { a, b in
            abs(offset(of: position(a), in: fresh) - staleOffset)
                < abs(offset(of: position(b), in: fresh) - staleOffset)
        }
    }

    private static func occurrences(of text: String, in content: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var searchStart = content.startIndex
        while let found = content.range(of: text, range: searchStart..<content.endIndex) {
            result.append(found)
            if found.upperBound == content.endIndex { break }
            searchStart = content.index(after: found.lowerBound)
        }
        return result
    }
}
