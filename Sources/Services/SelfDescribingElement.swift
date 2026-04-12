import Foundation
import aimdRenderer

// MARK: - Self-Describing Element Protocol

/* SACRED CODE - DO NOT MODIFY WITHOUT EXPLICIT PERMISSION
 *
 * Self-Describing Element Protocol (Wanderlust Pattern)
 *
 * WHY SACRED: This protocol enables generic AI interaction with all element types.
 * The EditInteractiveElementsTool uses editableFields and apply() to modify elements
 * without per-type switch statements. Adding a new element type REQUIRES adding
 * a conformance here — the compiler won't catch the omission since conformances
 * are extensions.
 *
 * UPDATE CONFORMANCES WHEN ADDING ELEMENT TYPES
 *
 * CURRENT CONFORMANCES (10 element types):
 * - CheckboxElement, ChoiceElement, ReviewElement, FillInElement
 * - FeedbackElement, SuggestionElement, StatusElement, ConfidenceElement
 * - ConditionalElement, CollapsibleElement
 *
 * DANGERS:
 * - Missing conformance for new element type (AI tool silently ignores it)
 * - Changing field names (breaks existing AI tool @Generable args)
 * - Removing validValues (AI generates invalid edits)
 */

/// A field that the AI tool can read and modify on an interactive element.
struct EditableField: Sendable {
    let name: String
    let currentValue: String
    let validValues: [String]?
}

/// Protocol enabling interactive elements to describe themselves for generic AI interaction.
/// Each element exposes its type, schema, editable fields, and an apply function.
protocol SelfDescribingElement {
    /// Human-readable type name (e.g., "Checkbox", "Status")
    var elementType: String { get }

    /// What this element is and how it works
    var schemaDescription: String { get }

    /// Fields the AI can modify, with current values and valid options
    var editableFields: [EditableField] { get }

    /// Produces an edit from a field name and value. Returns nil if invalid.
    func apply(field: String, value: String) -> InteractiveEdit?
}

// MARK: - Conformances

extension CheckboxElement: SelfDescribingElement {
    var elementType: String { "Checkbox" }

    var schemaDescription: String {
        "A toggleable checkbox. Markdown: `- [x]` (checked) or `- [ ]` (unchecked)."
    }

    var editableFields: [EditableField] {
        [EditableField(name: "isChecked", currentValue: isChecked ? "true" : "false", validValues: ["true", "false"])]
    }

    func apply(field: String, value: String) -> InteractiveEdit? {
        guard field == "isChecked" else { return nil }
        let shouldCheck = value.lowercased() == "true" || value == "x"
        guard isChecked != shouldCheck else { return nil }
        return .replace(range: checkRange, newText: shouldCheck ? "x" : " ")
    }
}

extension ChoiceElement: SelfDescribingElement {
    var elementType: String { "Choice" }

    var schemaDescription: String {
        "A single-select choice group. Click an option to select it (deselects others)."
    }

    var editableFields: [EditableField] {
        let indices = options.indices.map(String.init)
        let current = selectedIndex.map(String.init) ?? "none"
        return [EditableField(name: "selected", currentValue: current, validValues: indices)]
    }

    func apply(field: String, value: String) -> InteractiveEdit? {
        guard field == "selected", let index = Int(value), options.indices.contains(index) else { return nil }
        var replacements: [(range: Range<String.Index>, newText: String)] = []
        for (i, option) in options.enumerated() {
            let shouldSelect = i == index
            if option.isSelected != shouldSelect {
                replacements.append((range: option.checkRange, newText: shouldSelect ? "x" : " "))
            }
        }
        return replacements.isEmpty ? nil : .replaceMultiple(replacements)
    }
}

extension ReviewElement: SelfDescribingElement {
    var elementType: String { "Review" }

    var schemaDescription: String {
        "A review status selector. Options: APPROVED, PASS, FAIL, PASS WITH NOTES, BLOCKED, N/A."
    }

    var editableFields: [EditableField] {
        let indices = options.indices.map(String.init)
        let current: String
        if let sel = options.firstIndex(where: { $0.isSelected }) {
            current = String(sel)
        } else {
            current = "none"
        }
        let selectedNotes = options.first(where: { $0.isSelected })?.notes ?? ""
        return [
            EditableField(name: "selected", currentValue: current, validValues: indices),
            EditableField(name: "notes", currentValue: selectedNotes, validValues: nil),
        ]
    }

