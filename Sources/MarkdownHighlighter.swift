import AppKit
import Foundation
import aimdRenderer

/// A focused Markdown highlighter with lazy-compiled patterns and debouncing support.
/// Core highlighting logic is nonisolated for testability; only debouncing requires @MainActor.
///
/// Uses aimdRenderer's SyntaxTheme system for consistent theming across the app.
final class MarkdownHighlighter {

    // MARK: - Theme (now powered by aimdRenderer)

    /// Converts aimdRenderer SyntaxPalette to NSColors for AppKit rendering
    struct Theme {
        let heading1: NSColor
        let heading2: NSColor
        let heading3: NSColor
        let bold: NSColor
        let italic: NSColor
        let code: NSColor
        let codeBackground: NSColor
        let link: NSColor
        let listMarker: NSColor
        let blockquote: NSColor
        let separator: NSColor
        let foreground: NSColor
        let background: NSColor

        /// Creates a Theme from an aimdRenderer SyntaxPalette
        init(from palette: SyntaxPalette) {
            self.heading1 = NSColor(hex: palette.type) ?? .systemBlue
            self.heading2 = NSColor(hex: palette.function) ?? .systemIndigo
            self.heading3 = NSColor(hex: palette.keyword) ?? .systemPurple
            self.bold = NSColor(hex: palette.foreground) ?? .labelColor
            self.italic = NSColor(hex: palette.foreground) ?? .labelColor
            self.code = NSColor(hex: palette.string) ?? .systemOrange
            self.codeBackground = (NSColor(hex: palette.selection) ?? .quaternaryLabelColor).withAlphaComponent(0.3)
            self.link = NSColor(hex: palette.function) ?? .systemTeal
            self.listMarker = NSColor(hex: palette.comment) ?? .systemGray
            self.blockquote = NSColor(hex: palette.comment) ?? .secondaryLabelColor
            self.separator = NSColor(hex: palette.lineNumber) ?? .separatorColor
            self.foreground = NSColor(hex: palette.foreground) ?? .labelColor
            self.background = NSColor(hex: palette.background) ?? .textBackgroundColor
        }

        /// Default theme using Xcode Dark palette
        static let `default` = Theme(from: SyntaxTheme.xcodeDark.palette)
    }

    // MARK: - Highlight Rules

    private enum HighlightRule {
        case heading
        case codeBlock
        case inlineCode
        case bold
        case italic
        case link
        case bareLink
        case listMarker
        case blockquote
        case separator
    }

    // MARK: - Heading Scale

    enum HeadingScale {
        case compact   // 1.1, 1.05, 1.0
        case normal    // 1.6, 1.4, 1.2
        case spacious  // 2.0, 1.7, 1.4

        var multipliers: (h1: CGFloat, h2: CGFloat, h3: CGFloat) {
            switch self {
            case .compact:  return (1.1, 1.05, 1.0)
            case .normal:   return (1.6, 1.4, 1.2)
            case .spacious: return (2.0, 1.7, 1.4)
            }
        }
    }

    // MARK: - Properties

    let theme: Theme
    let baseFont: NSFont
    let headingScale: HeadingScale

    /// Compiled patterns - created once, reused for every highlight call
    private let patterns: [(NSRegularExpression, HighlightRule)]

    // MARK: - Initialization

    init(theme: Theme = .default, fontSize: CGFloat = 14, fontFamily: String? = nil, headingScale: HeadingScale = .normal) {
        self.theme = theme
        self.headingScale = headingScale
        self.baseFont = Self.resolveFont(family: fontFamily, size: fontSize, weight: .regular)
        self.patterns = Self.compilePatterns()
    }

