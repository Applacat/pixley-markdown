import SwiftUI
import aimdRenderer

// MARK: - Scroll Metrics

private struct ScrollMetrics: Equatable {
    let contentMinY: CGFloat
    let contentHeight: CGFloat
    let viewportHeight: CGFloat
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
    @State private var searchText: String = ""
    @State private var isSearching: Bool = false
    @State private var matchCount: Int = 0
    @State private var currentMatchIndex: Int = 0
    @State private var isGoToLineVisible: Bool = false
    @State private var scrollTarget: Int? = nil
    @State private var currentScrollOffset: CGFloat = 0
    @State private var blockOffsets: [Int: CGFloat] = [:]
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if isSearching {
                searchBar
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(cachedBlocks) { block in
                            HStack(alignment: .top, spacing: 0) {
                                GutterLineView(
                                    lineNumber: block.startLine,
                                    isBookmarked: bookmarkedLines.contains(block.startLine),
                                    isCommented: commentedLines.contains(block.startLine),
                                    existingComments: extractCommentThread(for: block.startLine),
                                    palette: palette,
                                    fontSize: fontSize,
                                    onToggleBookmark: { onToggleBookmark(block.startLine) },
                                    onAddComment: { text in onAddComment(block.startLine, text) }
                                )

                                ContentBlockView(
                                    block: block,
                                    palette: palette,
                                    searchText: searchText,
                                    onInteractiveElementChanged: onInteractiveElementChanged,
                                    onInteractiveElementClicked: onInteractiveElementClicked,
                                    onStatusSelected: onStatusSelected
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .id(block.id)
                            .onGeometryChange(for: CGFloat.self) { geo in
                                geo.frame(in: .named("scrollArea")).minY
                            } action: { minY in
                                blockOffsets[block.id] = minY
                            }
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
                    }
                }
                .coordinateSpace(name: "scrollArea")
                .onGeometryChange(for: CGFloat.self) { geo in
                    geo.size.height
                } action: { viewportHeight in
                    reportScrollProgress(viewportHeight: viewportHeight)
                }
                .font(.system(.body, design: .monospaced))
                .background(palette.background)
                .onChange(of: currentScrollOffset) { _, _ in
                    reportScrollProgress(viewportHeight: lastViewportHeight)
                }
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
            updateMatchCount()
        }
        .onAppear {
            reparse()
        }
        .onChange(of: content) {
            reparse()
        }
    }

    // MARK: - Comment Thread Extraction

    /// Extracts existing comment texts for a given content line by scanning consecutive
    /// `<!-- comment: ... -->` tags on the lines following it.
    private func extractCommentThread(for lineNumber: Int) -> [String] {
        let lines = content.components(separatedBy: "\n")
        guard lineNumber >= 1 && lineNumber <= lines.count else { return [] }

        var comments: [String] = []
        let commentPattern = #"<!--\s*feedback\s*(?::\s*(.*?))?\s*-->"#
        let regex = try? NSRegularExpression(pattern: commentPattern)

        // Scan lines after the content line for consecutive comment tags
        var i = lineNumber // 0-indexed = lineNumber (since lineNumber is 1-based, lines[lineNumber] is the next line)
        while i < lines.count {
            let line = lines[i]
            let nsRange = NSRange(line.startIndex..., in: line)
            if let match = regex?.firstMatch(in: line, range: nsRange),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: line) {
                comments.append(String(line[range]))
                i += 1
            } else {
                break
            }
        }
        return comments
    }

    // MARK: - Cache + Diff

    private func reparse() {
        guard content != cachedContent else { return }
        let structure = MarkdownStructureParser.parse(text: content)
        cachedBlocks = MarkdownBlockParser.parseFlat(content: content, elements: structure.elements)
        cachedContent = content
        blockOffsets = [:]
    }

    // MARK: - Scroll Progress

    @State private var lastViewportHeight: CGFloat = 0
    @State private var lastContentHeight: CGFloat = 0

    private func reportScrollProgress(viewportHeight: CGFloat) {
        lastViewportHeight = viewportHeight
        let scrollable = lastContentHeight - viewportHeight
        guard scrollable > 0 else {
            onScrollProgressChanged?(0)
            return
        }
        let progress = min(max(currentScrollOffset / scrollable, 0), 1)
        onScrollProgressChanged?(progress)
    }

    // MARK: - Scroll To Line

    private func scrollToLine(_ line: Int) {
        guard let block = cachedBlocks.first(where: { $0.startLine <= line && $0.endLine >= line }) else { return }
        scrollTarget = block.id
    }

    // MARK: - Bookmark at Current Position

    private func toggleBookmarkAtCurrentPosition() {
        // Find the block whose top is nearest to (but not far below) the viewport top
        let nearestBlock = cachedBlocks
            .filter { blockOffsets[$0.id] != nil }
            .min(by: { abs(blockOffsets[$0.id]!) < abs(blockOffsets[$1.id]!) })

        let line = nearestBlock?.startLine ?? cachedBlocks.first?.startLine ?? 1
        onToggleBookmark(line)
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
                .onExitCommand {
                    dismissSearch()
                }

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
                .font(.system(size: max(9, fontSize * 0.78)).monospacedDigit())
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
