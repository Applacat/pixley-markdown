import SwiftUI
import aimdRenderer

// MARK: - Glass Section View

/// Renders a single `Section` as a glass-material block.
/// Clicking the heading collapses/expands the section.
/// Depth caps visual compounding at 4.
struct GlassSectionView: View {

    let section: aimdRenderer.Section
    let content: String
    let depth: Int
    @Binding var collapsedSections: Set<String>
    let searchText: String
    let onInteractiveElementChanged: (InteractiveElement, Int?, String, String) -> Void
    let onInteractiveElementClicked: (InteractiveElement, Int?) -> Void
    let onStatusSelected: (StatusElement, String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isCollapsed: Bool {
        collapsedSections.contains(section.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Heading row — tap to collapse
            headingRow

            // Content (when not collapsed)
            if !isCollapsed {
                sectionContent
            }
        }
        .padding(12)
        .background(glassBackground)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    // MARK: - Heading Row

    private var headingRow: some View {
        HStack(spacing: 8) {
            Text(section.title)
                .font(headingFont)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer()

            if isCollapsed {
                Text("\(lineCount) lines")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.5), in: Capsule())
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.8)) {
                if isCollapsed {
                    collapsedSections.remove(section.id)
                } else {
                    collapsedSections.insert(section.id)
                }
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(section.title), \(isCollapsed ? "collapsed" : "expanded")")
        .accessibilityHint("Tap to \(isCollapsed ? "expand" : "collapse")")
    }

    // MARK: - Section Content

    private var sectionContent: some View {
        let blocks = sectionBlocks

        return VStack(alignment: .leading, spacing: 8) {
            // Direct content blocks (not in child sections)
            ForEach(blocks) { block in
                ContentBlockView(
                    block: block,
                    searchText: searchText,
                    onInteractiveElementChanged: onInteractiveElementChanged,
                    onInteractiveElementClicked: onInteractiveElementClicked,
                    onStatusSelected: onStatusSelected
                )
            }

            // Child sections as nested glass blocks
            ForEach(section.children) { child in
                GlassSectionView(
                    section: child,
                    content: content,
                    depth: min(depth + 1, 4),
                    collapsedSections: $collapsedSections,
                    searchText: searchText,
                    onInteractiveElementChanged: onInteractiveElementChanged,
                    onInteractiveElementClicked: onInteractiveElementClicked,
                    onStatusSelected: onStatusSelected
                )
            }
        }
    }

    // MARK: - Block Parsing

    private var sectionBlocks: [MarkdownBlock] {
        // Parse the section's own content (between heading and first child or end)
        let ownRange = sectionOwnContentRange
        guard let range = ownRange else { return [] }
        return MarkdownBlockParser.parse(
            content: content,
            sectionRange: range,
            elements: section.elements
        )
    }

    /// The range of this section's own content (after heading, before first child).
    private var sectionOwnContentRange: Range<String.Index>? {
        guard !section.title.isEmpty else { return section.range }

        // Find the end of the heading line
        let headingLine = content[section.range]
        guard let newlineIndex = headingLine.firstIndex(of: "\n") else {
            // Single-line section (just a heading, no content)
            return nil
        }

        let contentStart = content.index(after: newlineIndex)

        // Content ends at the first child's start, or at section end
        let contentEnd: String.Index
        if let firstChild = section.children.first {
            contentEnd = firstChild.range.lowerBound
        } else {
            contentEnd = section.range.upperBound
        }

        guard contentStart < contentEnd else { return nil }
        return contentStart..<contentEnd
    }

    // MARK: - Line Count

    private var lineCount: Int {
        let text = String(content[section.range])
        return text.components(separatedBy: "\n").count
    }

    // MARK: - Glass Material

    @ViewBuilder
    private var glassBackground: some View {
        // Cap visual depth at 4 — deeper sections look the same as depth 4
        let effectiveDepth = min(depth, 4)
        let opacity = 0.08 + Double(effectiveDepth) * 0.04

        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.primary.opacity(opacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
    }

    private var cornerRadius: CGFloat {
        max(12 - CGFloat(depth) * 2, 6)
    }

    // MARK: - Typography

    private var headingFont: Font {
        switch section.level {
        case 1: return .system(size: 24, weight: .bold, design: .monospaced)
        case 2: return .system(size: 20, weight: .bold, design: .monospaced)
        case 3: return .system(size: 17, weight: .semibold, design: .monospaced)
        case 4: return .system(size: 15, weight: .semibold, design: .monospaced)
        default: return .system(size: 14, weight: .semibold, design: .monospaced)
        }
    }
}
