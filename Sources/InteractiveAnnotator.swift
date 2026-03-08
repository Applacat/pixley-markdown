import AppKit
import aimdRenderer

/// Annotates an already-highlighted attributed string with interactive element styling.
///
/// Separated from MarkdownHighlighter because it addresses a different concern:
/// the highlighter knows about markdown syntax (headings, bold, code blocks),
/// while the annotator knows about interactive element semantics (checkboxes,
/// choices, reviews, fill-ins, status indicators, etc.).
///
/// Font dependency is injected via `baseFont` — the annotator does not duplicate
/// MarkdownHighlighter's font resolution logic.
final class InteractiveAnnotator {

    /// The base font used for sizing calculations (point size, italic variants)
    let baseFont: NSFont

    /// The theme foreground color for filled elements
    let foregroundColor: NSColor

    // MARK: - Initialization

    /// Creates an annotator with injected font and color dependencies.
    ///
    /// - Parameters:
    ///   - baseFont: The base font from the highlighter (used for point size and italic derivation)
    ///   - foregroundColor: The theme foreground color (used for filled fill-in elements)
    init(baseFont: NSFont, foregroundColor: NSColor) {
        self.baseFont = baseFont
        self.foregroundColor = foregroundColor
    }

    // MARK: - Interactive Element Annotation

    /// Annotates an already-highlighted attributed string with interactive element styling.
    /// Adds custom attributes, visual affordances, and tooltips for clickable elements.
    /// Click targets span full element ranges (not just bracket characters) for discoverability.
    ///
    /// - Parameters:
    ///   - attributed: The mutable attributed string to annotate (already syntax-highlighted)
    ///   - elements: Detected interactive elements with their ranges
    ///   - text: The original source text (for range conversion)
    ///   - enhanced: When true, applies full visual affordances (pills, backgrounds, tooltips).
    ///               When false, only adds click targets and cursor attributes (plain mode).
    func annotateInteractiveElements(_ attributed: NSMutableAttributedString, elements: [InteractiveElement], text: String, enhanced: Bool = true) {
        // Plain mode: just add click targets and tooltips, no visual styling
        if !enhanced {
            annotatePlainClickTargets(attributed, elements: elements, text: text)
            // Still replace x with check glyph for checked items (readability, not styling)
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
                // Dim checked items to show completion (no strikethrough -- native feel)
                if cb.isChecked {
                    attributed.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: nsRange)
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
                        let regularFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
                        let italicDescriptor = regularFont.fontDescriptor.withSymbolicTraits(.italic)
                        let italicFont = NSFont(descriptor: italicDescriptor, size: baseFont.pointSize) ?? regularFont
                        attributed.addAttribute(.font, value: italicFont, range: innerRange)
                        attributed.addAttribute(.foregroundColor, value: NSColor.placeholderTextColor, range: innerRange)
                    }
                } else {
                    attributed.addAttribute(.foregroundColor, value: foregroundColor, range: nsRange)
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
                    let regularFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
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

    // MARK: - Check Glyph Replacement

    /// Replaces "x"/"X" check marks with a check glyph for checked/selected items (display only).
    /// Processes in reverse order so character replacements don't shift earlier ranges.
    func replaceCheckGlyphs(_ attributed: NSMutableAttributedString, elements: [InteractiveElement], text: String) {
        for element in elements.reversed() {
            switch element {
            case .checkbox(let cb) where cb.isChecked:
                let checkNS = NSRange(cb.checkRange, in: text)
                if checkNS.location + checkNS.length <= attributed.length {
                    let checkAttrs = attributed.attributes(at: checkNS.location, effectiveRange: nil)
                    attributed.replaceCharacters(in: checkNS, with: NSAttributedString(string: "\u{2713}", attributes: checkAttrs))
                }
            case .choice(let ch):
                for option in ch.options.reversed() where option.isSelected {
                    let checkNS = NSRange(option.checkRange, in: text)
                    if checkNS.location + checkNS.length <= attributed.length {
                        let checkAttrs = attributed.attributes(at: checkNS.location, effectiveRange: nil)
                        attributed.replaceCharacters(in: checkNS, with: NSAttributedString(string: "\u{2713}", attributes: checkAttrs))
                    }
                }
            case .review(let rv):
                for option in rv.options.reversed() where option.isSelected {
                    let checkNS = NSRange(option.checkRange, in: text)
                    if checkNS.location + checkNS.length <= attributed.length {
                        let checkAttrs = attributed.attributes(at: checkNS.location, effectiveRange: nil)
                        attributed.replaceCharacters(in: checkNS, with: NSAttributedString(string: "\u{2713}", attributes: checkAttrs))
                    }
                }
            default:
                break
            }
        }
    }

    // MARK: - Native Control Indicators (Enhanced Mode)

    /// Replaces markdown brackets with native macOS control indicators (SF Symbols).
    /// `[x]`/`[ ]` -> native checkbox/radio images. Status labels get dropdown chevrons.
    /// Fill-in delimiters `[[`/`]]` become invisible to expose the field content.
    /// Processes in reverse order so character replacements don't shift earlier ranges.
    private func replaceWithNativeIndicators(_ attributed: NSMutableAttributedString, elements: [InteractiveElement], text: String) {
        let fontSize = baseFont.pointSize

        for element in elements.reversed() {
            switch element {
            case .checkbox(let cb):
                let symbol = cb.isChecked ? "checkmark.square.fill" : "square"
                let color: NSColor = cb.isChecked ? .controlAccentColor : .tertiaryLabelColor
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
                // Hide the [[ and ]] delimiters -- the field background makes the boundary visible
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
        // Bracket area: `[` before check char, `]` after -> 3 characters total
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
            return NSAttributedString(string: "\u{2022}")
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        return NSAttributedString(attachment: attachment)
    }

    // MARK: - Progress Bars

    /// Annotates section headings with progress bars based on interactive element completion.
    /// Progress bars are rendered-only -- not written back to the source markdown.
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

                // Build progress bar: filled/empty blocks + percentage
                let barLength = 6
                let filledCount = total > 0 ? Int(round(Double(filled) / Double(total) * Double(barLength))) : 0
                let emptyCount = barLength - filledCount
                let bar = String(repeating: "\u{2588}", count: filledCount) + String(repeating: "\u{2591}", count: emptyCount)
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

    // MARK: - Plain Mode Annotation

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

    // MARK: - CriticMarkup Helpers

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
    static func reviewStatusColor(_ status: ReviewStatus) -> NSColor {
        switch status {
        case .approved, .pass: return .systemGreen
        case .fail: return .systemRed
        case .passWithNotes: return .systemYellow
        case .blocked: return .systemOrange
        case .notApplicable: return .systemGray
        }
    }
}
