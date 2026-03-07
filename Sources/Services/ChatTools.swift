import Foundation
import aimdRenderer
import FoundationModels

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

    /// Current document content — updated by ChatService before each session
    var documentContent: String = ""

    /// File URL for write-back
    var fileURL: URL?

    /// Callback to apply edits — must be called on MainActor
    var onEdit: (@Sendable @MainActor (InteractiveEdit, URL) async throws -> String)?

    /// Callback to show upgrade popover from the AI tool context
    var onShowUpgradePrompt: (@MainActor () -> Void)?

    func call(arguments: Arguments) async throws -> String {
        // Gate: non-checkbox edits require Pro
        if arguments.editType != .checkbox {
            let isUnlocked = await MainActor.run { StoreService.shared.isUnlocked }
            if !isUnlocked {
                await MainActor.run { onShowUpgradePrompt?() }
                return "This feature requires Pixley Pro. The user was shown the upgrade prompt. Pixley Pro unlocks interactive element editing (choices, fill-ins, reviews, feedback, status, and more) for a one-time purchase."
            }
        }

        let elements = InteractiveElementDetector.detect(in: documentContent)

        guard arguments.elementIndex >= 0, arguments.elementIndex < elements.count else {
            return "Error: Element index \(arguments.elementIndex) out of range (document has \(elements.count) elements)"
        }

        guard let url = fileURL else {
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
                let newChar = shouldCheck ? "x" : " "
                let edit = InteractiveEdit.replace(range: cb.checkRange, newText: newChar)
                return await applyEdit(edit, to: url)
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
            var replacements: [(range: Range<String.Index>, newText: String)] = []
            for (i, option) in ch.options.enumerated() {
                let newChar = (i == optionIndex) ? "x" : " "
                let currentChar = option.isSelected ? "x" : " "
                if String(newChar) != String(currentChar) {
                    replacements.append((range: option.checkRange, newText: String(newChar)))
                }
            }
            if !replacements.isEmpty {
                let edit = InteractiveEdit.replaceMultiple(replacements)
                return await applyEdit(edit, to: url)
            } else {
                return "Option already selected"
            }

        case .review:
            guard case .review(let rv) = element else {
                return "Error: Element at index \(arguments.elementIndex) is not a review"
            }
            guard let optionIndex = Int(arguments.value),
                  optionIndex >= 0, optionIndex < rv.options.count else {
                return "Error: Invalid option index '\(arguments.value)' (review has \(rv.options.count) options)"
            }
            let dateString = Self.todayString()
            var replacements: [(range: Range<String.Index>, newText: String)] = []
            for (i, option) in rv.options.enumerated() {
                if i == optionIndex {
                    let newLine = "[x] \(option.status.rawValue) — \(dateString)"
                    replacements.append((range: option.range, newText: newLine))
                } else if option.isSelected {
                    let newLine = "[ ] \(option.status.rawValue)"
                    replacements.append((range: option.range, newText: newLine))
                }
            }
            if !replacements.isEmpty {
                let edit = InteractiveEdit.replaceMultiple(replacements)
                return await applyEdit(edit, to: url)
            } else {
                return "Review already set"
            }

        case .fillIn:
            guard case .fillIn(let fi) = element else {
                return "Error: Element at index \(arguments.elementIndex) is not a fill-in"
            }
            let edit = InteractiveEdit.replace(range: fi.range, newText: arguments.value)
            return await applyEdit(edit, to: url)

        case .feedback:
            guard case .feedback(let fb) = element else {
                return "Error: Element at index \(arguments.elementIndex) is not a feedback element"
            }
            let newComment = "<!-- feedback: \(arguments.value) -->"
            let edit = InteractiveEdit.replace(range: fb.range, newText: newComment)
            return await applyEdit(edit, to: url)
        }
    }

    private func applyEdit(_ edit: InteractiveEdit, to url: URL) async -> String {
        guard let onEdit else {
            return "Error: Edit handler not configured"
        }
        do {
            let newContent = try await onEdit(edit, url)
            documentContent = newContent
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