    func apply(field: String, value: String) -> InteractiveEdit? {
        switch field {
        case "selected":
            guard let index = Int(value), options.indices.contains(index) else { return nil }
            var replacements: [(range: Range<String.Index>, newText: String)] = []
            for (i, option) in options.enumerated() {
                let shouldSelect = i == index
                if option.isSelected != shouldSelect {
                    replacements.append((range: option.checkRange, newText: shouldSelect ? "x" : " "))
                }
            }
            return replacements.isEmpty ? nil : .replaceMultiple(replacements)
        case "notes":
            // Notes apply to the currently selected option
            guard let selIndex = options.firstIndex(where: { $0.isSelected }) else { return nil }
            let option = options[selIndex]
            let dateStr = {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                return f.string(from: Date())
            }()
            let newLine = "[x] \(option.status.rawValue) — \(dateStr)\(value.isEmpty ? "" : " | \(value)")"
            return .replace(range: option.range, newText: newLine)
        default:
            return nil
        }
    }
}

extension FillInElement: SelfDescribingElement {
    var elementType: String { "Fill-In" }

    var schemaDescription: String {
        "A text input field. User types a value to fill in the blank. Hint: \"\(hint)\"."
    }

    var editableFields: [EditableField] {
        [EditableField(name: "value", currentValue: value ?? "", validValues: nil)]
    }

    func apply(field: String, value: String) -> InteractiveEdit? {
        guard field == "value" else { return nil }
        return .replace(range: range, newText: "[[\(value)]]")
    }
}

extension FeedbackElement: SelfDescribingElement {
    var elementType: String { "Feedback" }

    var schemaDescription: String {
        "A feedback marker where the user provides free-text feedback."
    }

    var editableFields: [EditableField] {
        [EditableField(name: "text", currentValue: existingText ?? "", validValues: nil)]
    }

    func apply(field: String, value: String) -> InteractiveEdit? {
        guard field == "text" else { return nil }
        let newComment = "<!-- feedback: \(value) -->"
        return .replace(range: range, newText: newComment)
    }
}

extension SuggestionElement: SelfDescribingElement {
    var elementType: String { "Suggestion" }

    var schemaDescription: String {
        "A CriticMarkup suggestion (addition, deletion, or substitution). User can accept or reject."
    }

    var editableFields: [EditableField] {
        [EditableField(name: "action", currentValue: "pending", validValues: ["accept", "reject"])]
    }

    func apply(field: String, value: String) -> InteractiveEdit? {
        guard field == "action" else { return nil }
        switch value {
        case "accept":
            let replacement = newText ?? ""
            return .replace(range: range, newText: replacement)
        case "reject":
            let original = oldText ?? ""
            return .replace(range: range, newText: original)
        default:
            return nil
        }
    }
}

extension StatusElement: SelfDescribingElement {
    var elementType: String { "Status" }

    var schemaDescription: String {
        "A state machine with defined transitions. Current: \"\(currentState)\". States: \(states.joined(separator: ", "))."
    }

    var editableFields: [EditableField] {
        [EditableField(name: "status", currentValue: currentState, validValues: states)]
    }

    func apply(field: String, value: String) -> InteractiveEdit? {
        guard field == "status", states.contains(value) else { return nil }
        return .replace(range: labelRange, newText: value)
    }
}

extension ConfidenceElement: SelfDescribingElement {
    var elementType: String { "Confidence" }

    var schemaDescription: String {
        "An AI confidence marker. Level: \(level.rawValue). User can confirm."
    }

    var editableFields: [EditableField] {
        let isConfirmed = level == .confirmed
        return [EditableField(name: "confirmed", currentValue: isConfirmed ? "true" : "false", validValues: ["true", "false"])]
    }

    func apply(field: String, value: String) -> InteractiveEdit? {
        guard field == "confirmed" else { return nil }
        // Confirmation replaces the confidence marker with a confirmed version
        let shouldConfirm = value.lowercased() == "true"
        guard shouldConfirm, level != .confirmed else { return nil }
        let confirmedText = "<!-- confidence: confirmed | \(text) -->"
        return .replace(range: range, newText: confirmedText)
    }
}

extension ConditionalElement: SelfDescribingElement {
    var elementType: String { "Conditional" }
    var schemaDescription: String { "A conditional block that shows/hides content based on a key-value condition. Detect-only." }
    var editableFields: [EditableField] { [] }
    func apply(field: String, value: String) -> InteractiveEdit? { nil }
}

extension CollapsibleElement: SelfDescribingElement {
    var elementType: String { "Collapsible" }
    var schemaDescription: String { "A collapsible/expandable section with a title. Detect-only, no editable fields." }
    var editableFields: [EditableField] { [] }
    func apply(field: String, value: String) -> InteractiveEdit? { nil }
}

