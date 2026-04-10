import SwiftUI

// MARK: - SwiftUI Theme

/// SwiftUI implementation of MarkdownTheme protocol.
/// Renders markdown elements as SwiftUI Views.
///
/// OOD: Pure renderer - configuration in, View out.
/// No state management, just transformation.
///
/// Note: MainActor isolation is required because SwiftUI Views are MainActor-bound.
@MainActor
public struct SwiftUITheme: MarkdownTheme {
    public typealias Output = AnyView

    public let configuration: ThemeConfiguration

    public init(configuration: ThemeConfiguration = ThemeConfiguration()) {
        self.configuration = configuration
    }

    // MARK: - Block Renderers

    public func render(heading: HeadingInfo) -> AnyView {
        let scale = configuration.headingScale.factor(for: heading.level)
        let fontSize = configuration.fontSize * scale

        return AnyView(
            Text(heading.text)
                .font(.system(size: fontSize, weight: fontWeight(for: heading.level)))
                .foregroundStyle(palette.foreground)
                .padding(.vertical, verticalPadding(for: heading.level))
        )
    }

    public func render(paragraph: ParagraphInfo) -> AnyView {
        AnyView(
            Text(paragraph.text)
                .font(.system(size: configuration.fontSize))
                .foregroundStyle(palette.foreground)
                .padding(.vertical, 4)
        )
    }

    public func render(codeBlock: CodeBlockInfo) -> AnyView {
        return AnyView(
            CodeBlockView(
                codeBlock: codeBlock,
                fontSize: configuration.fontSize,
                palette: palette
            )
        )
    }

    public func render(link: LinkInfo) -> AnyView {
        let text = link.text
        let destination = link.destination ?? ""

        return AnyView(
            LinkView(
                text: text,
                destination: destination,
                fontSize: configuration.fontSize,
                linkColor: palette.function,
                underline: configuration.underlineLinks
            )
        )
    }

    public func render(listItem: String, ordered: Bool, index: Int?) -> AnyView {
        let marker: String
        if ordered, let idx = index {
            marker = "\(idx)."
        } else {
            marker = "\u{2022}"
        }

        return AnyView(
            HStack(alignment: .top, spacing: 8) {
                Text(marker)
                    .font(.system(size: configuration.fontSize))
                    .foregroundStyle(palette.comment)
                    .frame(width: ordered ? 24 : 16, alignment: .trailing)

                Text(listItem)
                    .font(.system(size: configuration.fontSize))
                    .foregroundStyle(palette.foreground)
            }
            .padding(.vertical, 2)
        )
    }

    public func render(blockQuote: String) -> AnyView {
        AnyView(
            HStack(spacing: 12) {
                Rectangle()
                    .fill(palette.keyword.opacity(0.5))
                    .frame(width: 4)

                Text(blockQuote)
                    .font(.system(size: configuration.fontSize))
                    .foregroundStyle(palette.comment)
                    .italic()
            }
            .padding(.vertical, 8)
        )
    }

    public func renderThematicBreak() -> AnyView {
        AnyView(
            Divider()
                .padding(.vertical, 16)
        )
    }

