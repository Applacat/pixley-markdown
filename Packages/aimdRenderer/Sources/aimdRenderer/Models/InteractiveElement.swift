import Foundation

// MARK: - Interactive Element Types

/// A detected interactive element in a markdown document.
/// Each element knows its range in the source text and its containing section.
public enum InteractiveElement: Sendable, Identifiable {
    public var id: String {
        switch self {
        case .checkbox(let e): return "checkbox-\(e.range.lowerBound)"
        case .choice(let e): return "choice-\(e.blockquoteRange.lowerBound)"
        case .review(let e): return "review-\(e.blockquoteRange.lowerBound)"
        case .fillIn(let e): return "fillIn-\(e.range.lowerBound)"
        case .feedback(let e): return "feedback-\(e.range.lowerBound)"
        case .suggestion(let e): return "suggestion-\(e.range.lowerBound)"
        case .status(let e): return "status-\(e.labelRange.lowerBound)"
        case .confidence(let e): return "confidence-\(e.range.lowerBound)"
        case .conditional(let e): return "conditional-\(e.range.lowerBound)"
        case .collapsible(let e): return "collapsible-\(e.range.lowerBound)"
        case .slider(let e): return "slider-\(e.range.lowerBound)"
        case .stepper(let e): return "stepper-\(e.range.lowerBound)"
        case .toggle(let e): return "toggle-\(e.range.lowerBound)"
        case .colorPicker(let e): return "colorPicker-\(e.range.lowerBound)"
        case .auditableCheckbox(let e): return "auditableCheckbox-\(e.range.lowerBound)"
        }
    }

    case checkbox(CheckboxElement)
    case choice(ChoiceElement)
    case review(ReviewElement)
    case fillIn(FillInElement)
    case feedback(FeedbackElement)
    case suggestion(SuggestionElement)
    case status(StatusElement)
    case confidence(ConfidenceElement)
    case conditional(ConditionalElement)
    case collapsible(CollapsibleElement)
    case slider(SliderElement)
    case stepper(StepperElement)
    case toggle(ToggleElement)
    case colorPicker(ColorPickerElement)
    case auditableCheckbox(AuditableCheckboxElement)

    /// Human-readable name of this element type for UI display.
    public var displayName: String {
        switch self {
        case .checkbox: return "Checkbox"
        case .choice: return "Choice"
        case .review: return "Review"
        case .fillIn: return "Fill-In"
        case .feedback: return "Feedback"
        case .suggestion: return "Suggestion"
        case .status: return "Status"
        case .confidence: return "Confidence"
        case .conditional: return "Conditional"
        case .collapsible: return "Collapsible"
        case .slider: return "Slider"
        case .stepper: return "Stepper"
        case .toggle: return "Toggle"
        case .colorPicker: return "Color Picker"
        case .auditableCheckbox: return "Auditable Checkbox"
        }
    }

    /// The range of this element in the source text.
    public var range: Range<String.Index> {
        switch self {
        case .checkbox(let e): return e.range
        case .choice(let e): return e.blockquoteRange
        case .review(let e): return e.blockquoteRange
        case .fillIn(let e): return e.range
        case .feedback(let e): return e.range
        case .suggestion(let e): return e.range
        case .status(let e): return e.commentRange
        case .confidence(let e): return e.range
        case .conditional(let e): return e.range
        case .collapsible(let e): return e.range
        case .slider(let e): return e.range
        case .stepper(let e): return e.range
        case .toggle(let e): return e.range
        case .colorPicker(let e): return e.range
        case .auditableCheckbox(let e): return e.range
        }
    }
}

// MARK: - Element Structs

public struct CheckboxElement: Sendable {
    /// Range of the full `- [ ] text` line
    public let range: Range<String.Index>
    /// Range of just the space/x character inside the brackets
    public let checkRange: Range<String.Index>
    public let isChecked: Bool
    public let label: String

    public init(range: Range<String.Index>, checkRange: Range<String.Index>, isChecked: Bool, label: String) {
        self.range = range
        self.checkRange = checkRange
        self.isChecked = isChecked
        self.label = label
    }
}

public struct ChoiceOption: Sendable {
    public let range: Range<String.Index>
    public let checkRange: Range<String.Index>
    public let isSelected: Bool
    public let label: String

    public init(range: Range<String.Index>, checkRange: Range<String.Index>, isSelected: Bool, label: String) {
        self.range = range
        self.checkRange = checkRange
        self.isSelected = isSelected
        self.label = label
    }
}

public struct ChoiceElement: Sendable {
    public let blockquoteRange: Range<String.Index>
    public let options: [ChoiceOption]
    public let selectedIndex: Int?

    public init(blockquoteRange: Range<String.Index>, options: [ChoiceOption], selectedIndex: Int?) {
        self.blockquoteRange = blockquoteRange
        self.options = options
        self.selectedIndex = selectedIndex
    }
}

public enum ReviewStatus: String, Sendable {
    case approved = "APPROVED"
    case pass = "PASS"
    case fail = "FAIL"
    case passWithNotes = "PASS WITH NOTES"
    case blocked = "BLOCKED"
    case notApplicable = "N/A"

    public var promptsForNotes: Bool {
        switch self {
        case .fail, .passWithNotes, .blocked: return true
        case .approved, .pass, .notApplicable: return false
        }
    }
}

public struct ReviewOption: Sendable {
    public let range: Range<String.Index>
    public let checkRange: Range<String.Index>
    public let isSelected: Bool
    public let status: ReviewStatus
    public let notes: String?
    public let date: String?

    public init(range: Range<String.Index>, checkRange: Range<String.Index>, isSelected: Bool, status: ReviewStatus, notes: String?, date: String?) {
        self.range = range
        self.checkRange = checkRange
        self.isSelected = isSelected
        self.status = status
        self.notes = notes
        self.date = date
    }
}