// MARK: - Spec 4 Conformances

extension SliderElement: SelfDescribingElement {
    var elementType: String { "Slider" }

    var schemaDescription: String {
        "An integer slider between \(minValue) and \(maxValue) (inclusive). " +
        "Markdown: `[[\(keyword) \(minValue)-\(maxValue)]]` → replaced with the chosen integer."
    }

    var editableFields: [EditableField] {
        [EditableField(name: "value", currentValue: "\(minValue)", validValues: nil)]
    }

    func apply(field: String, value: String) -> InteractiveEdit? {
        guard field == "value", let intValue = Int(value), intValue >= minValue, intValue <= maxValue else { return nil }
        return .replace(range: range, newText: "\(intValue)")
    }
}

extension StepperElement: SelfDescribingElement {
    var elementType: String { "Stepper" }

    var schemaDescription: String {
        if let mn = minValue, let mx = maxValue {
            return "An integer stepper between \(mn) and \(mx). Markdown: `[[pick number \(mn)-\(mx)]]`."
        }
        return "An unbounded integer stepper. Markdown: `[[pick number]]`."
    }

    var editableFields: [EditableField] {
        [EditableField(name: "value", currentValue: "0", validValues: nil)]
    }

    func apply(field: String, value: String) -> InteractiveEdit? {
        guard field == "value", let intValue = Int(value) else { return nil }
        if let mn = minValue, intValue < mn { return nil }
        if let mx = maxValue, intValue > mx { return nil }
        return .replace(range: range, newText: "\(intValue)")
    }
}

extension ToggleElement: SelfDescribingElement {
    var elementType: String { "Toggle" }

    var schemaDescription: String {
        "A binary toggle switch. Markdown: `[[toggle]]` → replaced with `on` or `off`."
    }

    var editableFields: [EditableField] {
        [EditableField(name: "state", currentValue: "off", validValues: ["on", "off"])]
    }

    func apply(field: String, value: String) -> InteractiveEdit? {
        guard field == "state", value == "on" || value == "off" else { return nil }
        return .replace(range: range, newText: value)
    }
}

extension ColorPickerElement: SelfDescribingElement {
    var elementType: String { "Color Picker" }

    var schemaDescription: String {
        "A color picker. Markdown: `[[pick color]]` → replaced with a hex color like `#FF5733`."
    }

    var editableFields: [EditableField] {
        [EditableField(name: "hex", currentValue: "#000000", validValues: nil)]
    }

    func apply(field: String, value: String) -> InteractiveEdit? {
        guard field == "hex" else { return nil }
        // Validate hex format
        let hex = value.hasPrefix("#") ? value : "#\(value)"
        let hexPattern = try! NSRegularExpression(pattern: #"^#[0-9A-Fa-f]{6}$"#)
        let nsRange = NSRange(hex.startIndex..., in: hex)
        guard hexPattern.firstMatch(in: hex, range: nsRange) != nil else { return nil }
        return .replace(range: range, newText: hex)
    }
}

extension AuditableCheckboxElement: SelfDescribingElement {
    var elementType: String { "Auditable Checkbox" }

    var schemaDescription: String {
        "A checkbox that auto-appends a date stamp (and optional note) when checked. Trigger: `(notes)` suffix in label."
    }

    var editableFields: [EditableField] {
        [EditableField(name: "isChecked", currentValue: isChecked ? "true" : "false", validValues: ["true", "false"])]
    }

    func apply(field: String, value: String) -> InteractiveEdit? {
        guard field == "isChecked" else { return nil }
        let shouldCheck = value.lowercased() == "true" || value == "x"
        guard isChecked != shouldCheck else { return nil }
        return .replace(range: checkRange, newText: shouldCheck ? "x" : " ")
    }
}

// MARK: - InteractiveElement Convenience

extension InteractiveElement {
    /// Returns self-describing metadata for this element via dispatch to the concrete type.
    var selfDescribing: SelfDescribingElement {
        switch self {
        case .checkbox(let e): return e
        case .choice(let e): return e
        case .review(let e): return e
        case .fillIn(let e): return e
        case .feedback(let e): return e
        case .suggestion(let e): return e
        case .status(let e): return e
        case .confidence(let e): return e
        case .conditional(let e): return e
        case .collapsible(let e): return e
        case .slider(let e): return e
        case .stepper(let e): return e
        case .toggle(let e): return e
        case .colorPicker(let e): return e
        case .auditableCheckbox(let e): return e
        }
    }
}
/* END SACRED CODE */
