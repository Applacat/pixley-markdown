import Foundation
import aimdRenderer

// MARK: - Interactive Edit

/// A structured edit to apply to a markdown file.
/// Retained for SelfDescribingElement's protocol surface; live write paths
/// use typed element methods with re-detection instead of raw ranges.
enum InteractiveEdit: Sendable {
    /// Replace a range of text with new content
    case replace(range: Range<String.Index>, newText: String)

    /// Replace multiple ranges atomically (applied in reverse order to preserve indices)
    case replaceMultiple([(range: Range<String.Index>, newText: String)])
}

// MARK: - Interaction Handler

/// Safely writes interactive element changes back to markdown files.
///
/// Design principles:
/// 1. Writes to the same file are serialized through a per-URL chain — two
///    rapid interactions never interleave their read-modify-write cycles.
/// 2. Every write re-reads the file and re-locates its target element via
///    `ElementRelocator` (same identity signature, nearest offset). Ranges
///    computed against displayed content are never applied to disk content.
/// 3. If the element can no longer be found, the write fails with
///    `rangeMismatch` ("Document changed externally") instead of writing blind.
/// 4. Atomic writes, with FileWatcher suppression settled on every path
///    (`selfWriteCompleted` / `selfWriteFailed`).
@MainActor
final class InteractionHandler {

    /// Errors that can occur during write-back
    enum WriteError: LocalizedError {
        case fileNotFound(URL)
        case readFailed(URL, Error)
        case rangeMismatch
        case writeFailed(URL, Error)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let url):
                return "File not found: \(url.lastPathComponent)"
            case .readFailed(let url, let error):
                return "Failed to read \(url.lastPathComponent): \(error.localizedDescription)"
            case .rangeMismatch:
                return "Document changed externally. Please try again."
            case .writeFailed(let url, let error):
                return "Failed to write \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Serialized Write Funnel

    /// The single write path (editor epic G1): resolves the live
    /// `MarkdownDocument` for the URL (created from the displayed content on
    /// first touch, synced by the load path thereafter) and performs the
    /// mutation through `SaveCoordinator` — serialized per document, computed
    /// against the MODEL's source (never a disk read), committed to the model,
    /// then written atomically with FileWatcher settlement.
    private func serializedWrite(
        to url: URL,
        displayedContent: String,
        fileWatcher: FileWatcher?,
        onContentUpdated: ((String) -> Void)?,
        compute: @escaping @Sendable (String) throws -> String
    ) async throws {
        let document = MarkdownDocumentRegistry.obtain(url: url, initialSource: displayedContent)
        try await SaveCoordinator.shared.perform(on: document, fileWatcher: fileWatcher, compute: compute)
        onContentUpdated?(document.source)
    }

    // MARK: - Core Patterns

    /// Toggles a checkbox. `displayedContent` is the content the element was
    /// detected in — used to anchor re-location in the fresh file content.
    func toggleCheckbox(
        _ checkbox: CheckboxElement,
        displayedContent: String,
        in url: URL,
        fileWatcher: FileWatcher? = nil,
        onContentUpdated: ((String) -> Void)? = nil
    ) async throws {
        let wasChecked = checkbox.isChecked
        try await serializedWrite(to: url, displayedContent: displayedContent, fileWatcher: fileWatcher, onContentUpdated: onContentUpdated) { current in
            guard let fresh = ElementRelocator.checkbox(
                checkbox, displayed: displayedContent, fresh: current
            ) else {
                throw WriteError.rangeMismatch
            }
            var modified = current
            modified.replaceSubrange(fresh.checkRange, with: wasChecked ? " " : "x")
            return modified
        }
    }

