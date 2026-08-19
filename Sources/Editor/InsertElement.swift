import AppKit
import SwiftUI

/// The interactive elements the Insert menu can author (G5, US-5.1 / #109).
/// Each inserts detector-recognized markdown at the caret through the editor's
/// normal edit path (`insertText` → engine binding → MarkdownDocument →
/// autosave), so it's undoable and round-trips. Shared so a future toolbar /
/// palette (D4) calls the same code.
enum InsertElement: String, CaseIterable {
    case addComment, checkbox, choice, fillInText, fillInDate, status, review, feedback

    var title: String {
        switch self {
        case .addComment: return "Add Comment"
        case .checkbox:   return "Checkbox"
        case .choice:     return "Choice (Radio)"
        case .fillInText: return "Fill-in"
        case .fillInDate: return "Fill-in Date"
        case .status:     return "Status"
        case .review:     return "Review Block"
        case .feedback:   return "Feedback"
        }
    }

    /// SF Symbol for the window-chrome insert toolbar.
    var icon: String {
        switch self {
        case .addComment: return "text.bubble"
        case .checkbox:   return "checkmark.square"
        case .choice:     return "smallcircle.filled.circle"
        case .fillInText: return "character.textbox"
        case .fillInDate: return "calendar"
        case .status:     return "flag"
        case .review:     return "checkmark.seal"
        case .feedback:   return "bubble.left"
        }
    }

    /// ⌥⌘-based to avoid the app's existing ⌘/⇧⌘ shortcuts.
    var shortcut: KeyEquivalent {
        switch self {
        case .addComment: return "c"
        case .checkbox:   return "k"
        case .choice:     return "r"
        case .fillInText: return "f"
        case .fillInDate: return "y" // not "d": ⌥⌘D is the macOS hide-Dock shortcut
        case .status:     return "s"
        case .review:     return "v"
        case .feedback:   return "b"
        }
    }

    /// Block-level elements start on their own line so they don't split prose.
    private var isBlock: Bool {
        switch self {
        case .fillInText, .fillInDate, .addComment: return false
        default: return true
        }
    }

    /// The markdown to insert and, optionally, a sub-range within it to select
    /// (so the user can type over a placeholder immediately). `selectedText` is
    /// the editor's current selection, used by Add Comment to wrap it.
    func snippet(selectedText: String) -> (text: String, select: NSRange?) {
        switch self {
        case .checkbox:
            let t = "- [ ] Task"
            return (t, (t as NSString).range(of: "Task")) // select the placeholder label
        case .choice:
            // One option per blockquote line (readable, matches the "+" add).
            let t = "> [ ] Option A\n> [ ] Option B"
            return (t, (t as NSString).range(of: "Option A"))
        case .fillInText:
            let t = "[[enter value]]"
            return (t, (t as NSString).range(of: "enter value"))
        case .fillInDate:
            let t = "[[date: ]]"
            return (t, NSRange(location: 8, length: 0)) // caret after "date: "
        case .status:
            return ("<!-- status: TODO / IN PROGRESS / DONE -->\n**Status:** TODO", nil)
        case .review:
            return ("> - [ ] APPROVED\n> - [ ] PASS\n> - [ ] FAIL\n> - [ ] N/A", nil)
        case .feedback:
            return ("<!-- feedback -->", nil)
        case .addComment:
            if !selectedText.isEmpty {
                // Wrap the selection as a CriticMarkup highlight + comment.
                let t = "{==\(selectedText)==}{>>comment<<}"
                return (t, (t as NSString).range(of: "comment"))
            }
            return ("<!-- feedback -->", nil)
        }
    }

    // MARK: - Insertion

    /// Inserts this element at the active editor's caret. Returns false when no
    /// editable editor is focused (menu item is disabled in that case anyway).
    @discardableResult
    @MainActor
    static func insert(_ element: InsertElement) -> Bool {
        guard let window = NSApp.keyWindow, let tv = editorTextView(in: window) else { return false }
        let full = tv.string as NSString
        let sel = tv.selectedRange()
        let selectedText = sel.length > 0 ? full.substring(with: sel) : ""

        var (text, select) = element.snippet(selectedText: selectedText)
        // Block elements go on their own line: prepend a newline if the caret
        // isn't already at the start of a line.
        if element.isBlock, sel.location > 0, full.character(at: sel.location - 1) != 10 {
            text = "\n" + text
            if let s = select { select = NSRange(location: s.location + 1, length: s.length) }
        }

        guard tv.shouldChangeText(in: sel, replacementString: text) else { return false }
        tv.insertText(text, replacementRange: sel)

        // Place the caret in the natural edit spot.
        if let s = select {
            tv.setSelectedRange(NSRange(location: sel.location + s.location, length: s.length))
        } else {
            tv.setSelectedRange(NSRange(location: sel.location + (text as NSString).length, length: 0))
        }
        window.makeFirstResponder(tv)
        return true
    }

    /// The editable editor text view: the current first responder if it's one,
    /// otherwise the first editable multi-line text view in the window (skips
    /// the chat input / find field, which aren't the document editor).
    @MainActor
    private static func editorTextView(in window: NSWindow) -> NSTextView? {
        if let tv = window.firstResponder as? NSTextView, tv.isEditable { return tv }
        return firstEditableTextView(in: window.contentView)
    }

    @MainActor
    private static func firstEditableTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let tv = view as? NSTextView, tv.isEditable, tv.isRichText { return tv }
        for sub in view.subviews {
            if let found = firstEditableTextView(in: sub) { return found }
        }
        return nil
    }
}
