import Foundation
import aimdRenderer
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Element Edit

/// A typed edit request produced by the AI tool: the element (as detected in
/// the tool's content snapshot) plus the intent. Routed through
/// InteractionHandler, which re-locates the element in fresh disk content —
/// the snapshot's ranges are never applied to the file directly.
enum ElementEdit: Sendable {
    case checkbox(CheckboxElement, check: Bool)
    case choice(ChoiceElement, optionIndex: Int)
    case review(ReviewElement, optionIndex: Int)
    case fillIn(FillInElement, value: String)
    case feedback(FeedbackElement, text: String)
}

// MARK: - Edit Interactive Elements Tool

/// FM tool that lets the AI edit interactive elements in the current document.
/// The AI can toggle checkboxes, select choices, fill in placeholders, etc.
@available(macOS 26, *)
final class EditInteractiveElementsTool: Tool, @unchecked Sendable {
    let name = "editInteractiveElements"
    let description = "Edit interactive elements in the current markdown document. Use this to toggle checkboxes, select choices, fill in placeholders, set reviews, or add feedback."

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

    /// Callback to apply edits — must be called on MainActor.
    /// Receives the typed edit, the content snapshot the element was detected
    /// in (for re-location anchoring), and the file URL. Returns new content.
    var onEdit: (@Sendable @MainActor (ElementEdit, String, URL) async throws -> String)?

    func call(arguments: Arguments) async throws -> String {
        // Snapshot mutable state on MainActor before doing work
        let (content, url, editHandler) = await MainActor.run { (documentContent, fileURL, onEdit) }

        let elements = InteractiveElementDetector.detect(in: content)

        guard arguments.elementIndex >= 0, arguments.elementIndex < elements.count else {
            return "Error: Element index \(arguments.elementIndex) out of range (document has \(elements.count) elements)"
        }

        guard let url else {
            return "Error: No file URL available"
        }

        let element = elements[arguments.elementIndex]

        switch arguments.editType {
        case .checkbox:
            guard case .checkbox(let cb) = element else {
                return "Error: Element at index \(arguments.elementIndex) is not a checkbox"
            }
            let shouldCheck = arguments.value.lowercased() == "true" || arguments.value == "x"
            if cb.isChecked != shouldCheck {
                return await applyEdit(.checkbox(cb, check: shouldCheck), snapshot: content, to: url, handler: editHandler)
            } else {
                return "Checkbox already \(shouldCheck ? "checked" : "unchecked")"
            }

        case .choice:
            guard case .choice(let ch) = element else {
                return "Error: Element at index \(arguments.elementIndex) is not a choice"
            }
            guard let optionIndex = Int(arguments.value),
                  optionIndex >= 0, optionIndex < ch.options.count else {
                return "Error: Invalid option index '\(arguments.value)' (choice has \(ch.options.count) options)"
            }
            if ch.selectedIndex == optionIndex {
                return "Option already selected"
            }
            return await applyEdit(.choice(ch, optionIndex: optionIndex), snapshot: content, to: url, handler: editHandler)

        case .review:
            guard case .review(let rv) = element else {
                return "Error: Element at index \(arguments.elementIndex) is not a review"
            }
            guard let optionIndex = Int(arguments.value),
                  optionIndex >= 0, optionIndex < rv.options.count else {
                return "Error: Invalid option index '\(arguments.value)' (review has \(rv.options.count) options)"
            }
            if rv.options[optionIndex].isSelected {
                return "Review already set"
            }
            return await applyEdit(.review(rv, optionIndex: optionIndex), snapshot: content, to: url, handler: editHandler)

        case .fillIn:
            guard case .fillIn(let fi) = element else {
                return "Error: Element at index \(arguments.elementIndex) is not a fill-in"
            }
            return await applyEdit(.fillIn(fi, value: arguments.value), snapshot: content, to: url, handler: editHandler)

        case .feedback:
            guard case .feedback(let fb) = element else {
                return "Error: Element at index \(arguments.elementIndex) is not a feedback element"
            }
            return await applyEdit(.feedback(fb, text: arguments.value), snapshot: content, to: url, handler: editHandler)
        }
    }

    private func applyEdit(
        _ edit: ElementEdit,
        snapshot: String,
        to url: URL,
        handler: (@Sendable @MainActor (ElementEdit, String, URL) async throws -> String)?
    ) async -> String {
        guard let handler else {
            return "Error: Edit handler not configured"
        }
        do {
            let newContent = try await handler(edit, snapshot, url)
            await MainActor.run { documentContent = newContent }
            return "Edit applied successfully"
        } catch {
            return "Error applying edit: \(error.localizedDescription)"
        }
    }
}
