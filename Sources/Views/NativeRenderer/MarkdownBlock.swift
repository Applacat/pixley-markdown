import Foundation
import aimdRenderer

// MARK: - Markdown Block

/// A renderable block of markdown content for the native SwiftUI renderer.
/// Produced by `MarkdownBlockParser` from raw markdown text within a section.
/// Each block carries a stable `index` assigned during parsing for ForEach identity,
/// plus its source line range for gutter line numbers.
struct MarkdownBlock: Identifiable {
    let id: Int // sequential index assigned at parse time
    let kind: Kind
    /// 1-based starting line number in the source markdown file
    let startLine: Int
    /// 1-based ending line number in the source markdown file (inclusive)
    let endLine: Int

    enum Kind {
        case heading(level: Int, text: String)
        case paragraph(runs: [InlineRun])
        case codeBlock(language: String?, code: String)
        case blockquote(blocks: [MarkdownBlock])
        case unorderedList(items: [ListItemBlock])
        case orderedList(items: [ListItemBlock], startIndex: Int)
        case horizontalRule
        case table(headers: [String], rows: [[String]])
        case interactiveElement(InteractiveElement)
        case image(alt: String, url: String)
        case rawText(String)
    }
}

// MARK: - Inline Run

/// An inline span of styled text within a paragraph.
struct InlineRun: Hashable {
    enum Style: Hashable {
        case plain
        case bold
        case italic
        case boldItalic
        case code
        case strikethrough
        case link(url: String)
        case image(url: String)
    }

    let text: String
    let style: Style
}

// MARK: - List Item Block

struct ListItemBlock: Identifiable {
    let id = UUID()
    /// 1-based source line number for this item (used for per-item gutter alignment)
    let startLine: Int
    let runs: [InlineRun]
    let children: [MarkdownBlock]
}

// MARK: - Markdown Block Parser

/// Parses raw markdown section content into an array of `MarkdownBlock` values.
/// Uses line-level regex parsing (not swift-markdown AST) for speed and simplicity.
enum MarkdownBlockParser {

    /// Parse the full document into a flat block array (headings included).
    static func parseFlat(content: String, elements: [InteractiveElement]) -> [MarkdownBlock] {
        let range = content.startIndex..<content.endIndex
        return parse(content: content, sectionRange: range, elements: elements, includeHeadings: true, lineOffset: 0)
    }

    /// Parse a section's raw text content (below its heading) into blocks.
    /// `lineOffset` is the 0-based line offset of the section's first line within the full document.
    static func parse(
        content: String,
        sectionRange: Range<String.Index>,
        elements: [InteractiveElement],
        includeHeadings: Bool = false,
        lineOffset: Int = 0
    ) -> [MarkdownBlock] {
        let text = String(content[sectionRange])
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        // Build a set of element ranges for quick lookup (offset into section)
        let sectionStart = content.distance(from: content.startIndex, to: sectionRange.lowerBound)

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let absLine = lineOffset + i + 1 // 1-based absolute line number

            // Skip empty lines
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Heading (only in flat parse mode)
            if includeHeadings, let headingLevel = parseHeadingLevel(trimmed) {
                let headingText = String(trimmed.dropFirst(headingLevel + 1))
                blocks.append(MarkdownBlock(
                    id: blocks.count,
                    kind: .heading(level: headingLevel, text: headingText),
                    startLine: absLine,
                    endLine: absLine
                ))
                i += 1
                continue
            }

            // Check if this line starts an interactive element
            let prevI = i
            if let elementKind = matchInteractiveElement(
                lineIndex: i, lines: lines, sectionStart: sectionStart,
                content: content, elements: elements, consumed: &i
            ) {
                let endAbsLine = lineOffset + (i - 1) + 1
                blocks.append(MarkdownBlock(id: blocks.count, kind: elementKind, startLine: absLine, endLine: endAbsLine))
                continue
            }

            // Code block (fenced)
            if trimmed.hasPrefix("```") {
                let result = parseCodeBlock(from: lines, startIndex: i)
                let endAbsLine = lineOffset + (result.nextIndex - 1) + 1
                blocks.append(MarkdownBlock(id: blocks.count, kind: result.kind, startLine: absLine, endLine: endAbsLine))
                i = result.nextIndex
                continue
            }

            // Horizontal rule
            if isHorizontalRule(trimmed) {
                blocks.append(MarkdownBlock(id: blocks.count, kind: .horizontalRule, startLine: absLine, endLine: absLine))
                i += 1
                continue
            }

            // Blockquote
            if trimmed.hasPrefix("> ") || trimmed == ">" {
                let result = parseBlockquote(
                    from: lines, startIndex: i, lineOffset: lineOffset,
                    content: content, sectionRange: sectionRange, elements: elements
                )
                let endAbsLine = lineOffset + (result.nextIndex - 1) + 1
                blocks.append(MarkdownBlock(id: blocks.count, kind: result.kind, startLine: absLine, endLine: endAbsLine))
                i = result.nextIndex
                continue
            }

            // Unordered list
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                let result = parseUnorderedList(from: lines, startIndex: i, lineOffset: lineOffset)
                let endAbsLine = lineOffset + (result.nextIndex - 1) + 1
                blocks.append(MarkdownBlock(id: blocks.count, kind: result.kind, startLine: absLine, endLine: endAbsLine))
                i = result.nextIndex
                continue
            }