    /// Selects a choice option (radio behavior — deselects others).
    func selectChoice(
        optionIndex: Int,
        in choice: ChoiceElement,
        displayedContent: String,
        url: URL,
        fileWatcher: FileWatcher? = nil,
        onContentUpdated: ((String) -> Void)? = nil
    ) async throws {
        try await serializedWrite(to: url, displayedContent: displayedContent, fileWatcher: fileWatcher, onContentUpdated: onContentUpdated) { current in
            guard let fresh = ElementRelocator.choice(
                choice, displayed: displayedContent, fresh: current
            ) else {
                throw WriteError.rangeMismatch
            }
            var modified = current
            for i in (0..<fresh.options.count).reversed() {
                let option = fresh.options[i]
                let newChar = (i == optionIndex) ? "x" : " "
                let currentChar = option.isSelected ? "x" : " "
                if newChar != currentChar {
                    modified.replaceSubrange(option.checkRange, with: newChar)
                }
            }
            return modified
        }
    }

    /// Appends a new unselected option to a choice (authoring: the "+" affordance).
    /// Inserts `  [ ] New Option` right after the last option, so the choice
    /// stays on its line and re-detects with one more radio.
    func addChoiceOption(
        _ choice: ChoiceElement,
        displayedContent: String,
        url: URL,
        fileWatcher: FileWatcher? = nil,
        onContentUpdated: ((String) -> Void)? = nil
    ) async throws {
        try await serializedWrite(to: url, displayedContent: displayedContent, fileWatcher: fileWatcher, onContentUpdated: onContentUpdated) { current in
            guard let fresh = ElementRelocator.choice(
                choice, displayed: displayedContent, fresh: current
            ), let last = fresh.options.last else {
                throw WriteError.rangeMismatch
            }
            var modified = current
            // New option on its OWN blockquote line (readable; matches review).
            modified.insert(contentsOf: "\n> [ ] New Option", at: last.range.upperBound)
            return modified
        }
    }

    /// Replaces a fill-in placeholder with a value.
    func fillIn(
        _ element: FillInElement,
        value: String,
        displayedContent: String,
        in url: URL,
        fileWatcher: FileWatcher? = nil,
        onContentUpdated: ((String) -> Void)? = nil
    ) async throws {
        // Typed prefixes keep filled values re-detectable with their type
        // intact (#88/#106) — no content-guessing on the way back in.
        let safeValue = Self.sanitizeFillInValue(value)
        let wrapped: String
        switch element.type {
        case .file:
            wrapped = "[[file: \(safeValue)]]"
        case .folder:
            wrapped = "[[folder: \(safeValue)]]"
        case .date:
            wrapped = "[[date: \(safeValue)]]"
        case .text:
            wrapped = "[[text: \(safeValue)]]"
        }
        try await serializedWrite(to: url, displayedContent: displayedContent, fileWatcher: fileWatcher, onContentUpdated: onContentUpdated) { current in
            guard let fresh = ElementRelocator.fillIn(
                element, displayed: displayedContent, fresh: current
            ) else {
                throw WriteError.rangeMismatch
            }
            var modified = current
            modified.replaceSubrange(fresh.range, with: wrapped)
            return modified
        }
    }

    /// Sets feedback text in a feedback comment.
    func setFeedback(
        _ element: FeedbackElement,
        text: String,
        displayedContent: String,
        in url: URL,
        fileWatcher: FileWatcher? = nil,
        onContentUpdated: ((String) -> Void)? = nil
    ) async throws {
        let sanitized = Self.sanitizeNoteText(text)
        let newComment = "<!-- feedback: \(sanitized) -->"
        try await serializedWrite(to: url, displayedContent: displayedContent, fileWatcher: fileWatcher, onContentUpdated: onContentUpdated) { current in
            guard let fresh = ElementRelocator.feedback(
                element, displayed: displayedContent, fresh: current
            ) else {
                throw WriteError.rangeMismatch
            }
            var modified = current
            modified.replaceSubrange(fresh.range, with: newComment)
            return modified
        }
    }

    // MARK: - Spec 4 Controls

