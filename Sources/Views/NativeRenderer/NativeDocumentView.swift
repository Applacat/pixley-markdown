import SwiftUI
import aimdRenderer

// MARK: - Scroll Metrics

private struct ScrollMetrics: Equatable {
    let contentMinY: CGFloat
    let contentHeight: CGFloat
    let viewportHeight: CGFloat
}

// MARK: - Gutter Row Model

/// A single renderable row in the outer gutter/content grid. Every source line
/// (including blank lines) gets a row so the gutter sequence is continuous.
struct GutterRowModel: Identifiable {
    enum Kind {
        case blank
        case block(MarkdownBlock)
        case unorderedListItem(ListItemBlock)
        case orderedListItem(ListItemBlock, displayNumber: Int)
    }
    let id: String
    let lineNumber: Int
    let kind: Kind
}

// MARK: - Native Document View

/// Pure SwiftUI renderer that displays a markdown document as a flat monospace scroll
/// styled with the current SyntaxPalette. All interactive elements render as native macOS controls.
/// Layout: Single ScrollView containing per-row HStack { GutterLineView | ContentBlockView }
struct NativeDocumentView: View {

    let content: String
    let palette: SyntaxPalette
    let fontSize: CGFloat
    let bookmarkedLines: Set<Int>
    let commentedLines: Set<Int>
    let onInteractiveElementChanged: (InteractiveElement, Int?, String, String) -> Void
    let onInteractiveElementClicked: (InteractiveElement, Int?) -> Void
    let onStatusSelected: (StatusElement, String) -> Void
    let onToggleBookmark: (Int) -> Void
    let onAddComment: (Int, String) -> Void
    var onScrollProgressChanged: ((Double) -> Void)? = nil

