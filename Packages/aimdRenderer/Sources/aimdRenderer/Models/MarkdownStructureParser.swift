import Foundation

// MARK: - Markdown Structure Parser

/// Builds a `DocumentStructure` from markdown text by:
/// 1. Extracting headings to build a section tree
/// 2. Detecting interactive elements
/// 3. Assigning each element to its containing section
public enum MarkdownStructureParser: Sendable {

    /// Parses markdown text into a full document structure.
    public static func parse(text: String) -> DocumentStructure {
        guard !text.isEmpty else {
            return DocumentStructure(sections: [], elements: [], content: text)
        }

        // Step 1: Find all headings with their positions
        let headingPositions = extractHeadings(from: text)

        // Step 2: Build section tree from headings
        var sections = buildSectionTree(from: headingPositions, in: text)

        // Step 3: Detect all interactive elements
        let elements = InteractiveElementDetector.detect(in: text)

        // Step 4: Assign elements to sections
        assignElements(elements, to: &sections, in: text)

        return DocumentStructure(sections: sections, elements: elements, content: text)
    }

    // MARK: - Heading Extraction

    private struct HeadingPosition {
        let level: Int
        let title: String
        let lineStart: String.Index
        let lineEnd: String.Index
    }

    private static let headingPattern = try! NSRegularExpression(
        pattern: #"^(#{1,6})\s+(.+)$"#,
        options: .anchorsMatchLines
    )

    private static func extractHeadings(from text: String) -> [HeadingPosition] {
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = headingPattern.matches(in: text, range: nsRange)

        return matches.compactMap { match -> HeadingPosition? in
            guard let fullRange = Range(match.range, in: text),
                  let hashRange = Range(match.range(at: 1), in: text),
                  let titleRange = Range(match.range(at: 2), in: text) else { return nil }

            let level = text.distance(from: hashRange.lowerBound, to: hashRange.upperBound)
            let title = String(text[titleRange]).trimmingCharacters(in: .whitespaces)

            return HeadingPosition(
                level: level,
                title: title,
                lineStart: fullRange.lowerBound,
                lineEnd: fullRange.upperBound
            )
        }
    }

    // MARK: - Section Tree Building

    private static func buildSectionTree(from headings: [HeadingPosition], in text: String) -> [Section] {
        guard !headings.isEmpty else {
            // No headings — if there's content, wrap in a single root section
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return [Section(
                    level: 0,
                    title: "",
                    range: text.startIndex..<text.endIndex
                )]
            }
            return []
        }

        var sections: [Section] = []

        // Content before the first heading gets a level-0 section
        if headings[0].lineStart > text.startIndex {
            let preContent = text[text.startIndex..<headings[0].lineStart]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !preContent.isEmpty {
                sections.append(Section(
                    level: 0,
                    title: "",
                    range: text.startIndex..<headings[0].lineStart
                ))
            }
        }

        // Create flat sections with ranges that extend to the next heading
        // of equal or higher level (not just the next heading)
        var flatSections: [Section] = []
        for (i, heading) in headings.enumerated() {
            // Find the next heading at same or higher level (lower number)
            var sectionEnd = text.endIndex
            for j in (i + 1)..<headings.count {
                if headings[j].level <= heading.level {
                    sectionEnd = headings[j].lineStart
                    break
                }
            }

            flatSections.append(Section(
                level: heading.level,
                title: heading.title,
                range: heading.lineStart..<sectionEnd
            ))
        }

        // Nest sections based on heading level
        sections.append(contentsOf: nestSections(flatSections))

        return sections
    }

    /// Nests flat sections into a tree based on heading levels.
    private static func nestSections(_ flat: [Section]) -> [Section] {
        guard !flat.isEmpty else { return [] }

        var result: [Section] = []
        var stack: [(section: Section, index: Int)] = []

        for section in flat {
            // Pop stack until we find a parent (lower level)
            while let last = stack.last, last.section.level >= section.level {
                let completed = stack.removeLast()
                if stack.last != nil {
                    stack[stack.count - 1].section.children.append(completed.section)
                } else {
                    result.append(completed.section)
                }
            }

            stack.append((section, 0))
        }

        // Flush remaining stack
        while let completed = stack.popLast() {
            if stack.last != nil {
                stack[stack.count - 1].section.children.append(completed.section)
            } else {
                result.append(completed.section)
            }
        }

        return result
    }

    // MARK: - Element Assignment

    /// Assigns each element to its most specific containing section.
    private static func assignElements(_ elements: [InteractiveElement], to sections: inout [Section], in text: String) {
        for element in elements {
            assignElement(element, to: &sections)
        }
    }

    /// Assigns a single element to the deepest section that contains it.
    private static func assignElement(_ element: InteractiveElement, to sections: inout [Section]) {
        for i in sections.indices {
            if sections[i].range.contains(element.range.lowerBound) {
                // Try to assign to a child first (more specific)
                if !sections[i].children.isEmpty {
                    let beforeCount = totalElements(in: sections[i].children)
                    assignElement(element, to: &sections[i].children)
                    let afterCount = totalElements(in: sections[i].children)
                    if afterCount > beforeCount {
                        return // Successfully assigned to child
                    }
                }
                // Assign to this section
                sections[i].elements.append(element)
                return
            }
        }
    }

    private static func totalElements(in sections: [Section]) -> Int {
        sections.reduce(0) { $0 + $1.elements.count + totalElements(in: $1.children) }
    }
}