    /// Spec 4: Replaces a Spec 4 control element (slider, stepper, toggle, color picker)
    /// with a raw value. The pattern is consumed — controls are empty-state only (MVP).
    func replaceSpec4Element(
        _ element: InteractiveElement,
        with value: String,
        displayedContent: String,
        in url: URL,
        fileWatcher: FileWatcher? = nil,
        onContentUpdated: ((String) -> Void)? = nil
    ) async throws {
        try await serializedWrite(to: url, displayedContent: displayedContent, fileWatcher: fileWatcher, onContentUpdated: onContentUpdated) { current in
            guard let fresh = ElementRelocator.spec4(
                element, displayed: displayedContent, fresh: current
            ) else {
                throw WriteError.rangeMismatch
            }
            var modified = current
            modified.replaceSubrange(fresh.range, with: value)
            return modified
        }
    }

    /// Spec 4: Toggles an auditable checkbox. Action is "check" (appends date + optional note)
    /// or "uncheck" (removes date + note).
    func toggleAuditableCheckbox(
        _ element: AuditableCheckboxElement,
        action: String,
        note: String,
        displayedContent: String,
        in url: URL,
        fileWatcher: FileWatcher? = nil,
        onContentUpdated: ((String) -> Void)? = nil
    ) async throws {
        let sanitizedNote = Self.sanitizeNoteText(note)
        let today = Self.todayString()

        try await serializedWrite(to: url, displayedContent: displayedContent, fileWatcher: fileWatcher, onContentUpdated: onContentUpdated) { current in
            guard let fresh = ElementRelocator.auditableCheckbox(
                element, displayed: displayedContent, fresh: current
            ) else {
                throw WriteError.rangeMismatch
            }

            // Reconstruct the line: preserve the original list marker prefix (e.g. `- [`)
            let lineText = String(current[fresh.range])
            guard let openBracket = lineText.firstIndex(of: "[") else {
                throw WriteError.rangeMismatch
            }
            let prefix = String(lineText[lineText.startIndex...openBracket])
            let suffix = "] " // closing bracket + space

            let labelWithMarker = "\(fresh.label) (notes)"
            let newLine: String
            switch action {
            case "check":
                let stamp = sanitizedNote.isEmpty ? "— \(today)" : "— \(today): \(sanitizedNote)"
                newLine = "\(prefix)x\(suffix)\(labelWithMarker) \(stamp)"
            case "uncheck":
                newLine = "\(prefix) \(suffix)\(labelWithMarker)"
            default:
                throw WriteError.rangeMismatch
            }

            var modified = current
            modified.replaceSubrange(fresh.range, with: newLine)
            return modified
        }
    }

    /// Sanitizes a fill-in value so it cannot break the `[[...]]` grammar:
    /// the closing `]]` sequence is split, newlines flattened (#89).
    /// Single `]` characters are fine — the detector grammar allows them.
    static func sanitizeFillInValue(_ value: String) -> String {
        var clean = value.replacingOccurrences(of: "\n", with: " ")
        clean = clean.replacingOccurrences(of: "\r", with: " ")
        while clean.contains("]]") {
            clean = clean.replacingOccurrences(of: "]]", with: "] ]")
        }
        return clean
    }

    /// Sanitizes CriticMarkup comment text so it cannot terminate its own
    /// `{>>...<<}` span early (#89).
    static func sanitizeCommentText(_ text: String) -> String {
        var clean = text.replacingOccurrences(of: "\n", with: " ")
        clean = clean.replacingOccurrences(of: "\r", with: " ")
        clean = clean.replacingOccurrences(of: "<<", with: "«")
        clean = clean.replacingOccurrences(of: ">>", with: "»")
        return clean
    }

    /// Sanitizes note text to prevent HTML comment corruption, newline injection, and excessive length.
    static func sanitizeNoteText(_ text: String) -> String {
        var clean = text.trimmingCharacters(in: .whitespaces)
        clean = clean.replacingOccurrences(of: "\n", with: " ")
        clean = clean.replacingOccurrences(of: "\r", with: " ")
        clean = clean.replacingOccurrences(of: "-->", with: "—>")
        clean = clean.replacingOccurrences(of: "--", with: "—")
        if clean.count > 500 {
            clean = String(clean.prefix(500))
        }
        return clean
    }