            // Ordered list
            if let _ = trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                let result = parseOrderedList(from: lines, startIndex: i, lineOffset: lineOffset)
                let endAbsLine = lineOffset + (result.nextIndex - 1) + 1
                blocks.append(MarkdownBlock(id: blocks.count, kind: result.kind, startLine: absLine, endLine: endAbsLine))
                i = result.nextIndex
                continue
            }

            // Table
            if trimmed.hasPrefix("|") {
                let result = parseTable(from: lines, startIndex: i)
                let endAbsLine = lineOffset + (result.nextIndex - 1) + 1
                blocks.append(MarkdownBlock(id: blocks.count, kind: result.kind, startLine: absLine, endLine: endAbsLine))
                i = result.nextIndex
                continue
            }

            // Image (standalone line)
            if let imageMatch = trimmed.range(of: #"^!\[([^\]]*)\]\(([^)]+)\)$"#, options: .regularExpression) {
                let imageText = String(trimmed[imageMatch])
                if let alt = extractGroup(from: imageText, pattern: #"!\[([^\]]*)\]"#),
                   let url = extractGroup(from: imageText, pattern: #"\(([^)]+)\)"#) {
                    blocks.append(MarkdownBlock(id: blocks.count, kind: .image(alt: alt, url: url), startLine: absLine, endLine: absLine))
                    i += 1
                    continue
                }
            }

            // Default: paragraph (collect consecutive non-blank non-special lines)
            let result = parseParagraph(from: lines, startIndex: i)
            let endAbsLine = lineOffset + (result.nextIndex - 1) + 1
            blocks.append(MarkdownBlock(id: blocks.count, kind: result.kind, startLine: absLine, endLine: endAbsLine))
            i = result.nextIndex
        }

        return blocks
    }

    // MARK: - Code Block

    private static func parseCodeBlock(from lines: [String], startIndex: Int) -> (kind: MarkdownBlock.Kind, nextIndex: Int) {
        let firstLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
        let language = String(firstLine.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        var code: [String] = []
        var i = startIndex + 1

        while i < lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                i += 1
                break
            }
            code.append(lines[i])
            i += 1
        }

        return (.codeBlock(language: language.isEmpty ? nil : language, code: code.joined(separator: "\n")), i)
    }

    // MARK: - Blockquote

    private static func parseBlockquote(
        from lines: [String],
        startIndex: Int,
        lineOffset: Int,
        content: String,
        sectionRange: Range<String.Index>,
        elements: [InteractiveElement]
    ) -> (kind: MarkdownBlock.Kind, nextIndex: Int) {
        var quoteLines: [String] = []
        var i = startIndex

        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("> ") {
                quoteLines.append(String(trimmed.dropFirst(2)))
            } else if trimmed == ">" {
                quoteLines.append("")
            } else {
                break
            }
            i += 1
        }

        let absStart = lineOffset + startIndex + 1
        let absEnd = lineOffset + (i - 1) + 1
        let innerText = quoteLines.joined(separator: "\n")
        let innerRuns = parseInlineRuns(innerText)
        return (.blockquote(blocks: [MarkdownBlock(id: 0, kind: .paragraph(runs: innerRuns), startLine: absStart, endLine: absEnd)]), i)
    }

    // MARK: - Lists

    private static func parseUnorderedList(from lines: [String], startIndex: Int, lineOffset: Int) -> (kind: MarkdownBlock.Kind, nextIndex: Int) {
        var items: [ListItemBlock] = []
        var i = startIndex

        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                let text = String(trimmed.dropFirst(2))
                let itemLine = lineOffset + i + 1
                items.append(ListItemBlock(startLine: itemLine, runs: parseInlineRuns(text), children: []))
                i += 1
            } else if trimmed.isEmpty {
                break
            } else {
                break
            }
        }

        return (.unorderedList(items: items), i)
    }

    private static func parseOrderedList(from lines: [String], startIndex: Int, lineOffset: Int) -> (kind: MarkdownBlock.Kind, nextIndex: Int) {
        var items: [ListItemBlock] = []
        var i = startIndex
        var firstNum = 1

        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if let match = trimmed.range(of: #"^(\d+)\.\s(.+)$"#, options: .regularExpression) {
                let matchStr = String(trimmed[match])
                if let numStr = extractGroup(from: matchStr, pattern: #"^(\d+)\."#),
                   let num = Int(numStr), items.isEmpty {
                    firstNum = num
                }
                if let text = extractGroup(from: matchStr, pattern: #"^\d+\.\s(.+)$"#) {
                    let itemLine = lineOffset + i + 1
                    items.append(ListItemBlock(startLine: itemLine, runs: parseInlineRuns(text), children: []))
                }
                i += 1
            } else if trimmed.isEmpty {
                break
            } else {
                break
            }
        }

        return (.orderedList(items: items, startIndex: firstNum), i)
    }

    // MARK: - Paragraph

    private static func parseParagraph(from lines: [String], startIndex: Int) -> (kind: MarkdownBlock.Kind, nextIndex: Int) {
        var paraLines: [String] = []
        var i = startIndex

        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("```") || trimmed.hasPrefix("# ") ||
               trimmed.hasPrefix("## ") || trimmed.hasPrefix("### ") ||
               trimmed.hasPrefix("#### ") || trimmed.hasPrefix("##### ") ||
               trimmed.hasPrefix("###### ") || isHorizontalRule(trimmed) ||
               trimmed.hasPrefix("> ") || trimmed.hasPrefix("|") ||
               trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") ||
               trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                break
            }
            paraLines.append(lines[i])
            i += 1
        }

        if paraLines.isEmpty {
            return (.rawText(lines[startIndex]), startIndex + 1)
        }

        let text = paraLines.joined(separator: " ")
        return (.paragraph(runs: parseInlineRuns(text)), i)
    }

    // MARK: - Table

    private static func parseTable(from lines: [String], startIndex: Int) -> (kind: MarkdownBlock.Kind, nextIndex: Int) {
        var i = startIndex
        let headers = parseTableRow(lines[i])
        i += 1

        if i < lines.count {
            let sep = lines[i].trimmingCharacters(in: .whitespaces)
            if sep.hasPrefix("|") && sep.contains("-") {
                i += 1
            }
        }

        var rows: [[String]] = []
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("|") else { break }
            rows.append(parseTableRow(lines[i]))
            i += 1
        }

        return (.table(headers: headers, rows: rows), i)
    }

    private static func parseTableRow(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var cells = trimmed.split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        if cells.first?.isEmpty == true { cells.removeFirst() }
        if cells.last?.isEmpty == true { cells.removeLast() }
        return cells
    }

    // MARK: - Inline Runs

    static func parseInlineRuns(_ text: String) -> [InlineRun] {
        guard !text.isEmpty else { return [] }

        var runs: [InlineRun] = []
        var remaining = text[text.startIndex...]

        let patterns: [(pattern: String, style: (String) -> InlineRun.Style)] = [
            (#"\!\[([^\]]*)\]\(([^)]+)\)"#, { match in
                if let url = extractGroup(from: match, pattern: #"\]\(([^)]+)\)"#) {
                    return .image(url: url)
                }
                return .plain
            }),
            (#"\[([^\]]+)\]\(([^)]+)\)"#, { match in
                if let url = extractGroup(from: match, pattern: #"\]\(([^)]+)\)"#) {
                    return .link(url: url)
                }
                return .plain
            }),
            (#"\*\*\*(.+?)\*\*\*"#, { _ in .boldItalic }),
            (#"\*\*(.+?)\*\*"#, { _ in .bold }),
            (#"\*(.+?)\*"#, { _ in .italic }),
            (#"`([^`]+)`"#, { _ in .code }),
            (#"~~(.+?)~~"#, { _ in .strikethrough }),
        ]

        while !remaining.isEmpty {
            var earliestMatch: (range: Range<Substring.Index>, text: String, style: InlineRun.Style)?

            for (pattern, styleFunc) in patterns {
                if let match = remaining.range(of: pattern, options: .regularExpression) {
                    if earliestMatch == nil || match.lowerBound < earliestMatch!.range.lowerBound {
                        let matched = String(remaining[match])
                        let style = styleFunc(matched)
                        let inner: String
                        if matched.hasPrefix("![") {
                            inner = extractGroup(from: matched, pattern: #"!\[([^\]]*)\]"#) ?? matched
                        } else if matched.hasPrefix("[") {
                            inner = extractGroup(from: matched, pattern: #"\[([^\]]+)\]"#) ?? matched
                        } else if matched.hasPrefix("***") {
                            inner = String(matched.dropFirst(3).dropLast(3))
                        } else if matched.hasPrefix("**") {
                            inner = String(matched.dropFirst(2).dropLast(2))
                        } else if matched.hasPrefix("*") {
                            inner = String(matched.dropFirst(1).dropLast(1))
                        } else if matched.hasPrefix("~~") {
                            inner = String(matched.dropFirst(2).dropLast(2))
                        } else if matched.hasPrefix("`") {
                            inner = String(matched.dropFirst(1).dropLast(1))
                        } else {
                            inner = matched
                        }
                        earliestMatch = (match, inner, style)
                    }
                }
            }

            if let match = earliestMatch {
                if match.range.lowerBound > remaining.startIndex {
                    let plain = String(remaining[remaining.startIndex..<match.range.lowerBound])
                    if !plain.isEmpty {
                        runs.append(InlineRun(text: plain, style: .plain))
                    }
                }
                runs.append(InlineRun(text: match.text, style: match.style))
                remaining = remaining[match.range.upperBound...]
            } else {
                runs.append(InlineRun(text: String(remaining), style: .plain))
                break
            }
        }

        return runs
    }

    // MARK: - Interactive Elements

    private static func matchInteractiveElement(
        lineIndex: Int,
        lines: [String],
        sectionStart: Int,
        content: String,
        elements: [InteractiveElement],
        consumed: inout Int
    ) -> MarkdownBlock.Kind? {
        var offset = sectionStart
        for j in 0..<lineIndex {
            offset += lines[j].count + 1
        }

        for element in elements {
            let elemStart = content.distance(from: content.startIndex, to: element.range.lowerBound)
            let elemEnd = content.distance(from: content.startIndex, to: element.range.upperBound)

            if elemStart >= offset && elemStart < offset + lines[lineIndex].count + 1 {
                var endLineIdx = lineIndex
                var endOffset = offset
                while endLineIdx < lines.count {
                    endOffset += lines[endLineIdx].count + 1
                    if endOffset >= elemEnd { break }
                    endLineIdx += 1
                }
                consumed = endLineIdx + 1
                return .interactiveElement(element)
            }
        }

        return nil
    }

    // MARK: - Helpers

    private static func isHorizontalRule(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        return (stripped.allSatisfy({ $0 == "-" }) && stripped.count >= 3) ||
               (stripped.allSatisfy({ $0 == "*" }) && stripped.count >= 3) ||
               (stripped.allSatisfy({ $0 == "_" }) && stripped.count >= 3)
    }

    private static func parseHeadingLevel(_ line: String) -> Int? {
        var level = 0
        for ch in line {
            if ch == "#" { level += 1 }
            else if ch == " " && level > 0 { return min(level, 6) }
            else { return nil }
        }
        return nil
    }
}

// MARK: - Regex Helper

private func extractGroup(from text: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          match.numberOfRanges > 1,
          let range = Range(match.range(at: 1), in: text) else { return nil }
    return String(text[range])
}