    public func render(image: ImageInfo) -> AnyView {
        AnyView(
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.system(size: 48))
                    .foregroundStyle(palette.comment)

                if !image.altText.isEmpty {
                    Text(image.altText)
                        .font(.system(size: configuration.fontSize - 2))
                        .foregroundStyle(palette.comment)
                        .italic()
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.vertical, 8)
        )
    }

    public func render(inlineCode: String) -> AnyView {
        return AnyView(
            Text(inlineCode)
                .font(.system(size: configuration.fontSize - 1, design: .monospaced))
                .foregroundStyle(palette.keyword)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(palette.background.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        )
    }

    public func render(emphasis: String) -> AnyView {
        AnyView(
            Text(emphasis)
                .font(.system(size: configuration.fontSize))
                .italic()
                .foregroundStyle(palette.foreground)
        )
    }

    public func render(strong: String) -> AnyView {
        AnyView(
            Text(strong)
                .font(.system(size: configuration.fontSize, weight: .bold))
                .foregroundStyle(palette.foreground)
        )
    }

    public func render(strikethrough: String) -> AnyView {
        AnyView(
            Text(strikethrough)
                .font(.system(size: configuration.fontSize))
                .strikethrough()
                .foregroundStyle(palette.comment)
        )
    }

    // MARK: - Full Document Rendering

    public func render(document: DocumentModel) -> AnyView {
        AnyView(
            DocumentRendererView(
                document: document,
                configuration: configuration
            )
        )
    }

    // MARK: - Private Helpers

    private var palette: SyntaxPalette {
        configuration.syntaxTheme.palette
    }

    private func fontWeight(for headingLevel: Int) -> Font.Weight {
        switch headingLevel {
        case 1: return .bold
        case 2: return .semibold
        case 3: return .medium
        default: return .regular
        }
    }

    private func verticalPadding(for headingLevel: Int) -> CGFloat {
        switch headingLevel {
        case 1: return 16
        case 2: return 12
        case 3: return 8
        default: return 6
        }
    }
}

// MARK: - Helper Views (for concurrency safety)

/// Code block view - extracts values to avoid closure capture issues
private struct CodeBlockView: View {
    let codeBlock: CodeBlockInfo
    let fontSize: CGFloat
    let palette: SyntaxPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language = codeBlock.language, !language.isEmpty {
                Text(language)
                    .font(.system(size: fontSize - 2, weight: .medium))
                    .foregroundStyle(palette.comment)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(codeBlock.code)
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundStyle(palette.foreground)
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(palette.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.vertical, 8)
    }
}

/// Link view - extracts values to avoid closure capture issues
private struct LinkView: View {
    let text: String
    let destination: String
    let fontSize: CGFloat
    let linkColor: Color
    let underline: Bool

    var body: some View {
        Link(destination: URL(string: destination) ?? URL(string: "about:blank")!) {
            Text(text)
                .font(.system(size: fontSize))
                .foregroundStyle(linkColor)
                .underline(underline)
        }
    }
}

// MARK: - Document Renderer View

/// SwiftUI View that renders the document using theme configuration
private struct DocumentRendererView: View {
    let document: DocumentModel
    let configuration: ThemeConfiguration

    var body: some View {
        let palette = configuration.syntaxTheme.palette
        let headingScale = configuration.headingScale
        let fontSize = configuration.fontSize

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Render headings
                ForEach(document.ast.headings) { heading in
                    let scale = headingScale.factor(for: heading.level)
                    Text(heading.text)
                        .font(.system(size: fontSize * scale, weight: fontWeight(for: heading.level)))
                        .foregroundStyle(palette.foreground)
                        .padding(.vertical, verticalPadding(for: heading.level))
                }

                // Render paragraphs
                ForEach(document.ast.paragraphs) { paragraph in
                    Text(paragraph.text)
                        .font(.system(size: fontSize))
                        .foregroundStyle(palette.foreground)
                        .padding(.vertical, 4)
                }

                // Render code blocks
                ForEach(document.ast.codeBlocks) { codeBlock in
                    CodeBlockView(
                        codeBlock: codeBlock,
                        fontSize: fontSize,
                        palette: palette
                    )
                }
            }
            .padding()
        }
        .background(palette.background)
    }

    private func fontWeight(for headingLevel: Int) -> Font.Weight {
        switch headingLevel {
        case 1: return .bold
        case 2: return .semibold
        case 3: return .medium
        default: return .regular
        }
    }

    private func verticalPadding(for headingLevel: Int) -> CGFloat {
        switch headingLevel {
        case 1: return 16
        case 2: return 12
        case 3: return 8
        default: return 6
        }
    }
}