    /// Resolves a font from family name, using system font descriptors for Apple fonts.
    static func resolveFont(family: String?, size: CGFloat, weight: NSFont.Weight) -> NSFont {
        guard let family else {
            return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        }

        switch family {
        case "New York":
            // Serif system font via descriptor
            let descriptor = NSFont.systemFont(ofSize: size, weight: weight)
                .fontDescriptor.withDesign(.serif)
            return descriptor.flatMap { NSFont(descriptor: $0, size: size) }
                ?? NSFont.systemFont(ofSize: size, weight: weight)
        case "SF Pro":
            return NSFont.systemFont(ofSize: size, weight: weight)
        case "SF Mono":
            return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        default:
            // Try direct name lookup for third-party fonts
            return NSFont(name: family, size: size)
                ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
    }

    /// Convenience initializer using aimdRenderer's SyntaxTheme
    convenience init(syntaxTheme: SyntaxTheme, fontSize: CGFloat = 14, fontFamily: String? = nil, headingScale: HeadingScale = .normal) {
        self.init(theme: Theme(from: syntaxTheme.palette), fontSize: fontSize, fontFamily: fontFamily, headingScale: headingScale)
    }

    // MARK: - Pattern Compilation

    private static func compilePatterns() -> [(NSRegularExpression, HighlightRule)] {
        let definitions: [(String, HighlightRule)] = [
            (#"^(#{1,6})\s+(.+)$"#, .heading),
            (#"```[\s\S]*?```"#, .codeBlock),
            (#"`[^`\n]+`"#, .inlineCode),
            (#"\*\*(.+?)\*\*|__(.+?)__"#, .bold),
            (#"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)|(?<!_)_(?!_)(.+?)(?<!_)_(?!_)"#, .italic),
            (#"\[([^\]]+)\]\(([^\)]+)\)"#, .link),
            (#"(?<!\()https?://[^\s\]\)>]+"#, .bareLink),
            (#"^[\t ]*[-*+][\t ]"#, .listMarker),
            (#"^[\t ]*\d+\.[\t ]"#, .listMarker),
            (#"^>.*$"#, .blockquote),
            (#"^[-*_]{3,}$"#, .separator),
        ]

        return definitions.compactMap { pattern, rule in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
                return nil
            }
            return (regex, rule)
        }
    }

    // MARK: - Highlighting (Core - Testable)

    /// Pure highlighting logic - no MainActor constraint for testability
    /// Security: Refuses to highlight files over 1MB to prevent regex DoS
    func highlight(_ text: String) -> NSAttributedString {
        // Security: Don't highlight extremely large files (prevents regex catastrophic backtracking)
        // Files over 1MB are shown as plain text with base styling
        guard text.utf8.count <= MarkdownConfig.maxHighlightSize else {
            return NSAttributedString(string: text, attributes: [
                .font: baseFont,
                .foregroundColor: theme.foreground
            ])
        }

        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: baseFont,
            .foregroundColor: theme.foreground
        ])

        let fullRange = NSRange(location: 0, length: attributed.length)

        for (regex, rule) in patterns {
            let matches = regex.matches(in: text, range: fullRange)
            for match in matches {
                applyRule(rule, to: attributed, match: match)
            }
        }

        return attributed
    }

    /// Annotates an already-highlighted attributed string with interactive element styling.
    /// Adds custom attributes, visual affordances, and tooltips for clickable elements.
    /// Click targets span full element ranges (not just bracket characters) for discoverability.
    ///
    /// - Parameters:
    ///   - enhanced: When true, applies full visual affordances (pills, backgrounds, tooltips).
    ///               When false, only adds click targets and cursor attributes (plain mode).
    func annotateInteractiveElements(_ attributed: NSMutableAttributedString, elements: [InteractiveElement], text: String, enhanced: Bool = true) {
        // Plain mode: just add click targets and tooltips, no visual styling
        if !enhanced {
            annotatePlainClickTargets(attributed, elements: elements, text: text)
            // Still replace x with ✓ for checked items (readability, not styling)
            replaceCheckGlyphs(attributed, elements: elements, text: text)
            return
        }

        for element in elements {
            let swiftRange = element.range
            guard let nsRange = Optional(NSRange(swiftRange, in: text)) else { continue }
            guard nsRange.location + nsRange.length <= attributed.length else { continue }

            let wrapper = InteractiveElementWrapper(element)

            switch element {
            case .checkbox(let cb):
                // Click target: the FULL line
                attributed.addAttribute(.interactiveElement, value: wrapper, range: nsRange)
                let tooltip = cb.isChecked ? "Click to uncheck" : "Click to mark as complete"
                attributed.addAttribute(.toolTip, value: tooltip, range: nsRange)
                // Dim checked items to show completion
                if cb.isChecked {
                    attributed.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: nsRange)
                    attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
                    attributed.addAttribute(.strikethroughColor, value: NSColor.secondaryLabelColor.withAlphaComponent(0.4), range: nsRange)
                }

            case .choice(let ch):
                for (i, option) in ch.options.enumerated() {
                    let optionNS = NSRange(option.range, in: text)
                    guard optionNS.location + optionNS.length <= attributed.length else { continue }
                    let optionWrapper = InteractiveElementWrapper(element, optionIndex: i)
                    attributed.addAttribute(.interactiveElement, value: optionWrapper, range: optionNS)
                    attributed.addAttribute(.toolTip, value: "Click to select this option", range: optionNS)
                    if option.isSelected {
                        attributed.addAttribute(.backgroundColor, value: NSColor.systemBlue.withAlphaComponent(0.08), range: optionNS)
                    }
                }

            case .review(let rv):
                for (i, option) in rv.options.enumerated() {
                    let optionNS = NSRange(option.range, in: text)
                    guard optionNS.location + optionNS.length <= attributed.length else { continue }
                    let optionWrapper = InteractiveElementWrapper(element, optionIndex: i)
                    attributed.addAttribute(.interactiveElement, value: optionWrapper, range: optionNS)
                    attributed.addAttribute(.toolTip, value: "Click to set review: \(option.status.rawValue)", range: optionNS)
                    let statusColor = Self.reviewStatusColor(option.status)
                    if option.isSelected {
                        attributed.addAttribute(.backgroundColor, value: statusColor.withAlphaComponent(0.15), range: optionNS)
                        attributed.addAttribute(.foregroundColor, value: statusColor, range: optionNS)
                    }
                }

            case .fillIn(let fi):
                // Native text field appearance: glass-like background, solid underline, hidden delimiters
                attributed.addAttribute(.interactiveElement, value: wrapper, range: nsRange)
                attributed.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor.withAlphaComponent(0.25), range: nsRange)
                attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
                attributed.addAttribute(.underlineColor, value: NSColor.separatorColor, range: nsRange)
                if fi.value == nil {
                    // Unfilled: italic placeholder in the inner content
                    let innerStart = nsRange.location + 2
                    let innerLength = nsRange.length - 4
                    if innerLength > 0 && innerStart + innerLength <= attributed.length {
                        let innerRange = NSRange(location: innerStart, length: innerLength)
                        let regularFont = MarkdownHighlighter.resolveFont(family: nil, size: baseFont.pointSize, weight: .regular)
                        let italicDescriptor = regularFont.fontDescriptor.withSymbolicTraits(.italic)
                        let italicFont = NSFont(descriptor: italicDescriptor, size: baseFont.pointSize) ?? regularFont
                        attributed.addAttribute(.font, value: italicFont, range: innerRange)
                        attributed.addAttribute(.foregroundColor, value: NSColor.placeholderTextColor, range: innerRange)
                    }
                } else {
                    attributed.addAttribute(.foregroundColor, value: theme.foreground, range: nsRange)
                }
                let tooltip: String = switch fi.type {
                case .text: fi.value != nil ? "Click to edit: \(fi.hint)" : "Click to fill in: \(fi.hint)"
                case .file: "Click to choose a file"
                case .folder: "Click to choose a folder"
                case .date: "Click to pick a date"
                }
                attributed.addAttribute(.toolTip, value: tooltip, range: nsRange)

            case .feedback(let fb):
                attributed.addAttribute(.interactiveElement, value: wrapper, range: nsRange)
                attributed.addAttribute(.backgroundColor, value: NSColor.systemPurple.withAlphaComponent(0.08), range: nsRange)
                if fb.existingText != nil {
                    attributed.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: nsRange)
                    attributed.addAttribute(.toolTip, value: "Click to edit feedback", range: nsRange)
                } else {
                    attributed.addAttribute(.foregroundColor, value: NSColor.systemPurple.withAlphaComponent(0.5), range: nsRange)
                    let regularFont = MarkdownHighlighter.resolveFont(family: nil, size: baseFont.pointSize, weight: .regular)
                    let italicDescriptor = regularFont.fontDescriptor.withSymbolicTraits(.italic)
                    let italicFont = NSFont(descriptor: italicDescriptor, size: baseFont.pointSize) ?? regularFont
                    attributed.addAttribute(.font, value: italicFont, range: nsRange)
                    attributed.addAttribute(.toolTip, value: "Click to leave feedback", range: nsRange)
                }

            case .suggestion(let s):
                attributed.addAttribute(.interactiveElement, value: wrapper, range: nsRange)
                let (color, tooltip, decoration): (NSColor, String, CriticDecoration) = switch s.type {
                case .addition:
                    (.systemGreen, "Suggested addition — click to review", .none)
                case .deletion:
                    (.systemRed, "Suggested deletion — click to review", .strikethrough)
                case .substitution:
                    (.systemOrange, "Suggested change — click to review", .none)
                case .highlight:
                    (.systemYellow, "Highlighted — click to review", .none)
                }
                attributed.addAttribute(.foregroundColor, value: color, range: nsRange)
                attributed.addAttribute(.backgroundColor, value: color.withAlphaComponent(0.10), range: nsRange)
                if decoration == .strikethrough {
                    attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
                    attributed.addAttribute(.strikethroughColor, value: color.withAlphaComponent(0.6), range: nsRange)
                }
                attributed.addAttribute(.toolTip, value: tooltip, range: nsRange)
                Self.dimCriticMarkupDelimiters(in: attributed, range: nsRange, text: text)

            case .status(let st):
                let labelNS = NSRange(st.labelRange, in: text)
                if labelNS.location + labelNS.length <= attributed.length {
                    attributed.addAttribute(.interactiveElement, value: wrapper, range: labelNS)
                    let isTerminal = st.nextStates.isEmpty
                    let badgeColor: NSColor = isTerminal ? .systemGreen : .systemIndigo
                    attributed.addAttribute(.backgroundColor, value: badgeColor.withAlphaComponent(0.15), range: labelNS)
                    attributed.addAttribute(.foregroundColor, value: badgeColor, range: labelNS)
                    let tooltip = isTerminal ? "Status complete" : "Click to advance status"
                    attributed.addAttribute(.toolTip, value: tooltip, range: labelNS)
                }
                let commentNS = NSRange(st.commentRange, in: text)
                if commentNS.location + commentNS.length <= attributed.length {
                    attributed.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: commentNS)
                }

            case .confidence(let c):
                attributed.addAttribute(.interactiveElement, value: wrapper, range: nsRange)
                let (color, tooltip): (NSColor, String) = switch c.level {
                case .high: (.systemGreen, "AI is confident — click to confirm")
                case .medium: (.systemYellow, "AI confidence: medium")
                case .low: (.systemRed, "AI is uncertain — click to challenge")
                case .confirmed: (.systemBlue, "Confirmed")
                }
                attributed.addAttribute(.backgroundColor, value: color.withAlphaComponent(0.15), range: nsRange)
                attributed.addAttribute(.toolTip, value: tooltip, range: nsRange)

            case .conditional, .collapsible:
                attributed.addAttribute(.interactiveElement, value: wrapper, range: nsRange)
            }
        }

        // Post-pass: replace markdown brackets with native macOS control indicators.
        // SF Symbol checkboxes, radio buttons, dropdown chevrons, hidden field delimiters.
        replaceWithNativeIndicators(attributed, elements: elements, text: text)
    }

    /// Replaces "x"/"X" check marks with "✓" glyph for checked/selected items (display only).
    /// Processes in reverse order so character replacements don't shift earlier ranges.
    private func replaceCheckGlyphs(_ attributed: NSMutableAttributedString, elements: [InteractiveElement], text: String) {
        for element in elements.reversed() {
            switch element {
            case .checkbox(let cb) where cb.isChecked:
                let checkNS = NSRange(cb.checkRange, in: text)
                if checkNS.location + checkNS.length <= attributed.length {
                    let checkAttrs = attributed.attributes(at: checkNS.location, effectiveRange: nil)
                    attributed.replaceCharacters(in: checkNS, with: NSAttributedString(string: "✓", attributes: checkAttrs))
                }
            case .choice(let ch):
                for option in ch.options.reversed() where option.isSelected {
                    let checkNS = NSRange(option.checkRange, in: text)
                    if checkNS.location + checkNS.length <= attributed.length {
                        let checkAttrs = attributed.attributes(at: checkNS.location, effectiveRange: nil)
                        attributed.replaceCharacters(in: checkNS, with: NSAttributedString(string: "✓", attributes: checkAttrs))
                    }
                }
            case .review(let rv):
                for option in rv.options.reversed() where option.isSelected {
                    let checkNS = NSRange(option.checkRange, in: text)
                    if checkNS.location + checkNS.length <= attributed.length {
                        let checkAttrs = attributed.attributes(at: checkNS.location, effectiveRange: nil)
                        attributed.replaceCharacters(in: checkNS, with: NSAttributedString(string: "✓", attributes: checkAttrs))
                    }
                }
            default:
                break
            }
        }
    }

    // MARK: - Native Control Indicators (Enhanced Mode)

    /// Replaces markdown brackets with native macOS control indicators (SF Symbols).
    /// `[x]`/`[ ]` → native checkbox/radio images. Status labels get dropdown chevrons.
    /// Fill-in delimiters `[[`/`]]` become invisible to expose the field content.
    /// Processes in reverse order so character replacements don't shift earlier ranges.
    private func replaceWithNativeIndicators(_ attributed: NSMutableAttributedString, elements: [InteractiveElement], text: String) {
        let fontSize = baseFont.pointSize

        for element in elements.reversed() {
            switch element {
            case .checkbox(let cb):
                let symbol = cb.isChecked ? "checkmark.square.fill" : "square"
                let color: NSColor = cb.isChecked ? .systemGreen : .tertiaryLabelColor
                replaceBracketArea(checkRange: cb.checkRange, in: attributed, text: text,
                                   symbol: symbol, color: color, fontSize: fontSize)

            case .choice(let ch):
                for option in ch.options.reversed() {
                    let symbol = option.isSelected ? "circle.inset.filled" : "circle"
                    let color: NSColor = option.isSelected ? .systemBlue : .tertiaryLabelColor
                    replaceBracketArea(checkRange: option.checkRange, in: attributed, text: text,
                                       symbol: symbol, color: color, fontSize: fontSize)
                }

            case .review(let rv):
                for option in rv.options.reversed() {
                    let statusColor = Self.reviewStatusColor(option.status)
                    let symbol = option.isSelected ? "circle.inset.filled" : "circle"
                    let color: NSColor = option.isSelected ? statusColor : .tertiaryLabelColor
                    replaceBracketArea(checkRange: option.checkRange, in: attributed, text: text,
                                       symbol: symbol, color: color, fontSize: fontSize)
                }

            case .status(let st) where !st.nextStates.isEmpty:
                // Append dropdown chevron to the status label (looks like NSPopUpButton)
                let labelNS = NSRange(st.labelRange, in: text)
                guard labelNS.location + labelNS.length <= attributed.length else { continue }
                let chevron = makeSFSymbolAttachment("chevron.up.chevron.down",
                                                     color: .secondaryLabelColor, size: fontSize * 0.55)
                let spacedChevron = NSMutableAttributedString(string: " ")
                spacedChevron.append(chevron)
                // Preserve interactive attributes on the chevron
                let attrs = attributed.attributes(at: labelNS.location, effectiveRange: nil)
                spacedChevron.addAttributes(attrs, range: NSRange(location: 0, length: spacedChevron.length))
                attributed.insert(spacedChevron, at: labelNS.location + labelNS.length)

            case .fillIn:
                // Hide the [[ and ]] delimiters — the field background makes the boundary visible
                let fullNS = NSRange(element.range, in: text)
                guard fullNS.length >= 4, fullNS.location + fullNS.length <= attributed.length else { continue }
                let openRange = NSRange(location: fullNS.location, length: 2)
                let closeRange = NSRange(location: fullNS.location + fullNS.length - 2, length: 2)
                attributed.addAttribute(.foregroundColor, value: NSColor.clear, range: openRange)
                attributed.addAttribute(.foregroundColor, value: NSColor.clear, range: closeRange)

            default:
                break
            }
        }
    }

    /// Replaces a `[x]`/`[ ]` bracket area with an SF Symbol attachment (checkbox or radio image).
    private func replaceBracketArea(checkRange: Range<String.Index>, in attributed: NSMutableAttributedString,
                                    text: String, symbol: String, color: NSColor, fontSize: CGFloat) {
        let checkNS = NSRange(checkRange, in: text)
        // Bracket area: `[` before check char, `]` after → 3 characters total
        guard checkNS.location > 0, checkNS.location + checkNS.length + 1 <= attributed.length else { return }
        let bracketRange = NSRange(location: checkNS.location - 1, length: checkNS.length + 2)

        // Preserve existing attributes (interactive element, tooltip, etc.)
        let existingAttrs = attributed.attributes(at: bracketRange.location, effectiveRange: nil)
        let symbolStr = makeSFSymbolAttachment(symbol, color: color, size: fontSize)
        let mutable = NSMutableAttributedString(attributedString: symbolStr)
        mutable.addAttributes(existingAttrs, range: NSRange(location: 0, length: mutable.length))
        attributed.replaceCharacters(in: bracketRange, with: mutable)
    }

    /// Creates an NSAttributedString containing a colored SF Symbol as an inline text attachment.
    private func makeSFSymbolAttachment(_ name: String, color: NSColor, size: CGFloat) -> NSAttributedString {
        let sizeConfig = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        let colorConfig = NSImage.SymbolConfiguration(paletteColors: [color])
        let config = sizeConfig.applying(colorConfig)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else {
            return NSAttributedString(string: "•")
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        return NSAttributedString(attachment: attachment)
    }

    /// Annotates section headings with progress bars based on interactive element completion.
    /// Progress bars are rendered-only — not written back to the source markdown.
    func annotateProgressBars(_ attributed: NSMutableAttributedString, structure: DocumentStructure, text: String) {
        for section in structure.sections {
            annotateSectionProgress(section, attributed: attributed, text: text)
        }
    }

    private func annotateSectionProgress(_ section: Section, attributed: NSMutableAttributedString, text: String) {
        if let progress = section.progress {
            // Find the end of the heading line to insert progress text
            let headingNS = NSRange(section.range, in: text)
            guard headingNS.location + headingNS.length <= attributed.length else { return }

            // Find the first newline in the section range to locate end of heading
            let headingText = text[section.range]
            if let newlineIndex = headingText.firstIndex(of: "\n") {
                let insertPosition = NSRange(newlineIndex..<newlineIndex, in: text).location

                let filled = Int(progress.completed)
                let total = Int(progress.total)
                let pct = total > 0 ? Int(Double(filled) / Double(total) * 100) : 0

                // Build progress bar: ████░░ 60% (3/5)
                let barLength = 6
                let filledCount = total > 0 ? Int(round(Double(filled) / Double(total) * Double(barLength))) : 0
                let emptyCount = barLength - filledCount
                let bar = String(repeating: "█", count: filledCount) + String(repeating: "░", count: emptyCount)
                let progressText = "  \(bar) \(pct)% (\(filled)/\(total))"

                let progressAttr = NSMutableAttributedString(string: progressText)
                let progressRange = NSRange(location: 0, length: progressAttr.length)
                let progressColor: NSColor = pct == 100 ? .systemGreen : .secondaryLabelColor
                progressAttr.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.75, weight: .regular), range: progressRange)
                progressAttr.addAttribute(.foregroundColor, value: progressColor, range: progressRange)

                attributed.insert(progressAttr, at: insertPosition)
            }
        }

        // Recurse into children (process in reverse order since insertions shift positions)
        for child in section.children.reversed() {
            annotateSectionProgress(child, attributed: attributed, text: text)
        }
    }

    /// Plain mode: adds only click targets and tooltips without visual enhancements.
    private func annotatePlainClickTargets(_ attributed: NSMutableAttributedString, elements: [InteractiveElement], text: String) {
        for element in elements {
            let swiftRange = element.range
            guard let nsRange = Optional(NSRange(swiftRange, in: text)) else { continue }
            guard nsRange.location + nsRange.length <= attributed.length else { continue }

            let wrapper = InteractiveElementWrapper(element)

            switch element {
            case .checkbox(let cb):
                attributed.addAttribute(.interactiveElement, value: wrapper, range: nsRange)
                attributed.addAttribute(.toolTip, value: cb.isChecked ? "Click to uncheck" : "Click to mark as complete", range: nsRange)

            case .choice(let ch):
                for (i, option) in ch.options.enumerated() {
                    let optionNS = NSRange(option.range, in: text)
                    guard optionNS.location + optionNS.length <= attributed.length else { continue }
                    attributed.addAttribute(.interactiveElement, value: InteractiveElementWrapper(element, optionIndex: i), range: optionNS)
                    attributed.addAttribute(.toolTip, value: "Click to select this option", range: optionNS)
                }

            case .review(let rv):
                for (i, option) in rv.options.enumerated() {
                    let optionNS = NSRange(option.range, in: text)
                    guard optionNS.location + optionNS.length <= attributed.length else { continue }
                    attributed.addAttribute(.interactiveElement, value: InteractiveElementWrapper(element, optionIndex: i), range: optionNS)
                    attributed.addAttribute(.toolTip, value: "Click to set review: \(option.status.rawValue)", range: optionNS)
                }

            case .fillIn(let fi):
                attributed.addAttribute(.interactiveElement, value: wrapper, range: nsRange)
                let tip: String = switch fi.type {
                case .text: "Click to fill in: \(fi.hint)"
                case .file: "Click to choose a file"
                case .folder: "Click to choose a folder"
                case .date: "Click to pick a date"
                }
                attributed.addAttribute(.toolTip, value: tip, range: nsRange)

            case .feedback(let fb):
                attributed.addAttribute(.interactiveElement, value: wrapper, range: nsRange)
                attributed.addAttribute(.toolTip, value: fb.existingText != nil ? "Click to edit feedback" : "Click to leave feedback", range: nsRange)

            case .suggestion(let s):
                attributed.addAttribute(.interactiveElement, value: wrapper, range: nsRange)
                let tip: String = switch s.type {
                case .addition: "Suggested addition — click to review"
                case .deletion: "Suggested deletion — click to review"
                case .substitution: "Suggested change — click to review"
                case .highlight: "Highlighted — click to review"
                }
                attributed.addAttribute(.toolTip, value: tip, range: nsRange)

            case .status(let st):
                let labelNS = NSRange(st.labelRange, in: text)
                if labelNS.location + labelNS.length <= attributed.length {
                    attributed.addAttribute(.interactiveElement, value: wrapper, range: labelNS)
                    attributed.addAttribute(.toolTip, value: st.nextStates.isEmpty ? "Status complete" : "Click to advance status", range: labelNS)
                }

            case .confidence(let c):
                attributed.addAttribute(.interactiveElement, value: wrapper, range: nsRange)
                let tip: String = switch c.level {
                case .high: "AI is confident — click to confirm"
                case .medium: "AI confidence: medium"
                case .low: "AI is uncertain — click to challenge"
                case .confirmed: "Confirmed"
                }
                attributed.addAttribute(.toolTip, value: tip, range: nsRange)

            case .conditional, .collapsible:
                attributed.addAttribute(.interactiveElement, value: wrapper, range: nsRange)
            }
        }
    }

    /// CriticMarkup decoration type for unified styling
    private enum CriticDecoration { case none, strikethrough }

    /// Dims CriticMarkup delimiters to make the content stand out over the syntax.
    private static func dimCriticMarkupDelimiters(in attributed: NSMutableAttributedString, range: NSRange, text: String) {
        let delimiterColor = NSColor.tertiaryLabelColor

        // Patterns: {++...++}  {--...--}  {~~...~>...~~}  {==...==}{>>...<<}
        let delimiterPatterns = [
            #"\{\+\+"#, #"\+\+\}"#,
            #"\{--"#, #"--\}"#,
            #"\{~~"#, #"~>"#, #"~~\}"#,
            #"\{=="#, #"==\}"#, #"\{>>"#, #"<<\}"#,
        ]

        for pattern in delimiterPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, range: range) {
                attributed.addAttribute(.foregroundColor, value: delimiterColor, range: match.range)
            }
        }
    }

    /// Maps review statuses to semantic colors for visual differentiation.
    private static func reviewStatusColor(_ status: ReviewStatus) -> NSColor {
        switch status {
        case .approved, .pass: return .systemGreen
        case .fail: return .systemRed
        case .passWithNotes: return .systemYellow
        case .blocked: return .systemOrange
        case .notApplicable: return .systemGray
        }
    }

    private func applyRule(_ rule: HighlightRule, to str: NSMutableAttributedString, match: NSTextCheckingResult) {
        switch rule {
        case .heading:
            let hashCount = match.range(at: 1).length
            let m = headingScale.multipliers
            let color: NSColor
            let size: CGFloat
            switch hashCount {
            case 1: color = theme.heading1; size = baseFont.pointSize * m.h1
            case 2: color = theme.heading2; size = baseFont.pointSize * m.h2
            default: color = theme.heading3; size = baseFont.pointSize * m.h3
            }
            // Use the same font family as base, just scaled and bold
            let headingFont = baseFont.withSize(size).withWeight(.bold)
            str.addAttributes([
                .foregroundColor: color,
                .font: headingFont
            ], range: match.range)

        case .codeBlock:
            // Code blocks always use monospaced regardless of base font family
            str.addAttributes([
                .foregroundColor: theme.code,
                .backgroundColor: theme.codeBackground,
                .font: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
            ], range: match.range)

        case .inlineCode:
            str.addAttributes([
                .foregroundColor: theme.code,
                .backgroundColor: theme.codeBackground
            ], range: match.range)

        case .bold:
            str.addAttribute(.font, value: baseFont.withWeight(.bold), range: match.range)

        case .italic:
            let italicFont = baseFont.withTraits(.italicFontMask)
            str.addAttribute(.font, value: italicFont, range: match.range)

        case .link:
            str.addAttribute(.foregroundColor, value: theme.link, range: match.range)
            // Make the link text (group 1) clickable using the URL (group 2)
            if match.numberOfRanges > 2 {
                let textRange = match.range(at: 1)
                let urlRange = match.range(at: 2)
                if textRange.location != NSNotFound && urlRange.location != NSNotFound,
                   let swiftRange = Range(urlRange, in: str.string) {
                    let urlString = String(str.string[swiftRange])
                    if let url = URL(string: urlString) {
                        str.addAttribute(.link, value: url, range: textRange)
                    }
                }
            }

        case .bareLink:
            str.addAttribute(.foregroundColor, value: theme.link, range: match.range)
            if let swiftRange = Range(match.range, in: str.string) {
                let urlString = String(str.string[swiftRange])
                if let url = URL(string: urlString) {
                    str.addAttribute(.link, value: url, range: match.range)
                }
            }

        case .listMarker:
            str.addAttribute(.foregroundColor, value: theme.listMarker, range: match.range)

        case .blockquote:
            str.addAttribute(.foregroundColor, value: theme.blockquote, range: match.range)

        case .separator:
            str.addAttribute(.foregroundColor, value: theme.separator, range: match.range)
        }
    }
}

// MARK: - Debouncing Extension (MainActor)

/// Debouncing wrapper - only this part needs MainActor isolation
@MainActor
final class DebouncedHighlighter {

    let highlighter: MarkdownHighlighter  // Changed from private to internal
    private var debounceTask: Task<Void, Never>?
    private let debounceDelay: Duration

    init(highlighter: MarkdownHighlighter = MarkdownHighlighter(), debounceDelay: Duration = .milliseconds(100)) {
        self.highlighter = highlighter
        self.debounceDelay = debounceDelay
    }

    deinit {
        debounceTask?.cancel()
    }

    /// Debounced highlighting - call this from text change handlers
    func highlightDebounced(_ text: String, completion: @escaping @MainActor (NSAttributedString) -> Void) {
        debounceTask?.cancel()

        let delay = debounceDelay
        let highlighterRef = highlighter

        debounceTask = Task { @MainActor [weak self] in
            guard self != nil else { return }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }

            let result = highlighterRef.highlight(text)
            completion(result)
        }
    }
}

// MARK: - Font Extension

extension NSFont {
    func withTraits(_ traits: NSFontTraitMask) -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(NSFontDescriptor.SymbolicTraits(rawValue: UInt32(traits.rawValue)))
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }

    func withSize(_ size: CGFloat) -> NSFont {
        NSFont(descriptor: fontDescriptor, size: size) ?? self
    }

    func withWeight(_ weight: NSFont.Weight) -> NSFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [NSFontDescriptor.TraitKey.weight: weight]
        ])
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}

// MARK: - NSColor Hex Extension

extension NSColor {
    /// Creates an NSColor from a hex string (e.g., "#FF5733" or "FF5733")
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b: UInt64
        switch hex.count {
        case 6: // RGB
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8: // ARGB (ignore alpha for now)
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            return nil
        }

        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: 1.0
        )
    }
}
