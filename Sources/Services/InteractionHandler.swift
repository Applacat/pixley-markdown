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

    /// Writes content to a file with security-scoped access on the parent directory.
    /// Ensures write permission for files in subfolders of the sandbox-granted directory.
    private func secureWrite(_ content: String, to url: URL) async throws {
        let parentDir = url.deletingLastPathComponent()
        let hasAccess = parentDir.startAccessingSecurityScopedResource()
        defer { if hasAccess { parentDir.stopAccessingSecurityScopedResource() } }

        try await Task.detached(priority: .userInitiated) {
            try content.write(to: url, atomically: true, encoding: .utf8)
        }.value
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
        // Step 1: Suppress FileWatcher EARLY with longer window to cover atomic writes
        // Atomic writes can trigger multiple DispatchSource events (write + rename + delete),
        // and macOS may buffer/delay these events, so we need a generous window.
        // Extended to 1.0 second to handle slow disk I/O and event coalescing.
        fileWatcher?.suppressChanges(for: 1.0)

        // Step 2: Read + compute edit off main thread (no file write yet)
        let newContent = try await Task.detached(priority: .userInitiated) {
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

            return newContent
        }.value

        // Step 3: Write atomically with security-scoped access
        do {
            try await secureWrite(newContent, to: url)
        } catch {
            throw WriteError.writeFailed(url, error)
        }

        // Step 4: Update in-memory state (main actor)
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
        // Re-detect from fresh file content to avoid stale range corruption
        fileWatcher?.suppressChanges(for: 1.0)

        let newContent = try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: url)
            guard let currentContent = String(data: data, encoding: .utf8) else {
                throw WriteError.readFailed(url, NSError(domain: "InteractionHandler", code: 1))
            }

            // Re-detect elements from fresh content
            let elements = InteractiveElementDetector.detect(in: currentContent)
            guard let freshChoice = elements.compactMap({ element -> ChoiceElement? in
                if case .choice(let ch) = element { return ch }
                return nil
            }).first(where: { $0.options.count == choice.options.count }) else {
                throw WriteError.rangeMismatch
            }

            var modified = currentContent
            // Process in reverse to preserve indices
            for i in (0..<freshChoice.options.count).reversed() {
                let option = freshChoice.options[i]
                let newChar = (i == optionIndex) ? "x" : " "
                let currentChar = option.isSelected ? "x" : " "
                if String(newChar) != String(currentChar) {
                    modified.replaceSubrange(option.checkRange, with: String(newChar))
                }
            }
            return modified
        }.value

        try await secureWrite(newContent, to: url)

        await MainActor.run {
            onContentUpdated?(newContent)
        }
    }

    /// Replaces a fill-in placeholder with a value.
    func fillIn(
        _ element: FillInElement,
        value: String,
        in url: URL,
        fileWatcher: FileWatcher? = nil,
        onContentUpdated: ((String) -> Void)? = nil
    ) async throws {
        // Wrap value in [[ ]] so it stays detectable as a fill-in for re-editing
        let wrapped = "[[\(value)]]"
        try await apply(
            edit: .replace(range: element.range, newText: wrapped),
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

        // Re-detect from fresh file content to avoid stale range corruption
        fileWatcher?.suppressChanges(for: 1.0)

        let newContent = try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: url)
            guard let currentContent = String(data: data, encoding: .utf8) else {
                throw WriteError.readFailed(url, NSError(domain: "InteractionHandler", code: 1))
            }

            // Re-detect elements from fresh content
            let elements = InteractiveElementDetector.detect(in: currentContent)
            guard let freshReview = elements.compactMap({ element -> ReviewElement? in
                if case .review(let rv) = element { return rv }
                return nil
            }).first(where: { $0.options.count == review.options.count }) else {
                throw WriteError.rangeMismatch
            }

            guard optionIndex < freshReview.options.count else {
                throw WriteError.rangeMismatch
            }

            var modified = currentContent
            // Process in reverse to preserve indices
            // Deselect ALL other options (not just currently selected) to enforce mutual exclusivity
            for i in (0..<freshReview.options.count).reversed() {
                let option = freshReview.options[i]
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
        }.value

        try await secureWrite(newContent, to: url)

        await MainActor.run {
            onContentUpdated?(newContent)
        }
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

    /// Adds a CriticMarkup comment to a text range. Wraps the selected text in `{==text==}{>>comment<<}`.
    func addComment(
        selectedText: String,
        comment: String,
        range: Range<String.Index>,
        in url: URL,
        fileWatcher: FileWatcher? = nil,
        onContentUpdated: ((String) -> Void)? = nil
    ) async throws {
        let replacement = "{==\(selectedText)==}{>>\(comment)<<}"
        try await apply(
            edit: .replace(range: range, newText: replacement),
            to: url,
            fileWatcher: fileWatcher,
            onContentUpdated: onContentUpdated
        )
    }

    /// Edits the comment text of a CriticMarkup highlight.
    /// Replaces the full `{==text==}{>>old comment<<}` with `{==text==}{>>new comment<<}`.
    func editComment(
        _ suggestion: SuggestionElement,
        newComment: String,
        in url: URL,
        fileWatcher: FileWatcher? = nil,
        onContentUpdated: ((String) -> Void)? = nil
    ) async throws {
        let highlightedText = suggestion.oldText ?? ""
        let replacement = "{==\(highlightedText)==}{>>\(newComment)<<}"
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
        // Re-detect from fresh file content to avoid stale range corruption
        fileWatcher?.suppressChanges(for: 1.0)

        let newContent = try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: url)
            guard let currentContent = String(data: data, encoding: .utf8) else {
                throw WriteError.readFailed(url, NSError(domain: "InteractionHandler", code: 1))
            }

            // Re-detect status elements from fresh content
            let elements = InteractiveElementDetector.detect(in: currentContent)
            guard let freshStatus = elements.compactMap({ element -> StatusElement? in
                if case .status(let st) = element { return st }
                return nil
            }).first(where: { $0.states == status.states }) else {
                throw WriteError.rangeMismatch
            }

            let label = "**Status:** \(newState)"

            var modified = currentContent
            modified.replaceSubrange(freshStatus.labelRange, with: label)
            return modified
        }.value

        try await secureWrite(newContent, to: url)

        await MainActor.run {
            onContentUpdated?(newContent)
        }
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
