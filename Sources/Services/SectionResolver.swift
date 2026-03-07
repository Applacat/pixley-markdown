import Foundation
import aimdRenderer

// MARK: - Section Resolver

/// Groups a flat list of interactive elements by their containing heading section.
/// Enables the AI tool to query "all elements in Section 3" without needing
/// every element in its context window.
struct SectionResolver: Sendable {

    /// A section derived from a heading in the document.
    struct Section: Sendable {
        let index: Int
        let title: String
        let level: Int
        let range: Range<String.Index>
        let elements: [InteractiveElement]
    }

    private let resolvedSections: [Section]

    /// Creates a resolver by scanning the document text for headings
    /// and assigning each element to its nearest preceding heading.
    init(elements: [InteractiveElement], documentText: String) {
        // Parse headings: lines starting with # (ATX headings)
        var headings: [(title: String, level: Int, position: String.Index)] = []
        var searchStart = documentText.startIndex

        while searchStart < documentText.endIndex {
            guard let lineEnd = documentText[searchStart...].firstIndex(where: { $0 == "\n" }) ?? Optional(documentText.endIndex) else { break }
            let line = documentText[searchStart..<lineEnd]

            // Count leading # characters
            var hashCount = 0
            for ch in line {
                if ch == "#" { hashCount += 1 } else { break }
            }

            if hashCount >= 1 && hashCount <= 6 {
                let afterHashes = line.dropFirst(hashCount)
                if afterHashes.first == " " || afterHashes.isEmpty {
                    let title = String(afterHashes.drop(while: { $0 == " " }))
                        .trimmingCharacters(in: .whitespaces)
                    headings.append((title: title, level: hashCount, position: searchStart))
                }
            }

            searchStart = lineEnd < documentText.endIndex ? documentText.index(after: lineEnd) : documentText.endIndex
        }

        // Build sections: each heading defines a section until the next heading at same or higher level
        var sections: [Section] = []
        for (i, heading) in headings.enumerated() {
            let sectionStart = heading.position
            let sectionEnd: String.Index
            if i + 1 < headings.count {
                sectionEnd = headings[i + 1].position
            } else {
                sectionEnd = documentText.endIndex
            }

            let sectionRange = sectionStart..<sectionEnd
            let sectionElements = elements.filter { element in
                sectionRange.contains(element.range.lowerBound)
            }

            sections.append(Section(
                index: i,
                title: heading.title,
                level: heading.level,
                range: sectionRange,
                elements: sectionElements
            ))
        }

        // Elements before the first heading go into a synthetic "Preamble" section
        if let firstHeadingPos = headings.first?.position, firstHeadingPos > documentText.startIndex {
            let preambleRange = documentText.startIndex..<firstHeadingPos
            let preambleElements = elements.filter { preambleRange.contains($0.range.lowerBound) }
            if !preambleElements.isEmpty {
                var withPreamble = [Section(
                    index: 0,
                    title: "(Preamble)",
                    level: 0,
                    range: preambleRange,
                    elements: preambleElements
                )]
                // Re-index the rest
                for (i, section) in sections.enumerated() {
                    withPreamble.append(Section(
                        index: i + 1,
                        title: section.title,
                        level: section.level,
                        range: section.range,
                        elements: section.elements
                    ))
                }
                sections = withPreamble
            }
        }

        self.resolvedSections = sections
    }

    /// Returns elements belonging to the section at the given index.
    func elements(inSection sectionIndex: Int) -> [InteractiveElement] {
        guard sectionIndex >= 0 && sectionIndex < resolvedSections.count else { return [] }
        return resolvedSections[sectionIndex].elements
    }

    /// Returns a summary of all sections (for the AI tool's context).
    func sections() -> [(index: Int, title: String, level: Int, elementCount: Int)] {
        resolvedSections.map { ($0.index, $0.title, $0.level, $0.elements.count) }
    }

    /// Total number of sections found.
    var sectionCount: Int { resolvedSections.count }
}
