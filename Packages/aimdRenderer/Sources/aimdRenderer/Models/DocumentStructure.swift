import Foundation

// MARK: - Document Structure

/// A structural model of a markdown document built from headings, with interactive elements
/// assigned to their containing sections. Enables FM context optimization via `outline()` and `summary()`.
public struct DocumentStructure: Sendable {

    /// Top-level sections (# headings and content before any heading)
    public let sections: [Section]

    /// All interactive elements found in the document, flattened
    public let elements: [InteractiveElement]

    /// The original content this structure was parsed from
    public let content: String

    public init(sections: [Section], elements: [InteractiveElement], content: String) {
        self.sections = sections
        self.elements = elements
        self.content = content
    }

    // MARK: - FM Context Optimization

    /// Produces a headings-only outline at the specified depth.
    /// - Parameter maxDepth: Maximum heading level to include (1 = # only, 2 = # + ##, etc.)
    /// - Returns: A string with indented headings suitable for FM context.
    public func outline(maxDepth: Int = 6) -> String {
        var lines: [String] = []
        appendOutline(sections: sections, maxDepth: maxDepth, lines: &lines)
        return lines.joined(separator: "\n")
    }

    /// Produces a summary with element counts per section.
    public func summary() -> String {
        var lines: [String] = []
        appendSummary(sections: sections, lines: &lines)
        return lines.joined(separator: "\n")
    }

    // MARK: - Queries

    /// Returns all elements of a specific type.
    public func elements(ofType filter: (InteractiveElement) -> Bool) -> [InteractiveElement] {
        elements.filter(filter)
    }

    /// Returns the section containing the given string index.
    public func section(containing index: String.Index) -> Section? {
        findSection(in: sections, containing: index)
    }

    // MARK: - Private Helpers

    private func appendOutline(sections: [Section], maxDepth: Int, lines: inout [String]) {
        for section in sections {
            if section.level <= maxDepth {
                let indent = String(repeating: "  ", count: section.level - 1)
                let prefix = String(repeating: "#", count: section.level)
                lines.append("\(indent)\(prefix) \(section.title)")
            }
            appendOutline(sections: section.children, maxDepth: maxDepth, lines: &lines)
        }
    }

    private func appendSummary(sections: [Section], lines: inout [String]) {
        for section in sections {
            let elementCount = section.elements.count
            if elementCount > 0 {
                let prefix = String(repeating: "#", count: section.level)
                let counts = elementCountDescription(section.elements)
                lines.append("\(prefix) \(section.title) — \(counts)")
            }
            appendSummary(sections: section.children, lines: &lines)
        }
    }

    private func elementCountDescription(_ elements: [InteractiveElement]) -> String {
        var counts: [String: Int] = [:]
        for element in elements {
            let name: String
            switch element {
            case .checkbox: name = "checkbox"
            case .choice: name = "choice"
            case .review: name = "review"
            case .fillIn: name = "fill-in"
            case .feedback: name = "feedback"
            case .suggestion: name = "suggestion"
            case .status: name = "status"
            case .confidence: name = "confidence"
            case .conditional: name = "conditional"
            case .collapsible: name = "collapsible"
            case .slider: name = "slider"
            case .stepper: name = "stepper"
            case .toggle: name = "toggle"
            case .colorPicker: name = "color-picker"
            case .auditableCheckbox: name = "auditable-checkbox"
            }
            counts[name, default: 0] += 1
        }
        return counts.sorted(by: { $0.key < $1.key }).map { "\($0.value) \($0.key)" }.joined(separator: ", ")
    }

    private func findSection(in sections: [Section], containing index: String.Index) -> Section? {
        for section in sections {
            if section.range.contains(index) {
                // Check children first for more specific match
                if let child = findSection(in: section.children, containing: index) {
                    return child
                }
                return section
            }
        }
        return nil
    }
}

// MARK: - Section

/// A section of a markdown document, corresponding to a heading and its content
/// up to the next heading of equal or higher level.
public struct Section: Sendable, Identifiable {
    public var id: String { "section-\(level)-\(title)-\(range.lowerBound)" }

    /// Heading level (1 for #, 2 for ##, etc.)
    public let level: Int

    /// Heading text (without the # prefix)
    public let title: String

    /// Range of the entire section in the source text (heading through end of content)
    public let range: Range<String.Index>

    /// Child sections (subheadings)
    public var children: [Section]

    /// Interactive elements found within this section (not in children)
    public var elements: [InteractiveElement]

    public init(
        level: Int,
        title: String,
        range: Range<String.Index>,
        children: [Section] = [],
        elements: [InteractiveElement] = []
    ) {
        self.level = level
        self.title = title
        self.range = range
        self.children = children
        self.elements = elements
    }

    // MARK: - Progress Calculation

    /// Checkbox completion progress for this section (including children).
    /// Returns (completed, total) or nil if no checkboxes exist.
    public var checkboxProgress: (completed: Int, total: Int)? {
        let allElements = allElementsRecursive
        var total = 0
        var completed = 0

        for element in allElements {
            if case .checkbox(let e) = element {
                total += 1
                if e.isChecked { completed += 1 }
            }
        }

        return total > 0 ? (completed, total) : nil
    }

    /// All elements in this section and all descendants.
    public var allElementsRecursive: [InteractiveElement] {
        var result = elements
        for child in children {
            result.append(contentsOf: child.allElementsRecursive)
        }
        return result
    }
}
