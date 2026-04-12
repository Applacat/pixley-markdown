import SwiftUI
import AppKit
import aimdRenderer

// MARK: - Content Block View

/// Renders a single `MarkdownBlock` as a SwiftUI view using SyntaxPalette colors.
struct ContentBlockView: View {

    let block: MarkdownBlock
    let palette: SyntaxPalette
    let searchText: String
    var documentContent: String = ""
    let onInteractiveElementChanged: (InteractiveElement, Int?, String, String) -> Void
    let onInteractiveElementClicked: (InteractiveElement, Int?) -> Void
    let onStatusSelected: (StatusElement, String) -> Void

    var body: some View {
        switch block.kind {
        case .heading(let level, let text):
            headingView(level: level, text: text)

        case .paragraph(let runs):
            inlineRunsView(runs)

        case .codeBlock(let language, let code):
            codeBlockView(language: language, code: code, startLine: block.startLine)

        case .blockquote(let blocks):
            blockquoteView(blocks)

        case .unorderedList(let items):
            unorderedListView(items)

        case .orderedList(let items, let startIndex):
            orderedListView(items, startIndex: startIndex)

        case .horizontalRule:
            Divider()
                .overlay(palette.comment.opacity(0.3))
                .padding(.vertical, 4)

        case .table(let headers, let rows):
            tableView(headers: headers, rows: rows)

        case .interactiveElement(let element):
            NativeControlView(
                element: element,
                documentContent: documentContent,
                palette: palette,
                onChanged: onInteractiveElementChanged,
                onClicked: onInteractiveElementClicked,
                onStatusSelected: onStatusSelected
            )

        case .image(let alt, let url):
            imageView(alt: alt, url: url)

        case .rawText(let text):
            Text(text)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(palette.foreground)
                .textSelection(.enabled)
        }
    }

    // MARK: - Heading

    private func headingView(level: Int, text: String) -> some View {
        let font: Font = switch level {
        case 1: .system(size: 24, weight: .bold, design: .monospaced)
        case 2: .system(size: 20, weight: .bold, design: .monospaced)
        case 3: .system(size: 17, weight: .semibold, design: .monospaced)
        case 4: .system(size: 15, weight: .semibold, design: .monospaced)
        default: .system(size: 14, weight: .semibold, design: .monospaced)
        }

        return highlightedText(text)
            .font(font)
            .foregroundStyle(palette.type)
            .padding(.top, level == 1 ? 12 : 8)
            .padding(.bottom, 2)
            .textSelection(.enabled)
    }

    // MARK: - Inline Runs

