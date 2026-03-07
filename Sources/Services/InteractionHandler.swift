import Foundation
import aimdRenderer

// MARK: - Interactive Edit

/// A structured edit to apply to a markdown file.
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
/// 1. Always reads fresh from disk before modifying (never from NSTextStorage)
/// 2. Uses atomic writes to prevent corruption
/// 3. Suppresses FileWatcher to avoid reload pill for self-initiated writes
/// 4. Handles concurrent writes by re-reading disk
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

    /// Applies an edit to a file on disk.
    ///
    /// - Parameters:
    ///   - edit: The structured edit to apply
    ///   - url: The file URL to modify
    ///   - fileWatcher: Optional FileWatcher to suppress reload for this write
    ///   - onContentUpdated: Callback with the new file content (for updating in-memory state)
    /// - Throws: `WriteError` if the operation fails
    func apply(
        edit: InteractiveEdit,
        to url: URL,
        fileWatcher: FileWatcher? = nil,
        onContentUpdated: ((String) -> Void)? = nil
    ) async throws {
        // Step 1: Read fresh from disk
        let currentContent: String
        do {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                throw WriteError.readFailed(url, NSError(domain: "InteractionHandler", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid UTF-8 encoding"]))
            }
            currentContent = text
        } catch let error as WriteError {
            throw error
        } catch {
            throw WriteError.readFailed(url, error)
        }

        // Step 2: Apply the edit
        let newContent: String
        switch edit {
        case .replace(let range, let newText):
            guard range.lowerBound >= currentContent.startIndex,
                  range.upperBound <= currentContent.endIndex else {
                throw WriteError.rangeMismatch
            }
            var modified = currentContent
            modified.replaceSubrange(range, with: newText)
            newContent = modified

        case .replaceMultiple(let replacements):
            var modified = currentContent
            // Sort replacements in reverse order so earlier indices stay valid
            let sorted = replacements.sorted { $0.range.lowerBound > $1.range.lowerBound }
            for (range, newText) in sorted {
                guard range.lowerBound >= modified.startIndex,
                      range.upperBound <= modified.endIndex else {
                    throw WriteError.rangeMismatch
                }
                modified.replaceSubrange(range, with: newText)
            }
            newContent = modified
        }

        // Step 3: Suppress FileWatcher before writing
        fileWatcher?.suppressNextChange = true

        // Step 4: Write atomically
        do {
            try newContent.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            fileWatcher?.suppressNextChange = false
            throw WriteError.writeFailed(url, error)
        }

        // Step 5: Update in-memory state
        onContentUpdated?(newContent)
    }

    // MARK: - Convenience Methods

    /// Toggles a checkbox in a markdown file.
    func toggleCheckbox(
        _ checkbox: CheckboxElement,
        in url: URL,
        fileWatcher: FileWatcher? = nil,
        onContentUpdated: ((String) -> Void)? = nil
    ) async throws {
        let newChar = checkbox.isChecked ? " " : "x"
        try await apply(
            edit: .replace(range: checkbox.checkRange, newText: newChar),
            to: url,
            fileWatcher: fileWatcher,
            onContentUpdated: onContentUpdated
        )
    }

    /// Selects a choice option (radio behavior — deselects others).
    func selectChoice(
        optionIndex: Int,
        in choice: ChoiceElement,
        url: URL,
        fileWatcher: FileWatcher? = nil,
        onContentUpdated: ((String) -> Void)? = nil
    ) async throws {
        var replacements: [(range: Range<String.Index>, newText: String)] = []

        for (i, option) in choice.options.enumerated() {
            let newChar = (i == optionIndex) ? "x" : " "
            let currentChar = option.isSelected ? "x" : " "
            if String(newChar) != String(currentChar) {
                replacements.append((range: option.checkRange, newText: String(newChar)))
            }
        }

        guard !replacements.isEmpty else { return }

        try await apply(
            edit: .replaceMultiple(replacements),
            to: url,
            fileWatcher: fileWatcher,
            onContentUpdated: onContentUpdated
        )
    }

    /// Replaces a fill-in placeholder with a value.
    func fillIn(
        _ element: FillInElement,
        value: String,
        in url: URL,
        fileWatcher: FileWatcher? = nil,
        onContentUpdated: ((String) -> Void)? = nil
    ) async throws {
        try await apply(
            edit: .replace(range: element.range, newText: value),
            to: url,
            fileWatcher: fileWatcher,
            onContentUpdated: onContentUpdated
        )
    }

    /// Sets feedback text in a feedback comment.
    func setFeedback(
        _ element: FeedbackElement,
        text: String,
        in url: URL,
        fileWatcher: FileWatcher? = nil,
        onContentUpdated: ((String) -> Void)? = nil
    ) async throws {
        let newComment = "<!-- feedback: \(text) -->"
        try await apply(
            edit: .replace(range: element.range, newText: newComment),
            to: url,
            fileWatcher: fileWatcher,
            onContentUpdated: onContentUpdated
        )
    }

    // MARK: - Phase 3: Advanced Patterns

    /// Selects a review option (radio behavior) with date stamp and optional notes.
    ///
    /// The selected option gets `[x] STATUS — YYYY-MM-DD` (plus `: notes` if provided).
    /// Other options are deselected and their date/notes are cleared.
    func selectReview(
        optionIndex: Int,
        notes: String? = nil,
        in review: ReviewElement,
        url: URL,
        fileWatcher: FileWatcher? = nil,
        onContentUpdated: ((String) -> Void)? = nil
    ) async throws {
        let dateString = Self.todayString()
        var replacements: [(range: Range<String.Index>, newText: String)] = []

        for (i, option) in review.options.enumerated() {
            if i == optionIndex {
                // Build the selected line: `[x] STATUS — YYYY-MM-DD` or `[x] STATUS — YYYY-MM-DD: notes`
                var suffix = " \(option.status.rawValue) — \(dateString)"
                if let notes, !notes.isEmpty {
                    suffix += ": \(notes)"
                }
                let newLine = "[x]\(suffix)"
                // Replace from check bracket through end of option
                replacements.append((range: option.range, newText: newLine))
            } else if option.isSelected {
                // Deselect: strip date and notes, keep just `[ ] STATUS`
                let newLine = "[ ] \(option.status.rawValue)"
                replacements.append((range: option.range, newText: newLine))
            }
        }

        guard !replacements.isEmpty else { return }

        try await apply(
            edit: .replaceMultiple(replacements),
            to: url,
            fileWatcher: fileWatcher,
            onContentUpdated: onContentUpdated
        )
    }

    /// Accepts a CriticMarkup suggestion — applies the change to the file.
    func acceptSuggestion(
        _ suggestion: SuggestionElement,
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

        try await apply(
            edit: .replace(range: suggestion.range, newText: replacement),
            to: url,
            fileWatcher: fileWatcher,
            onContentUpdated: onContentUpdated
        )
    }

    /// Rejects a CriticMarkup suggestion — removes the markup, keeps original.
    func rejectSuggestion(
        _ suggestion: SuggestionElement,
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

        try await apply(
            edit: .replace(range: suggestion.range, newText: replacement),
            to: url,
            fileWatcher: fileWatcher,
            onContentUpdated: onContentUpdated
        )
    }

    /// Advances a status to the next state. Appends date for terminal states.
    func advanceStatus(
        _ status: StatusElement,
        to newState: String,
        in url: URL,
        fileWatcher: FileWatcher? = nil,
        onContentUpdated: ((String) -> Void)? = nil
    ) async throws {
        let isTerminal = (status.states.last == newState)
        var label = "**Status:** \(newState)"
        if isTerminal {
            label += " — \(Self.todayString())"
        }

        try await apply(
            edit: .replace(range: status.labelRange, newText: label),
            to: url,
            fileWatcher: fileWatcher,
            onContentUpdated: onContentUpdated
        )
    }

    /// Confirms a confidence indicator (sets to confirmed, preserves text).
    func confirmConfidence(
        _ element: ConfidenceElement,
        in url: URL,
        fileWatcher: FileWatcher? = nil,
        onContentUpdated: ((String) -> Void)? = nil
    ) async throws {
        let newMarker = "> [confidence: confirmed] \(element.text)"
        try await apply(
            edit: .replace(range: element.range, newText: newMarker),
            to: url,
            fileWatcher: fileWatcher,
            onContentUpdated: onContentUpdated
        )
    }

    /// Challenges a low-confidence indicator by appending a feedback comment after it.
    func challengeConfidence(
        _ element: ConfidenceElement,
        feedback: String,
        in url: URL,
        fileWatcher: FileWatcher? = nil,
        onContentUpdated: ((String) -> Void)? = nil
    ) async throws {
        let comment = "\n<!-- feedback: \(feedback) -->"
        // Insert the comment right after the confidence element's range
        try await apply(
            edit: .replace(range: element.range.upperBound..<element.range.upperBound, newText: comment),
            to: url,
            fileWatcher: fileWatcher,
            onContentUpdated: onContentUpdated
        )
    }

    // MARK: - Helpers

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