    // MARK: - Phase 3: Advanced Patterns

    /// Selects a review option (radio behavior) with date stamp and optional notes.
    func selectReview(
        optionIndex: Int,
        notes: String? = nil,
        in review: ReviewElement,
        displayedContent: String,
        url: URL,
        fileWatcher: FileWatcher? = nil,
        onContentUpdated: ((String) -> Void)? = nil
    ) async throws {
        let dateString = Self.todayString()
        try await serializedWrite(to: url, displayedContent: displayedContent, fileWatcher: fileWatcher, onContentUpdated: onContentUpdated) { current in
            guard let fresh = ElementRelocator.review(
                review, displayed: displayedContent, fresh: current
            ) else {
                throw WriteError.rangeMismatch
            }
            var modified = current
            for i in (0..<fresh.options.count).reversed() {
                let option = fresh.options[i]
                if i == optionIndex {
                    var suffix = " \(option.status.rawValue) — \(dateString)"
                    if let notes, !notes.isEmpty {
                        suffix += ": \(notes)"
                    }
                    let newLine = "[x]\(suffix)"
                    modified.replaceSubrange(option.range, with: newLine)
                } else {
                    let newLine = "[ ] \(option.status.rawValue)"
                    modified.replaceSubrange(option.range, with: newLine)
                }
            }
            return modified
        }
    }

    /// Clears all review selections (deselects every option, removes date/notes).
    func clearReview(
        in review: ReviewElement,
        displayedContent: String,
        url: URL,
        fileWatcher: FileWatcher? = nil,
        onContentUpdated: ((String) -> Void)? = nil
    ) async throws {
        try await serializedWrite(to: url, displayedContent: displayedContent, fileWatcher: fileWatcher, onContentUpdated: onContentUpdated) { current in
            guard let fresh = ElementRelocator.review(
                review, displayed: displayedContent, fresh: current
            ) else {
                throw WriteError.rangeMismatch
            }
            var modified = current
            for i in (0..<fresh.options.count).reversed() {
                let option = fresh.options[i]
                let newLine = "[ ] \(option.status.rawValue)"
                modified.replaceSubrange(option.range, with: newLine)
            }
            return modified
        }
    }

    /// Accepts a CriticMarkup suggestion — applies the change to the file.
    func acceptSuggestion(
        _ suggestion: SuggestionElement,
        displayedContent: String,
        in url: URL,
        fileWatcher: FileWatcher? = nil,
        onContentUpdated: ((String) -> Void)? = nil
    ) async throws {
        let replacement: String
        switch suggestion.type {
        case .addition:
            // {++text++} → text
            replacement = suggestion.newText ?? ""
        case .deletion:
            // {--text--} → (removed)
            replacement = ""
        case .substitution:
            // {~~old~>new~~} → new
            replacement = suggestion.newText ?? ""
        case .highlight:
            // {==text==}{>>comment<<} → text
            replacement = suggestion.oldText ?? ""
        }
        try await replaceSuggestion(suggestion, with: replacement, displayedContent: displayedContent,
                                    in: url, fileWatcher: fileWatcher, onContentUpdated: onContentUpdated)
    }

    /// Rejects a CriticMarkup suggestion — removes the markup, keeps original.
    func rejectSuggestion(
        _ suggestion: SuggestionElement,
        displayedContent: String,
        in url: URL,
        fileWatcher: FileWatcher? = nil,
        onContentUpdated: ((String) -> Void)? = nil
    ) async throws {
        let replacement: String
        switch suggestion.type {
        case .addition:
            // {++text++} → (removed)
            replacement = ""
        case .deletion:
            // {--text--} → text (keep original)
            replacement = suggestion.oldText ?? ""
        case .substitution:
            // {~~old~>new~~} → old (keep original)
            replacement = suggestion.oldText ?? ""
        case .highlight:
            // {==text==}{>>comment<<} → text (keep highlighted text)
            replacement = suggestion.oldText ?? ""
        }
        try await replaceSuggestion(suggestion, with: replacement, displayedContent: displayedContent,
                                    in: url, fileWatcher: fileWatcher, onContentUpdated: onContentUpdated)
    }

