import Foundation
import aimdRenderer
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Edit Interactive Elements Tool

/// FM tool that lets the AI edit interactive elements in the current document.
/// The AI can toggle checkboxes, select choices, fill in placeholders, etc.
@available(macOS 26, *)
final class EditInteractiveElementsTool: Tool, @unchecked Sendable {
    let name = "editInteractiveElements"
    let description = """
        Edit interactive elements in the current markdown document. \
        Use this to toggle checkboxes, select choices, fill in \
        placeholders, set reviews, or add feedback.
        """

    @Generable
    struct Arguments {
        @Guide(description: "The type of edit: 'checkbox', 'choice', 'review', 'fillIn', or 'feedback'")
        var editType: EditType

        @Guide(description: "Zero-based index of the element in the document's element list")
        var elementIndex: Int

        @Guide(description: "For checkbox: 'true' or 'false'. For choice/review: the option index as string. For fillIn/feedback: the text value.")
        var value: String

        @Generable
        enum EditType {
            case checkbox
            case choice
            case review
            case fillIn
            case feedback
        }
    }

    // SAFETY: All three properties are only written from @MainActor (ChatService)
    // and read from call() which snapshots them via MainActor.run before use.
    // @unchecked Sendable is safe because call() hops to MainActor to read state.

    /// Current document content — updated by ChatService before each session
    var documentContent: String = ""

    /// File URL for write-back
    var fileURL: URL?

    /// Callback to apply edits — must be called on MainActor
    var onEdit: (@Sendable @MainActor (InteractiveEdit, URL) async throws -> String)?

    func call(arguments: Arguments) async throws -> String {
        let (content, url, editHandler) = await MainActor.run { (documentContent, fileURL, onEdit) }
        let elements = InteractiveElementDetector.detect(in: content)

        guard arguments.elementIndex >= 0, arguments.elementIndex < elements.count else {
            return "Error: Element index \(arguments.elementIndex) out of range (document has \(elements.count) elements)"
        }
        guard let url else { return "Error: No file URL available" }

        let element = elements[arguments.elementIndex]
        let index = arguments.elementIndex

        switch arguments.editType {
        case .checkbox: return await editCheckbox(element, index: index, value: arguments.value, url: url, handler: editHandler)
        case .choice:   return await editChoice(element, index: index, value: arguments.value, url: url, handler: editHandler)
        case .review:   return await editReview(element, index: index, value: arguments.value, url: url, handler: editHandler)
        case .fillIn:   return await editFillIn(element, index: index, value: arguments.value, url: url, handler: editHandler)
        case .feedback: return await editFeedback(element, index: index, value: arguments.value, url: url, handler: editHandler)
        }
    }

    // MARK: - Per-Edit-Type Handlers

    private typealias EditHandler = (@Sendable @MainActor (InteractiveEdit, URL) async throws -> String)?

    private func editCheckbox(_ element: InteractiveElement, index: Int, value: String, url: URL, handler: EditHandler) async -> String {
        guard case .checkbox(let cb) = element else {
            return "Error: Element at index \(index) is not a checkbox"
        }
        let shouldCheck = value.lowercased() == "true" || value == "x"
        guard cb.isChecked != shouldCheck else {
            return "Checkbox already \(shouldCheck ? "checked" : "unchecked")"
        }
        let edit = InteractiveEdit.replace(range: cb.checkRange, newText: shouldCheck ? "x" : " ")
        return await applyEdit(edit, to: url, handler: handler)
    }

    private func editChoice(_ element: InteractiveElement, index: Int, value: String, url: URL, handler: EditHandler) async -> String {
        guard case .choice(let ch) = element else {
            return "Error: Element at index \(index) is not a choice"
        }
        guard let optionIndex = Int(value),
              optionIndex >= 0, optionIndex < ch.options.count else {
            return "Error: Invalid option index '\(value)' (choice has \(ch.options.count) options)"
        }
        var replacements: [(range: Range<String.Index>, newText: String)] = []
        for (i, option) in ch.options.enumerated() {
            let newChar = (i == optionIndex) ? "x" : " "
            if (option.isSelected ? "x" : " ") != newChar {
                replacements.append((range: option.checkRange, newText: String(newChar)))
            }
        }
        guard !replacements.isEmpty else { return "Option already selected" }
        return await applyEdit(InteractiveEdit.replaceMultiple(replacements), to: url, handler: handler)
    }

    private func editReview(_ element: InteractiveElement, index: Int, value: String, url: URL, handler: EditHandler) async -> String {
        guard case .review(let rv) = element else {
            return "Error: Element at index \(index) is not a review"
        }
        guard let optionIndex = Int(value),
              optionIndex >= 0, optionIndex < rv.options.count else {
            return "Error: Invalid option index '\(value)' (review has \(rv.options.count) options)"
        }
        let dateString = Self.todayString()
        var replacements: [(range: Range<String.Index>, newText: String)] = []
        for (i, option) in rv.options.enumerated() {
            if i == optionIndex {
                replacements.append((range: option.range, newText: "[x] \(option.status.rawValue) — \(dateString)"))
            } else if option.isSelected {
                replacements.append((range: option.range, newText: "[ ] \(option.status.rawValue)"))
            }
        }
        guard !replacements.isEmpty else { return "Review already set" }
        return await applyEdit(InteractiveEdit.replaceMultiple(replacements), to: url, handler: handler)
    }

    private func editFillIn(_ element: InteractiveElement, index: Int, value: String, url: URL, handler: EditHandler) async -> String {
        guard case .fillIn(let fi) = element else {
            return "Error: Element at index \(index) is not a fill-in"
        }
        return await applyEdit(InteractiveEdit.replace(range: fi.range, newText: value), to: url, handler: handler)
    }

    private func editFeedback(_ element: InteractiveElement, index: Int, value: String, url: URL, handler: EditHandler) async -> String {
        guard case .feedback(let fb) = element else {
            return "Error: Element at index \(index) is not a feedback element"
        }
        let newComment = "<!-- feedback: \(value) -->"
        return await applyEdit(InteractiveEdit.replace(range: fb.range, newText: newComment), to: url, handler: handler)
    }

    private func applyEdit(
        _ edit: InteractiveEdit,
        to url: URL,
        handler: (@Sendable @MainActor (InteractiveEdit, URL) async throws -> String)?
    ) async -> String {
        guard let handler else {
            return "Error: Edit handler not configured"
        }
        do {
            let newContent = try await handler(edit, url)
            await MainActor.run { documentContent = newContent }
            return "Edit applied successfully"
        } catch {
            return "Error applying edit: \(error.localizedDescription)"
        }
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
