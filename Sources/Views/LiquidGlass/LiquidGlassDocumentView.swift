import SwiftUI
import aimdRenderer

// MARK: - Liquid Glass Document View

/// Pure SwiftUI renderer that displays a markdown document as nested glass-material blocks.
/// Headings create nested containers with compounding `.ultraThinMaterial`.
/// All interactive elements render as native macOS controls.
struct LiquidGlassDocumentView: View {

    let content: String
    let onInteractiveElementChanged: (InteractiveElement, Int?, String, String) -> Void
    let onInteractiveElementClicked: (InteractiveElement, Int?) -> Void
    let onStatusSelected: (StatusElement, String) -> Void

    @State private var collapsedSections: Set<String> = []
    @State private var searchText: String = ""
    @State private var isSearching: Bool = false
    @State private var matchCount: Int = 0
    @State private var currentMatchIndex: Int = 0
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        let structure = MarkdownStructureParser.parse(text: content)

        VStack(spacing: 0) {
            // Cmd+F search bar
            if isSearching {
                searchBar
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    // Preamble content (before first heading) lives on the root blob
                    let preambleBlocks = preambleBlocks(from: structure)
                    ForEach(preambleBlocks) { block in
                        ContentBlockView(
                            block: block,
                            searchText: searchText,
                            onInteractiveElementChanged: onInteractiveElementChanged,
                            onInteractiveElementClicked: onInteractiveElementClicked,
                            onStatusSelected: onStatusSelected
                        )
                    }

                    // Sections as glass blocks
                    ForEach(structure.sections.filter { $0.level > 0 }) { section in
                        GlassSectionView(
                            section: section,
                            content: content,
                            depth: 1,
                            collapsedSections: $collapsedSections,
                            searchText: searchText,
                            onInteractiveElementChanged: onInteractiveElementChanged,
                            onInteractiveElementClicked: onInteractiveElementClicked,
                            onStatusSelected: onStatusSelected
                        )
                    }
                }
                .padding(16)
            }
            .font(.system(.body, design: .monospaced))
            .background(.ultraThinMaterial)
        }
        .background {
            // Hidden button to capture Cmd+F
            Button("") {
                isSearching = true
                searchFieldFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .hidden()
        }
        .onChange(of: searchText) {
            updateMatchCount()
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Find...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .focused($searchFieldFocused)
                .onSubmit {
                    // Move to next match
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
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 60)
            } else if !searchText.isEmpty {
                Text("No matches")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                dismissSearch()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
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

    /// Extract preamble content — sections with level 0 (content before first heading)
    private func preambleBlocks(from structure: DocumentStructure) -> [MarkdownBlock] {
        let preambleSections = structure.sections.filter { $0.level == 0 }
        guard let preamble = preambleSections.first else { return [] }
        return MarkdownBlockParser.parse(
            content: content,
            sectionRange: preamble.range,
            elements: preamble.elements
        )
    }
}