    /// Edits the comment text of a CriticMarkup highlight.
    /// Replaces the full `{==text==}{>>old comment<<}` with `{==text==}{>>new comment<<}`.
    func editComment(
        _ suggestion: SuggestionElement,
        newComment: String,
        displayedContent: String,
        in url: URL,
        fileWatcher: FileWatcher? = nil,
        onContentUpdated: ((String) -> Void)? = nil
    ) async throws {
        let highlightedText = suggestion.oldText ?? ""
        let replacement = "{==\(highlightedText)==}{>>\(Self.sanitizeCommentText(newComment))<<}"
        try await replaceSuggestion(suggestion, with: replacement, displayedContent: displayedContent,
                                    in: url, fileWatcher: fileWatcher, onContentUpdated: onContentUpdated)
    }

    /// Shared suggestion write path: re-locates by type + old/new text, nearest offset.
    private func replaceSuggestion(
        _ suggestion: SuggestionElement,
        with replacement: String,
        displayedContent: String,
        in url: URL,
        fileWatcher: FileWatcher?,
        onContentUpdated: ((String) -> Void)?
    ) async throws {
        try await serializedWrite(to: url, displayedContent: displayedContent, fileWatcher: fileWatcher, onContentUpdated: onContentUpdated) { current in
            guard let fresh = ElementRelocator.suggestion(
                suggestion, displayed: displayedContent, fresh: current
            ) else {
                throw WriteError.rangeMismatch
            }
            var modified = current
            modified.replaceSubrange(fresh.range, with: replacement)
            return modified
        }
    }

    /// Adds a CriticMarkup comment to a text range. Wraps the selected text in `{==text==}{>>comment<<}`.
    /// The selection is re-anchored by its text: exact position if unchanged,
    /// else the nearest occurrence of the same text in the fresh content.
    func addComment(
        selectedText: String,
        comment: String,
        range: Range<String.Index>,
        displayedContent: String,
        in url: URL,
        fileWatcher: FileWatcher? = nil,
        onContentUpdated: ((String) -> Void)? = nil
    ) async throws {
        // A selection containing CriticMarkup delimiters can't be wrapped
        // without corrupting markup — refuse rather than write garbage (#89).
        guard !selectedText.contains("==}"), !selectedText.contains("{==") else {
            throw WriteError.rangeMismatch
        }
        let replacement = "{==\(selectedText)==}{>>\(Self.sanitizeCommentText(comment))<<}"
        try await serializedWrite(to: url, displayedContent: displayedContent, fileWatcher: fileWatcher, onContentUpdated: onContentUpdated) { current in
            guard let freshRange = ElementRelocator.selection(
                text: selectedText, staleRange: range, displayed: displayedContent, fresh: current
            ) else {
                throw WriteError.rangeMismatch
            }
            var modified = current
            modified.replaceSubrange(freshRange, with: replacement)
            return modified
        }
    }

    /// Advances a status to the next state.
    func advanceStatus(
        _ status: StatusElement,
        to newState: String,
        displayedContent: String,
        in url: URL,
        fileWatcher: FileWatcher? = nil,
        onContentUpdated: ((String) -> Void)? = nil
    ) async throws {
        try await serializedWrite(to: url, displayedContent: displayedContent, fileWatcher: fileWatcher, onContentUpdated: onContentUpdated) { current in
            guard let fresh = ElementRelocator.status(
                status, displayed: displayedContent, fresh: current
            ) else {
                throw WriteError.rangeMismatch
            }
            let label = "**Status:** \(newState)"
            var modified = current
            modified.replaceSubrange(fresh.labelRange, with: label)
            return modified
        }
    }