public struct ReviewElement: Sendable {
    public let blockquoteRange: Range<String.Index>
    public let options: [ReviewOption]
    public let selectedStatus: ReviewStatus?

    public init(blockquoteRange: Range<String.Index>, options: [ReviewOption], selectedStatus: ReviewStatus?) {
        self.blockquoteRange = blockquoteRange
        self.options = options
        self.selectedStatus = selectedStatus
    }
}

public enum FillInType: Sendable {
    case text
    case file
    case folder
    case date
}

public struct FillInElement: Sendable {
    public let range: Range<String.Index>
    public let hint: String
    public let type: FillInType
    public let value: String?

    public init(range: Range<String.Index>, hint: String, type: FillInType, value: String?) {
        self.range = range
        self.hint = hint
        self.type = type
        self.value = value
    }
}

public struct FeedbackElement: Sendable {
    public let range: Range<String.Index>
    public let existingText: String?

    public init(range: Range<String.Index>, existingText: String?) {
        self.range = range
        self.existingText = existingText
    }
}

public enum SuggestionType: Sendable {
    case addition
    case deletion
    case substitution
    case highlight
}

public struct SuggestionElement: Sendable {
    public let range: Range<String.Index>
    public let type: SuggestionType
    public let oldText: String?
    public let newText: String?
    public let comment: String?

    public init(range: Range<String.Index>, type: SuggestionType, oldText: String?, newText: String?, comment: String?) {
        self.range = range
        self.type = type
        self.oldText = oldText
        self.newText = newText
        self.comment = comment
    }
}

public struct StatusElement: Sendable {
    public let commentRange: Range<String.Index>
    public let labelRange: Range<String.Index>
    public let states: [String]
    public let currentState: String

    public init(commentRange: Range<String.Index>, labelRange: Range<String.Index>, states: [String], currentState: String) {
        self.commentRange = commentRange
        self.labelRange = labelRange
        self.states = states
        self.currentState = currentState
    }

    /// Returns all states except the current one (allows forward and backward transitions).
    public var nextStates: [String] {
        states.filter { $0 != currentState }
    }
}

public enum ConfidenceLevel: String, Sendable {
    case high
    case medium
    case low
    case confirmed
}

public struct ConfidenceElement: Sendable {
    public let range: Range<String.Index>
    public let level: ConfidenceLevel
    public let text: String

    public init(range: Range<String.Index>, level: ConfidenceLevel, text: String) {
        self.range = range
        self.level = level
        self.text = text
    }
}

public struct ConditionalElement: Sendable {
    public let range: Range<String.Index>
    public let key: String
    public let value: String
    public let contentRange: Range<String.Index>

    public init(range: Range<String.Index>, key: String, value: String, contentRange: Range<String.Index>) {
        self.range = range
        self.key = key
        self.value = value
        self.contentRange = contentRange
    }
}

public struct CollapsibleElement: Sendable {
    public let range: Range<String.Index>
    public let title: String
    public let contentRange: Range<String.Index>

    public init(range: Range<String.Index>, title: String, contentRange: Range<String.Index>) {
        self.range = range
        self.title = title
        self.contentRange = contentRange
    }
}

// MARK: - Spec 4: New Controls

/// A slider control: `[[slide MIN-MAX]]` or `[[rate MIN-MAX]]`.
/// Integer range only, inclusive on both ends. Strict validation —
/// invalid ranges (reversed, missing) are not detected.
public struct SliderElement: Sendable {
    public let range: Range<String.Index>
    public let minValue: Int
    public let maxValue: Int
    /// "slide" or "rate" — preserved for round-trip write-back
    public let keyword: String

    public init(range: Range<String.Index>, minValue: Int, maxValue: Int, keyword: String) {
        self.range = range
        self.minValue = minValue
        self.maxValue = maxValue
        self.keyword = keyword
    }
}

/// A stepper control: `[[pick number]]` or `[[pick number MIN-MAX]]`.
/// Integer-only, step size 1.
public struct StepperElement: Sendable {
    public let range: Range<String.Index>
    /// nil when the pattern is `[[pick number]]` without range
    public let minValue: Int?
    public let maxValue: Int?

    public init(range: Range<String.Index>, minValue: Int?, maxValue: Int?) {
        self.range = range
        self.minValue = minValue
        self.maxValue = maxValue
    }
}

/// A toggle switch: `[[toggle]]`.
public struct ToggleElement: Sendable {
    public let range: Range<String.Index>

    public init(range: Range<String.Index>) {
        self.range = range
    }
}

/// A color picker: `[[pick color]]`.
public struct ColorPickerElement: Sendable {
    public let range: Range<String.Index>

    public init(range: Range<String.Index>) {
        self.range = range
    }
}

/// A checkbox variant that auto-appends a date stamp (and optional note) when checked.
/// Triggered by the `(notes)` suffix in the label.
public struct AuditableCheckboxElement: Sendable {
    /// Range of the full `- [ ] label (notes)` line
    public let range: Range<String.Index>
    /// Range of just the space/x character inside the brackets
    public let checkRange: Range<String.Index>
    public let isChecked: Bool
    /// The label with the `(notes)` suffix stripped
    public let label: String
    /// The timestamp if checked (format: `YYYY-MM-DD`)
    public let date: String?
    /// The optional note text if provided
    public let note: String?

    public init(
        range: Range<String.Index>,
        checkRange: Range<String.Index>,
        isChecked: Bool,
        label: String,
        date: String?,
        note: String?
    ) {
        self.range = range
        self.checkRange = checkRange
        self.isChecked = isChecked
        self.label = label
        self.date = date
        self.note = note
    }
}
