import SwiftUI
import AppKit
import aimdRenderer

// MARK: - Content Block View

/// Renders a single `MarkdownBlock` as a SwiftUI view.
struct ContentBlockView: View {

    let block: MarkdownBlock
    let searchText: String
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
            codeBlockView(language: language, code: code)

        case .blockquote(let blocks):
            blockquoteView(blocks)

        case .unorderedList(let items):
            unorderedListView(items)

        case .orderedList(let items, let startIndex):
            orderedListView(items, startIndex: startIndex)

        case .horizontalRule:
            Divider()
                .padding(.vertical, 4)

        case .table(let headers, let rows):
            tableView(headers: headers, rows: rows)

        case .interactiveElement(let element):
            NativeControlView(
                element: element,
                onChanged: onInteractiveElementChanged,
                onClicked: onInteractiveElementClicked,
                onStatusSelected: onStatusSelected
            )

        case .image(let alt, let url):
            imageView(alt: alt, url: url)

        case .rawText(let text):
            Text(text)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
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
            .foregroundStyle(.primary)
            .padding(.top, level == 1 ? 8 : 4)
            .textSelection(.enabled)
    }

    // MARK: - Inline Runs

    private func inlineRunsView(_ runs: [InlineRun]) -> some View {
        let combined = runs.reduce(Text("")) { result, run in
            result + styledText(run)
        }

        return combined
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(.primary)
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
                .foregroundColor(.secondary)
        case .link(let url):
            var attr = AttributedString(run.text)
            attr.link = URL(string: url)
            return Text(attr)
        case .image:
            return Text("[\(run.text)]")
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Code Block

    private func codeBlockView(language: String?, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with language and copy button
            HStack {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Copy code")
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 4)

            // Code content
            highlightedText(code)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Blockquote

    private func blockquoteView(_ blocks: [MarkdownBlock]) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor.opacity(0.5))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(blocks) { block in
                    ContentBlockView(
                        block: block,
                        searchText: searchText,
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
                        .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                }
            }
            .background(Color.primary.opacity(0.05))

            Divider()

            // Data rows
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 0) {
                    ForEach(rows[rowIndex].indices, id: \.self) { colIndex in
                        Text(rows[rowIndex][colIndex])
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                    }
                }
                if rowIndex < rows.count - 1 {
                    Divider()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
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
                            .foregroundStyle(.secondary)
                    case .empty:
                        ProgressView()
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Label(alt.isEmpty ? "Image" : alt, systemImage: "photo")
                    .foregroundStyle(.secondary)
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
            let beforeEnd = text.index(remaining.startIndex, offsetBy: remainingLowered.distance(from: remainingLowered.startIndex, to: range.lowerBound))
            let before = remaining[remaining.startIndex..<beforeEnd]
            if !before.isEmpty {
                result = result + Text(before)
            }

            // Matched text — bright accent to stand out (Text concatenation doesn't support .background)
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