    @State private var cachedBlocks: [MarkdownBlock] = []
    @State private var cachedContent: String = ""
    @State private var gutterRows: [GutterRowModel] = []
    /// Precomputed comment threads per line — avoids per-row regex + string split during scroll.
    @State private var commentThreadCache: [Int: [String]] = [:]
    @State private var searchText: String = ""
    /// Debounced version of searchText — passed to ContentBlockView to avoid per-keystroke re-renders.
    @State private var debouncedSearchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var isSearching: Bool = false
    @State private var matchCount: Int = 0
    @State private var currentMatchIndex: Int = 0
    @State private var isGoToLineVisible: Bool = false
    @State private var scrollTarget: Int? = nil
    @State private var currentScrollOffset: CGFloat = 0
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if isSearching {
                searchBar
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(gutterRows) { row in
                            renderGutterRow(row)
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.trailing, 16)
                    .onGeometryChange(for: ScrollMetrics.self) { geo in
                        ScrollMetrics(
                            contentMinY: geo.frame(in: .named("scrollArea")).minY,
                            contentHeight: geo.size.height,
                            viewportHeight: 0
                        )
                    } action: { metrics in
                        currentScrollOffset = -metrics.contentMinY
                        lastContentHeight = metrics.contentHeight
                        reportScrollProgress(viewportHeight: lastViewportHeight)
                    }
                }
                .coordinateSpace(name: "scrollArea")
                .onGeometryChange(for: CGFloat.self) { geo in
                    geo.size.height
                } action: { viewportHeight in
                    lastViewportHeight = viewportHeight
                    reportScrollProgress(viewportHeight: viewportHeight)
                }
                .font(.system(.body, design: .monospaced))
                .background(palette.background)
                .onChange(of: scrollTarget) { _, target in
                    if let target {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            proxy.scrollTo(target, anchor: .top)
                        }
                        scrollTarget = nil
                    }
                }
            }
        }
        .overlay {
            if isGoToLineVisible {
                GoToLineOverlay(
                    palette: palette,
                    maxLine: cachedBlocks.last?.endLine ?? 0,
                    onGoToLine: { line in
                        scrollToLine(line)
                        isGoToLineVisible = false
                    },
                    onDismiss: {
                        isGoToLineVisible = false
                    }
                )
            }
        }
        .background {
            Group {
                Button("") {
                    isSearching = true
                    searchFieldFocused = true
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("") {
                    isGoToLineVisible = true
                }
                .keyboardShortcut("g", modifiers: .command)

                Button("") {
                    toggleBookmarkAtCurrentPosition()
                }
                .keyboardShortcut("b", modifiers: .command)
            }
            .hidden()
        }
        .onChange(of: searchText) {
            // Debounce search highlighting to avoid per-keystroke re-renders
            // of every visible ContentBlockView (each runs string scans)
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                debouncedSearchText = searchText
                updateMatchCount()
            }
        }
        .onAppear {
            reparse()
        }
        .onChange(of: content) {
            reparse()
        }
    }

    // MARK: - Row Rendering (Per-Line Gutter Alignment)

    @ViewBuilder
    private func renderGutterRow(_ row: GutterRowModel) -> some View {
        switch row.kind {
        case .blank:
            gutterRow(lineNumber: row.lineNumber, rowID: row.id) {
                // Blank line: single-line height matching surrounding text
                Text(" ")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.clear)
            }

        case .unorderedListItem(let item):
            gutterRow(lineNumber: row.lineNumber, rowID: row.id) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\u{2022}")
                        .foregroundStyle(palette.comment)
                    inlineRunsView(item.runs)
                }
            }

        case .orderedListItem(let item, let displayNumber):
            gutterRow(lineNumber: row.lineNumber, rowID: row.id) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(displayNumber).")
                        .foregroundStyle(palette.comment)
                        .monospacedDigit()
                        .frame(minWidth: 20, alignment: .trailing)
                    inlineRunsView(item.runs)
                }
            }

        case .block(let block):
            gutterRow(lineNumber: row.lineNumber, rowID: row.id) {
                ContentBlockView(
                    block: block,
                    palette: palette,
                    searchText: debouncedSearchText,
                    documentContent: content,
                    onInteractiveElementChanged: onInteractiveElementChanged,
                    onInteractiveElementClicked: onInteractiveElementClicked,
                    onStatusSelected: onStatusSelected
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// A single row in the outer gutter/content grid: one gutter cell + padding + one content cell.
    @ViewBuilder
    private func gutterRow<Content: View>(
        lineNumber: Int,
        rowID: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 0) {
            GutterLineView(
                lineNumber: lineNumber,
                isBookmarked: bookmarkedLines.contains(lineNumber),
                isCommented: commentedLines.contains(lineNumber),
                existingComments: commentThreadCache[lineNumber] ?? [],
                palette: palette,
                fontSize: fontSize,
                onToggleBookmark: { onToggleBookmark(lineNumber) },
                onAddComment: { text in onAddComment(lineNumber, text) }
            )
            // Vertical separator between gutter and content
            Rectangle()
                .fill(palette.comment.opacity(0.15))
                .frame(width: 0.5)
                .padding(.horizontal, 12)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(rowID)
    }

    /// Renders inline styled runs for list items (used by per-item list rows).
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
        switch run.style {
        case .plain: return Text(run.text)
        case .bold: return Text(run.text).bold()
        case .italic: return Text(run.text).italic()
        case .boldItalic: return Text(run.text).bold().italic()
        case .strikethrough: return Text(run.text).strikethrough()
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

    // MARK: - Comment Thread Precomputation

    private static let commentRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"<!--\s*feedback\s*(?::\s*(.*?))?\s*-->"#)
    }()

    /// Precomputes comment threads for all lines in one pass.
    /// Called from Task.detached in reparse() — must be nonisolated.
    private nonisolated static func precomputeCommentThreads(from content: String) -> [Int: [String]] {
        guard let regex = commentRegex else { return [:] }
        let lines = content.components(separatedBy: "\n")
        var result: [Int: [String]] = [:]

        for (i, line) in lines.enumerated() {
            let nsRange = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, range: nsRange),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: line) {
                // Attribute comment to the preceding content line (1-based)
                let targetLine = i // line i is after the content line at i-1 (0-based)
                result[targetLine, default: []].append(String(line[range]))
            }
        }
        return result
    }

    // MARK: - Cache + Diff

    /// Parses markdown off the main thread to avoid blocking UI during file open.
    /// Content guard prevents duplicate parses for the same text.
    private func reparse() {
        guard content != cachedContent else { return }
        let textToParse = content
        cachedContent = textToParse

        Task.detached(priority: .userInitiated) {
            let structure = MarkdownStructureParser.parse(text: textToParse)
            let blocks = MarkdownBlockParser.parseFlat(content: textToParse, elements: structure.elements)

            // Precompute comment threads in one pass (was per-row during scroll)
            let threads = Self.precomputeCommentThreads(from: textToParse)

            await MainActor.run {
                guard textToParse == cachedContent else { return }
                cachedBlocks = blocks
                commentThreadCache = threads
                gutterRows = Self.computeGutterRows(blocks: blocks, content: textToParse)
            }
        }
    }

    /// Flattens blocks into per-line rows, emitting blank spacer rows for empty source lines
    /// so every line number from 1..N appears in the gutter.
    private static func computeGutterRows(blocks: [MarkdownBlock], content: String) -> [GutterRowModel] {
        let totalLines = content.isEmpty ? 0 : content.components(separatedBy: "\n").count
        guard totalLines > 0 else { return [] }

        var rows: [GutterRowModel] = []
        var cursor = 1

        func emitBlanks(upTo target: Int) {
            while cursor < target {
                rows.append(GutterRowModel(id: "blank-\(cursor)", lineNumber: cursor, kind: .blank))
                cursor += 1
            }
        }

        for block in blocks {
            emitBlanks(upTo: block.startLine)

            switch block.kind {
            case .unorderedList(let items):
                for item in items {
                    emitBlanks(upTo: item.startLine)
                    rows.append(GutterRowModel(
                        id: "ulist-\(block.id)-\(item.startLine)",
                        lineNumber: item.startLine,
                        kind: .unorderedListItem(item)
                    ))
                    cursor = item.startLine + 1
                }
            case .orderedList(let items, let startIndex):
                for (offset, item) in items.enumerated() {
                    emitBlanks(upTo: item.startLine)
                    rows.append(GutterRowModel(
                        id: "olist-\(block.id)-\(item.startLine)",
                        lineNumber: item.startLine,
                        kind: .orderedListItem(item, displayNumber: startIndex + offset)
                    ))
                    cursor = item.startLine + 1
                }
            default:
                rows.append(GutterRowModel(
                    id: "block-\(block.id)",
                    lineNumber: block.startLine,
                    kind: .block(block)
                ))
                cursor = block.endLine + 1
            }
        }

        // Trailing blank lines
        emitBlanks(upTo: totalLines + 1)

        return rows
    }

    // MARK: - Scroll Progress

    @State private var lastViewportHeight: CGFloat = 0
    @State private var lastContentHeight: CGFloat = 0
    @State private var lastReportedProgress: Double = -1

    private func reportScrollProgress(viewportHeight: CGFloat) {
        let scrollable = lastContentHeight - viewportHeight
        let progress: Double
        if scrollable > 0 {
            progress = min(max(currentScrollOffset / scrollable, 0), 1)
        } else {
            progress = 0
        }
        // Throttle: only fire callback when progress changes by >0.5% to break potential
        // feedback loops from parent re-renders that recreate closures.
        if abs(progress - lastReportedProgress) > 0.005 {
            lastReportedProgress = progress
            onScrollProgressChanged?(progress)
        }
    }

    // MARK: - Scroll To Line

    private func scrollToLine(_ line: Int) {
        guard let block = cachedBlocks.first(where: { $0.startLine <= line && $0.endLine >= line }) else { return }
        scrollTarget = block.id
    }

    // MARK: - Bookmark at Current Position

    private func toggleBookmarkAtCurrentPosition() {
        // Estimate nearest visible line from scroll offset and content height
        guard !cachedBlocks.isEmpty, lastContentHeight > 0 else {
            if let first = cachedBlocks.first { onToggleBookmark(first.startLine) }
            return
        }
        let totalLines = max(1, cachedBlocks.last?.endLine ?? 1)
        let ratio = min(max(currentScrollOffset / lastContentHeight, 0), 1)
        let targetLine = max(1, Int((Double(totalLines) * Double(ratio)).rounded()))
        // Find the block containing or starting at that line
        let block = cachedBlocks.first { $0.startLine <= targetLine && $0.endLine >= targetLine }
            ?? cachedBlocks.first
        onToggleBookmark(block?.startLine ?? 1)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.comment)

            TextField("Find...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .focused($searchFieldFocused)
                .onSubmit {
                    if matchCount > 0 {
                        currentMatchIndex = (currentMatchIndex + 1) % matchCount
                    }
                }
                #if os(macOS)
                .onExitCommand {
                    dismissSearch()
                }
                #endif

            if matchCount > 0 {
                Text("\(currentMatchIndex + 1) of \(matchCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.comment)
                    .frame(minWidth: 60)
            } else if !searchText.isEmpty {
                Text("No matches")
                    .font(.caption)
                    .foregroundStyle(palette.comment)
            }

            Button {
                dismissSearch()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(palette.comment)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.background)
    }

    private func dismissSearch() {
        isSearching = false
        searchText = ""
        currentMatchIndex = 0
        matchCount = 0
    }

    private func updateMatchCount() {
        guard !searchText.isEmpty else {
            matchCount = 0
            currentMatchIndex = 0
            return
        }
        let lowered = content.lowercased()
        let searchLowered = searchText.lowercased()
        var count = 0
        var searchRange = lowered.startIndex..<lowered.endIndex
        while let range = lowered.range(of: searchLowered, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<lowered.endIndex
        }
        matchCount = count
        if currentMatchIndex >= count {
            currentMatchIndex = 0
        }
    }
}

