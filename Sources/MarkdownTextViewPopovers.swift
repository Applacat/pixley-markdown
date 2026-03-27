import AppKit
import aimdRenderer

// MARK: - Popover Routing & Presentation

/// Extension extracting all popover show/routing logic from MarkdownNSTextView.
/// Keeps the main text view class focused on event handling and drawing.
extension MarkdownNSTextView {

    /// Returns the view-coordinate rect for a character range (for popover positioning).
    func glyphRect(for charRange: NSRange) -> NSRect? {
        guard let layoutManager, let textContainer else { return nil }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        return rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    /// Checks if the element needs an inline popover and shows it. Returns true if handled.
    func showElementPopover(_ element: InteractiveElement, optionIndex: Int?, at charRange: NSRange) -> Bool {
        switch element {
        case .fillIn(let fi):
            let isFilled = fi.value != nil
            switch fi.type {
            case .text:
                showInputPopover(for: element, at: charRange, config: InputPopoverConfig(
                    title: "Fill In",
                    subtitle: isFilled ? "Edit your response" : fi.hint,
                    fieldName: "value",
                    placeholder: isFilled ? "" : fi.hint,
                    initialValue: fi.value ?? ""
                ))
                return true
            case .date:
                showDatePickerPopover(for: element, at: charRange, existingDate: fi.value)
                return true
            case .file, .folder:
                // Filled file/folder: show text popover with current path for re-edit
                if isFilled {
                    showInputPopover(for: element, at: charRange, config: InputPopoverConfig(
                        title: fi.type == .file ? "File Path" : "Folder Path",
                        subtitle: "Edit path or click Submit to re-pick",
                        fieldName: "value",
                        initialValue: fi.value ?? ""
                    ))
                    return true
                }
                return false // Unfilled: NSOpenPanel handled by callback
            }

        case .feedback(let fb):
            showInputPopover(for: element, at: charRange, config: InputPopoverConfig(
                title: fb.existingText != nil ? "Edit Feedback" : "Leave Feedback",
                subtitle: "Your comment will be saved in the document.",
                fieldName: "text",
                initialValue: fb.existingText ?? "",
                multiline: true
            ))
            return true

        case .suggestion(let s):
            if s.type == .highlight {
                showCommentPopover(for: element, suggestion: s, at: charRange)
            } else {
                showSuggestionPopover(for: element, suggestion: s, at: charRange)
            }
            return true

        case .review(let rv):
            guard let optionIndex, optionIndex < rv.options.count else { return false }
            if rv.options[optionIndex].status.promptsForNotes {
                showInputPopover(for: element, at: charRange, config: InputPopoverConfig(
                    title: "Review: \(rv.options[optionIndex].status.rawValue)",
                    subtitle: "Add notes for this review status.",
                    fieldName: "notes",
                    multiline: true,
                    allowEmpty: true
                ), optionIndex: optionIndex)
                return true
            }
            return false

        case .confidence(let conf):
            if conf.level == .low {
                showInputPopover(for: element, at: charRange, config: InputPopoverConfig(
                    title: "Challenge AI Confidence",
                    subtitle: "Explain why you disagree with this assessment.",
                    fieldName: "challenge",
                    multiline: true
                ))
                return true
            }
            return false

        default:
            return false
        }
    }

    // MARK: - Input Popover

    /// Shows an inline text input popover at the element's position.
    func showInputPopover(for element: InteractiveElement, at charRange: NSRange, config: InputPopoverConfig, optionIndex: Int? = nil) {
        inputPopover?.close()

        let popover = NSPopover()
        popover.behavior = .transient

        let controller = InputPopoverController(config: config) { [weak self] value in
            self?.inputPopover?.close()
            self?.inputPopover = nil
            self?.onInputSubmitted?(element, optionIndex, config.fieldName, value)
        } onCancel: { [weak self] in
            self?.inputPopover?.close()
            self?.inputPopover = nil
        }
        popover.contentViewController = controller

        guard let positionRect = glyphRect(for: charRange) else { return }
        inputPopover = popover
        // Defer show to next run loop so the triggering mouseDown event completes
        // before the transient popover's event monitor starts listening.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.inputPopover === popover else { return }
            popover.show(relativeTo: positionRect, of: self, preferredEdge: .maxY)
        }
    }

    // MARK: - Date Picker Popover

    /// Shows a graphical date picker popover at the element's position.
    func showDatePickerPopover(for element: InteractiveElement, at charRange: NSRange, existingDate: String? = nil) {
        inputPopover?.close()

        let popover = NSPopover()
        popover.behavior = .transient

        let controller = DatePickerPopoverController(
            initialDate: existingDate,
            onSubmit: { [weak self] dateString in
                self?.inputPopover?.close()
                self?.inputPopover = nil
                self?.onInputSubmitted?(element, nil, "value", dateString)
            },
            onCancel: { [weak self] in
                self?.inputPopover?.close()
                self?.inputPopover = nil
            }
        )
        popover.contentViewController = controller

        guard let positionRect = glyphRect(for: charRange) else { return }
        inputPopover = popover
        DispatchQueue.main.async { [weak self] in
            guard let self, self.inputPopover === popover else { return }
            popover.show(relativeTo: positionRect, of: self, preferredEdge: .maxY)
        }
    }

    // MARK: - Comment Popover

    /// Shows a read/edit/remove popover for CriticMarkup highlight comments.
    func showCommentPopover(for element: InteractiveElement, suggestion: SuggestionElement, at charRange: NSRange) {
        inputPopover?.close()

        let commentText = suggestion.comment ?? ""
        let popover = NSPopover()
        popover.behavior = .transient

        let controller = CommentPopoverController(
            commentText: commentText,
            onEdit: { [weak self] newComment in
                self?.inputPopover?.close()
                self?.inputPopover = nil
                self?.onInputSubmitted?(element, nil, "editComment", newComment)
            },
            onRemove: { [weak self] in
                self?.inputPopover?.close()
                self?.inputPopover = nil
                self?.onInputSubmitted?(element, nil, "action", "accept")
            },
            onCancel: { [weak self] in
                self?.inputPopover?.close()
                self?.inputPopover = nil
            }
        )
        popover.contentViewController = controller

        guard let positionRect = glyphRect(for: charRange) else { return }
        inputPopover = popover
        DispatchQueue.main.async { [weak self] in
            guard let self, self.inputPopover === popover else { return }
            popover.show(relativeTo: positionRect, of: self, preferredEdge: .maxY)
        }
    }

    // MARK: - Suggestion Popover

    /// Shows an accept/reject popover for CriticMarkup suggestions.
    func showSuggestionPopover(for element: InteractiveElement, suggestion: SuggestionElement, at charRange: NSRange) {
        inputPopover?.close()

        let popover = NSPopover()
        popover.behavior = .transient

        let controller = SuggestionPopoverController(
            suggestion: suggestion,
            onAccept: { [weak self] in
                self?.inputPopover?.close()
                self?.inputPopover = nil
                self?.onInputSubmitted?(element, nil, "action", "accept")
            },
            onReject: { [weak self] in
                self?.inputPopover?.close()
                self?.inputPopover = nil
                self?.onInputSubmitted?(element, nil, "action", "reject")
            },
            onCancel: { [weak self] in
                self?.inputPopover?.close()
                self?.inputPopover = nil
            }
        )
        popover.contentViewController = controller

        guard let positionRect = glyphRect(for: charRange) else { return }
        inputPopover = popover
        DispatchQueue.main.async { [weak self] in
            guard let self, self.inputPopover === popover else { return }
            popover.show(relativeTo: positionRect, of: self, preferredEdge: .maxY)
        }
    }
}