    /// Confirms a confidence indicator (sets to confirmed, preserves text).
    func confirmConfidence(
        _ element: ConfidenceElement,
        displayedContent: String,
        in url: URL,
        fileWatcher: FileWatcher? = nil,
        onContentUpdated: ((String) -> Void)? = nil
    ) async throws {
        let newMarker = "> [confidence: confirmed] \(element.text)"
        try await serializedWrite(to: url, displayedContent: displayedContent, fileWatcher: fileWatcher, onContentUpdated: onContentUpdated) { current in
            guard let fresh = ElementRelocator.confidence(
                element, displayed: displayedContent, fresh: current
            ) else {
                throw WriteError.rangeMismatch
            }
            var modified = current
            modified.replaceSubrange(fresh.range, with: newMarker)
            return modified
        }
    }

    /// Challenges a low-confidence indicator by appending a feedback comment after it.
    func challengeConfidence(
        _ element: ConfidenceElement,
        feedback: String,
        displayedContent: String,
        in url: URL,
        fileWatcher: FileWatcher? = nil,
        onContentUpdated: ((String) -> Void)? = nil
    ) async throws {
        let comment = "\n<!-- feedback: \(Self.sanitizeNoteText(feedback)) -->"
        try await serializedWrite(to: url, displayedContent: displayedContent, fileWatcher: fileWatcher, onContentUpdated: onContentUpdated) { current in
            guard let fresh = ElementRelocator.confidence(
                element, displayed: displayedContent, fresh: current
            ) else {
                throw WriteError.rangeMismatch
            }
            var modified = current
            modified.insert(contentsOf: comment, at: fresh.range.upperBound)
            return modified
        }
    }

    // MARK: - Gutter Comments

    /// Sets, replaces, or removes a gutter comment (`<!-- feedback: ... -->` on
    /// the line after the anchor). `commentText == nil` removes the comment.
    /// The anchor is re-located by its line text in the fresh content, so a
    /// document that shifted since render still gets the comment on the line
    /// the user clicked.
    func setGutterComment(
        lineNumber: Int,
        commentText: String?,
        displayedContent: String,
        in url: URL,
        fileWatcher: FileWatcher? = nil,
        onContentUpdated: ((String) -> Void)? = nil
    ) async throws {
        let displayedLines = displayedContent.components(separatedBy: "\n")
        // lineNumber is 1-based
        let staleLineIndex = lineNumber - 1
        guard staleLineIndex >= 0, staleLineIndex < displayedLines.count else {
            throw WriteError.rangeMismatch
        }
        let anchorText = displayedLines[staleLineIndex]
        let sanitized = commentText.map { Self.sanitizeNoteText($0) }

        try await serializedWrite(to: url, displayedContent: displayedContent, fileWatcher: fileWatcher, onContentUpdated: onContentUpdated) { current in
            var lines = current.components(separatedBy: "\n")
            guard let anchorIndex = ElementRelocator.anchorLine(
                text: anchorText,
                staleIndex: staleLineIndex,
                displayedLines: displayedLines,
                freshLines: lines
            ) else {
                throw WriteError.rangeMismatch
            }

            let nextIndex = anchorIndex + 1
            let nextIsComment = nextIndex < lines.count
                && lines[nextIndex].trimmingCharacters(in: .whitespaces).hasPrefix("<!-- feedback")

            if let text = sanitized {
                let commentTag = "<!-- feedback: \(text) -->"
                if nextIsComment {
                    lines[nextIndex] = commentTag
                } else {
                    lines.insert(commentTag, at: nextIndex)
                }
            } else if nextIsComment {
                lines.remove(at: nextIndex)
            }
            return lines.joined(separator: "\n")
        }
    }

    // MARK: - Helpers

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func todayString() -> String {
        dateFormatter.string(from: Date())
    }
}