// MARK: - Gutter Line View

/// A single gutter row showing a line number, bookmark indicator, and comment indicator.
/// Click toggles bookmark. Right-click (secondary) opens comment popover.
private struct GutterLineView: View {
    let lineNumber: Int
    let isBookmarked: Bool
    let isCommented: Bool
    let existingComments: [String]
    let palette: SyntaxPalette
    let fontSize: CGFloat
    let onToggleBookmark: () -> Void
    let onAddComment: (String) -> Void

    @State private var showCommentPopover: Bool = false

    var body: some View {
        HStack(spacing: 2) {
            // Indicator dots
            VStack(spacing: 1) {
                if isBookmarked {
                    Circle()
                        .fill(palette.keyword)
                        .frame(width: 6, height: 6)
                }
                if isCommented {
                    Circle()
                        .fill(palette.comment)
                        .frame(width: 6, height: 6)
                }
            }
            .frame(width: 10)

            Text("\(lineNumber)")
                .font(.system(.caption2, design: .monospaced).monospacedDigit())
                .foregroundStyle(palette.lineNumber)
        }
        .frame(width: GutterView.width, alignment: .trailing)
        .padding(.trailing, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggleBookmark()
        }
        .contextMenu {
            Button("Add Comment...") {
                showCommentPopover = true
            }
            Button(isBookmarked ? "Remove Bookmark" : "Add Bookmark") {
                onToggleBookmark()
            }
        }
        .accessibilityLabel("Line \(lineNumber)")
        .accessibilityValue(isBookmarked ? "Bookmarked" : "")
        .accessibilityHint("Tap to toggle bookmark")
        .accessibilityAction(named: "Toggle Bookmark") {
            onToggleBookmark()
        }
        .accessibilityAction(named: "Add Comment") {
            showCommentPopover = true
        }
        .popover(isPresented: $showCommentPopover, arrowEdge: .trailing) {
            CommentPopoverView(
                existingComments: existingComments,
                palette: palette,
                onAdd: { text in
                    onAddComment(text)
                    showCommentPopover = false
                }
            )
        }
    }
}

// MARK: - Comment Popover View

/// Popover showing existing comment thread and input for new comment.
private struct CommentPopoverView: View {
    let existingComments: [String]
    let palette: SyntaxPalette
    let onAdd: (String) -> Void

    @State private var newCommentText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !existingComments.isEmpty {
                // Thread: existing comments
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(existingComments.indices, id: \.self) { idx in
                            Text(existingComments[idx])
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(palette.foreground)
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(palette.selection.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
                .frame(maxHeight: 150)

                Divider()
            }

            // New comment input
            HStack(spacing: 6) {
                TextField("Add comment...", text: $newCommentText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .focused($isFocused)
                    .onSubmit {
                        submitComment()
                    }

                Button("Add") {
                    submitComment()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(10)
        .frame(width: 280)
        .onAppear {
            isFocused = true
        }
    }

    private func submitComment() {
        var text = newCommentText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        // Sanitize: strip --> to prevent HTML comment corruption
        text = text.replacingOccurrences(of: "-->", with: "—>")
        text = text.replacingOccurrences(of: "--", with: "—")
        onAdd(text)
    }
}