    private func inlineRunsView(_ runs: [InlineRun]) -> some View {
        let combined = runs.reduce(Text("")) { result, run in
            result + styledText(run)
        }

        return combined
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(palette.foreground)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func styledText(_ run: InlineRun) -> Text {
        let base = highlightedText(run.text)

        switch run.style {
        case .plain:
            return base
        case .bold:
            return base.bold()
        case .italic:
            return base.italic()
        case .boldItalic:
            return base.bold().italic()
        case .strikethrough:
            return base.strikethrough()
        case .code:
            return Text(run.text)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(palette.string)
        case .link(let url):
            var attr = AttributedString(run.text)
            attr.link = URL(string: url)
            return Text(attr)
        case .image:
            return Text("[\(run.text)]")
                .foregroundColor(palette.comment)
        }
    }

    // MARK: - Code Block

    private func codeBlockView(language: String?, code: String, startLine: Int) -> some View {
        let codeLines = code.components(separatedBy: "\n")
        // Code content starts after the ``` fence line
        let firstCodeLine = startLine + 1

        return VStack(alignment: .leading, spacing: 0) {
            // Header with language and copy button
            HStack {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(.caption)
                        .foregroundStyle(palette.comment)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(palette.comment)
                }
                .buttonStyle(.borderless)
                .help("Copy code")
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 4)

            // Code content with line numbers
            HStack(alignment: .top, spacing: 0) {
                // Line number column
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(codeLines.indices, id: \.self) { idx in
                        Text("\(firstCodeLine + idx)")
                            .font(.system(size: 10, design: .monospaced).monospacedDigit())
                            .foregroundStyle(palette.lineNumber)
                            .frame(height: 16)
                    }
                }
                .frame(width: 28)
                .padding(.leading, 4)

                // Separator
                Rectangle()
                    .fill(palette.comment.opacity(0.15))
                    .frame(width: 0.5)
                    .padding(.vertical, 2)

                // Code text
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(codeLines.indices, id: \.self) { idx in
                        highlightedText(codeLines[idx])
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(palette.foreground)
                            .frame(height: 16, alignment: .leading)
                    }
                }
                .textSelection(.enabled)
                .padding(.leading, 8)
            }
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(palette.selection.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(palette.comment.opacity(0.15), lineWidth: 0.5)
        )
    }

    // MARK: - Blockquote

    private func blockquoteView(_ blocks: [MarkdownBlock]) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(palette.keyword.opacity(0.5))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(blocks) { block in
                    ContentBlockView(
                        block: block,
                        palette: palette,
                        searchText: searchText,
                        documentContent: documentContent,
                        onInteractiveElementChanged: onInteractiveElementChanged,
                        onInteractiveElementClicked: onInteractiveElementClicked,
                        onStatusSelected: onStatusSelected
                    )
                }
            }
            .padding(.leading, 12)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Lists

    private func unorderedListView(_ items: [ListItemBlock]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\u{2022}")
                        .foregroundStyle(palette.comment)
                    inlineRunsView(item.runs)
                }
            }
        }
    }

    private func orderedListView(_ items: [ListItemBlock], startIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(startIndex + index).")
                        .foregroundStyle(palette.comment)
                        .monospacedDigit()
                        .frame(minWidth: 20, alignment: .trailing)
                    inlineRunsView(item.runs)
                }
            }
        }
    }

    // MARK: - Table

    private func tableView(headers: [String], rows: [[String]]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                ForEach(headers.indices, id: \.self) { i in
                    Text(headers[i])
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(palette.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                }
            }
            .background(palette.selection.opacity(0.3))

            Divider().overlay(palette.comment.opacity(0.2))

            // Data rows
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 0) {
                    ForEach(rows[rowIndex].indices, id: \.self) { colIndex in
                        Text(rows[rowIndex][colIndex])
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(palette.foreground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                    }
                }
                if rowIndex < rows.count - 1 {
                    Divider().overlay(palette.comment.opacity(0.1))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(palette.comment.opacity(0.15), lineWidth: 0.5)
        )
    }

    // MARK: - Image

    private func imageView(alt: String, url: String) -> some View {
        Group {
            if let imageURL = URL(string: url) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 600)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    case .failure:
                        Label(alt.isEmpty ? "Image" : alt, systemImage: "photo")
                            .foregroundStyle(palette.comment)
                    case .empty:
                        ProgressView()
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Label(alt.isEmpty ? "Image" : alt, systemImage: "photo")
                    .foregroundStyle(palette.comment)
            }
        }
    }

    // MARK: - Search Highlighting

    private func highlightedText(_ text: String) -> Text {
        guard !searchText.isEmpty else {
            return Text(text)
        }

        let lowered = text.lowercased()
        let searchLowered = searchText.lowercased()

        var result = Text("")
        var remaining = text[text.startIndex...]
        var remainingLowered = lowered[lowered.startIndex...]

        while let range = remainingLowered.range(of: searchLowered) {
            // Text before match
            let offset = remainingLowered.distance(
                from: remainingLowered.startIndex, to: range.lowerBound
            )
            let beforeEnd = text.index(remaining.startIndex, offsetBy: offset)
            let before = remaining[remaining.startIndex..<beforeEnd]
            if !before.isEmpty {
                result = result + Text(before)
            }

            // Matched text
            let matchStart = beforeEnd
            let matchEnd = text.index(matchStart, offsetBy: searchLowered.count)
            let matched = remaining[matchStart..<matchEnd]

            var matchAttr = AttributedString(matched)
            matchAttr.backgroundColor = .yellow
            matchAttr.foregroundColor = .black
            result = result + Text(matchAttr).bold()

            remaining = remaining[matchEnd...]
            remainingLowered = remainingLowered[range.upperBound...]
        }

        // Remaining text
        if !remaining.isEmpty {
            result = result + Text(remaining)
        }

        return result
    }
}
