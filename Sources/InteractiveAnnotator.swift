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

    /// Background color for CriticMarkup comment highlights
    let commentHighlightColor: NSColor?

    // MARK: - Initialization

    /// Creates an annotator with injected font and color dependencies.
    ///
    /// - Parameters:
    ///   - baseFont: The base font from the highlighter (used for point size and italic derivation)
    ///   - foregroundColor: The theme foreground color (used for filled fill-in elements)
    ///   - commentHighlightColor: Theme-specific background for comment highlights (nil falls back to system yellow)
    init(baseFont: NSFont, foregroundColor: NSColor, commentHighlightColor: NSColor? = nil) {
        self.baseFont = baseFont
        self.foregroundColor = foregroundColor
        self.commentHighlightColor = commentHighlightColor
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
        if !enhanced {
            annotatePlainClickTargets(attributed, elements: elements, text: text)
            replaceCheckGlyphs(attributed, elements: elements, text: text)
            return
        }

        for element in elements {
            guard let nsRange = validNSRange(for: element, in: text, length: attributed.length) else { continue }
            let wrapper = InteractiveElementWrapper(element)

            switch element {
            case .checkbox(let cb):
                annotateEnhancedCheckbox(attributed, cb: cb, wrapper: wrapper, range: nsRange)
            case .choice(let ch):
                annotateEnhancedChoice(attributed, ch: ch, element: element, text: text)
            case .review(let rv):
                annotateEnhancedReview(attributed, rv: rv, element: element, text: text)
            case .fillIn(let fi):
                annotateEnhancedFillIn(attributed, fi: fi, wrapper: wrapper, range: nsRange)
            case .feedback(let fb):
                annotateEnhancedFeedback(attributed, fb: fb, wrapper: wrapper, range: nsRange)
            case .suggestion(let s):
                annotateEnhancedSuggestion(attributed, s: s, wrapper: wrapper, range: nsRange, swiftRange: element.range, text: text)
            case .status(let st):
                annotateEnhancedStatus(attributed, st: st, wrapper: wrapper, text: text)
            case .confidence(let c):
                annotateEnhancedConfidence(attributed, c: c, wrapper: wrapper, range: nsRange)
            case .conditional, .collapsible:
                attributed.addAttribute(.interactiveElement, value: wrapper, range: nsRange)
            case .auditableCheckbox(let ac):
                annotateEnhancedAuditableCheckbox(attributed, ac: ac, wrapper: wrapper, range: nsRange)
            case .slider, .stepper, .toggle, .colorPicker:
                annotateEnhancedControl(attributed, wrapper: wrapper, range: nsRange)
            }
        }

        replaceWithNativeIndicators(attributed, elements: elements, text: text)
    }

    // MARK: - Range Validation

    private func validNSRange(for element: InteractiveElement, in text: String, length: Int) -> NSRange? {
        let nsRange = NSRange(element.range, in: text)
        guard nsRange.location + nsRange.length <= length else { return nil }
        return nsRange
    }

    // MARK: - Enhanced Mode Per-Element Annotation

    private func annotateEnhancedCheckbox(
        _ attributed: NSMutableAttributedString, cb: CheckboxElement,
        wrapper: InteractiveElementWrapper, range: NSRange
    ) {
        attributed.addAttribute(.interactiveElement, value: wrapper, range: range)
        let tooltip = cb.isChecked ? "Click to uncheck" : "Click to mark as complete"
        attributed.addAttribute(.toolTip, value: tooltip, range: range)
        if cb.isChecked {
            attributed.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
        }
    }

    private func annotateEnhancedChoice(_ attributed: NSMutableAttributedString, ch: ChoiceElement, element: InteractiveElement, text: String) {
        for (i, option) in ch.options.enumerated() {
            let optionNS = NSRange(option.range, in: text)
            guard optionNS.location + optionNS.length <= attributed.length else { continue }
            attributed.addAttribute(.interactiveElement, value: InteractiveElementWrapper(element, optionIndex: i), range: optionNS)
            attributed.addAttribute(.toolTip, value: "Click to select this option", range: optionNS)
            if option.isSelected {
                attributed.addAttribute(.backgroundColor, value: NSColor.systemBlue.withAlphaComponent(0.08), range: optionNS)
            }
        }
    }

    private func annotateEnhancedReview(_ attributed: NSMutableAttributedString, rv: ReviewElement, element: InteractiveElement, text: String) {
        for (i, option) in rv.options.enumerated() {
            let optionNS = NSRange(option.range, in: text)
            guard optionNS.location + optionNS.length <= attributed.length else { continue }
            attributed.addAttribute(.interactiveElement, value: InteractiveElementWrapper(element, optionIndex: i), range: optionNS)
            attributed.addAttribute(.toolTip, value: "Click to set review: \(option.status.rawValue)", range: optionNS)
            let statusColor = Self.reviewStatusColor(option.status)
            if option.isSelected {
                attributed.addAttribute(.backgroundColor, value: statusColor.withAlphaComponent(0.15), range: optionNS)
                attributed.addAttribute(.foregroundColor, value: statusColor, range: optionNS)
            }
        }
    }

    private func annotateEnhancedFillIn(
        _ attributed: NSMutableAttributedString, fi: FillInElement,
        wrapper: InteractiveElementWrapper, range: NSRange
    ) {
        attributed.addAttribute(.interactiveElement, value: wrapper, range: range)
        attributed.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor.withAlphaComponent(0.25), range: range)
        attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        attributed.addAttribute(.underlineColor, value: NSColor.separatorColor, range: range)
        if fi.value == nil {
            let innerStart = range.location + 2
            let innerLength = range.length - 4
            if innerLength > 0 && innerStart + innerLength <= attributed.length {
                let innerRange = NSRange(location: innerStart, length: innerLength)
                let italicFont = makeItalicFont()
                attributed.addAttribute(.font, value: italicFont, range: innerRange)
                attributed.addAttribute(.foregroundColor, value: NSColor.placeholderTextColor, range: innerRange)
            }
        } else {
            attributed.addAttribute(.foregroundColor, value: foregroundColor, range: range)
        }
        let tooltip: String = switch fi.type {
        case .text: fi.value != nil ? "Click to edit: \(fi.hint)" : "Click to fill in: \(fi.hint)"
        case .file: "Click to choose a file"
        case .folder: "Click to choose a folder"
        case .date: "Click to pick a date"
        }
        attributed.addAttribute(.toolTip, value: tooltip, range: range)
    }

    private func annotateEnhancedFeedback(
        _ attributed: NSMutableAttributedString, fb: FeedbackElement,
        wrapper: InteractiveElementWrapper, range: NSRange
    ) {
        attributed.addAttribute(.interactiveElement, value: wrapper, range: range)
        attributed.addAttribute(.backgroundColor, value: NSColor.systemPurple.withAlphaComponent(0.08), range: range)
        if fb.existingText != nil {
            attributed.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: range)
            attributed.addAttribute(.toolTip, value: "Click to edit feedback", range: range)
        } else {
            attributed.addAttribute(.foregroundColor, value: NSColor.systemPurple.withAlphaComponent(0.5), range: range)
            attributed.addAttribute(.font, value: makeItalicFont(), range: range)
            attributed.addAttribute(.toolTip, value: "Click to leave feedback", range: range)
        }
    }

    private func annotateEnhancedSuggestion(
        _ attributed: NSMutableAttributedString, s: SuggestionElement,
        wrapper: InteractiveElementWrapper, range: NSRange,
        swiftRange: Range<String.Index>, text: String
    ) {
        attributed.addAttribute(.interactiveElement, value: wrapper, range: range)
        let (color, tooltip, decoration): (NSColor, String, CriticDecoration) = switch s.type {
        case .addition:    (.systemGreen, "Suggested addition — click to review", .none)
        case .deletion:    (.systemRed, "Suggested deletion — click to review", .strikethrough)
        case .substitution: (.systemOrange, "Suggested change — click to review", .none)
        case .highlight:   (.systemYellow, s.comment != nil ? "Comment — click to read" : "Highlighted — click to add comment", .none)
        }
        if s.type == .highlight {
            let bgColor = commentHighlightColor ?? NSColor.systemYellow.withAlphaComponent(0.15)
            attributed.addAttribute(.backgroundColor, value: bgColor, range: range)
            hideHighlightComment(in: attributed, swiftRange: swiftRange, nsRange: range, text: text)
        } else {
            attributed.addAttribute(.foregroundColor, value: color, range: range)
            attributed.addAttribute(.backgroundColor, value: color.withAlphaComponent(0.10), range: range)
        }
        if decoration == .strikethrough {
            attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            attributed.addAttribute(.strikethroughColor, value: color.withAlphaComponent(0.6), range: range)
        }
        attributed.addAttribute(.toolTip, value: tooltip, range: range)
        Self.dimCriticMarkupDelimiters(in: attributed, range: range, text: text)
    }

    private func hideHighlightComment(in attributed: NSMutableAttributedString, swiftRange: Range<String.Index>, nsRange: NSRange, text: String) {
        let fullText = String(text[swiftRange])
        guard let commentStart = fullText.range(of: "==}{>>") else { return }
        let offset = fullText.distance(from: fullText.startIndex, to: commentStart.lowerBound) + 2
        let hideStart = text.index(swiftRange.lowerBound, offsetBy: offset)
        let hideNS = NSRange(hideStart..<swiftRange.upperBound, in: text)
        guard hideNS.location + hideNS.length <= attributed.length else { return }
        attributed.addAttribute(.foregroundColor, value: NSColor.clear, range: hideNS)
        attributed.addAttribute(.font, value: NSFont.systemFont(ofSize: 0.1), range: hideNS)
    }

    private func annotateEnhancedStatus(
        _ attributed: NSMutableAttributedString, st: StatusElement,
        wrapper: InteractiveElementWrapper, text: String
    ) {
        let labelNS = NSRange(st.labelRange, in: text)
        if labelNS.location + labelNS.length <= attributed.length {
            attributed.addAttribute(.interactiveElement, value: wrapper, range: labelNS)
            let isTerminal = st.nextStates.isEmpty
            let badgeColor: NSColor = isTerminal ? .systemGreen : .controlAccentColor
            attributed.addAttribute(.backgroundColor, value: badgeColor.withAlphaComponent(isTerminal ? 0.15 : 0.12), range: labelNS)
            attributed.addAttribute(.foregroundColor, value: isTerminal ? badgeColor : .labelColor, range: labelNS)
            attributed.addAttribute(.toolTip, value: isTerminal ? "Status complete" : "Click to change status", range: labelNS)
        }
        let commentNS = NSRange(st.commentRange, in: text)
        if commentNS.location + commentNS.length <= attributed.length {
            attributed.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: commentNS)
        }
    }

    private func annotateEnhancedConfidence(
        _ attributed: NSMutableAttributedString, c: ConfidenceElement,
        wrapper: InteractiveElementWrapper, range: NSRange
    ) {
        attributed.addAttribute(.interactiveElement, value: wrapper, range: range)
        let (color, tooltip): (NSColor, String) = switch c.level {
        case .high:      (.systemGreen, "AI is confident — click to confirm")
        case .medium:    (.systemYellow, "AI confidence: medium")
        case .low:       (.systemRed, "AI is uncertain — click to challenge")
        case .confirmed: (.systemBlue, "Confirmed")
        }
        attributed.addAttribute(.backgroundColor, value: color.withAlphaComponent(0.15), range: range)
        attributed.addAttribute(.toolTip, value: tooltip, range: range)
    }

    private func annotateEnhancedAuditableCheckbox(
        _ attributed: NSMutableAttributedString, ac: AuditableCheckboxElement,
        wrapper: InteractiveElementWrapper, range: NSRange
    ) {
        attributed.addAttribute(.interactiveElement, value: wrapper, range: range)
        let tooltip = ac.isChecked ? "Click to uncheck (auditable)" : "Click to mark as complete (will prompt for note)"
        attributed.addAttribute(.toolTip, value: tooltip, range: range)
        if ac.isChecked {
            attributed.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
        }
    }

    private func annotateEnhancedControl(_ attributed: NSMutableAttributedString, wrapper: InteractiveElementWrapper, range: NSRange) {
        attributed.addAttribute(.interactiveElement, value: wrapper, range: range)
        attributed.addAttribute(.toolTip, value: "Click to adjust", range: range)
        attributed.addAttribute(.backgroundColor, value: NSColor.controlAccentColor.withAlphaComponent(0.08), range: range)
    }

    private func makeItalicFont() -> NSFont {
        let regularFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
        let italicDescriptor = regularFont.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: italicDescriptor, size: baseFont.pointSize) ?? regularFont
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
                if cb.isChecked {
                    replaceBracketArea(checkRange: cb.checkRange, in: attributed, text: text,
                                       symbol: "checkmark.square.fill", color: .controlAccentColor, fontSize: fontSize,
                                       paletteColors: [.white, .controlAccentColor])
                } else {
                    replaceBracketArea(checkRange: cb.checkRange, in: attributed, text: text,
                                       symbol: "square", color: .tertiaryLabelColor, fontSize: fontSize)
                }

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
                // Append dropdown chevron to the status label
                let labelNS = NSRange(st.labelRange, in: text)
                guard labelNS.location + labelNS.length <= attributed.length else { continue }
                let chevron = makeSFSymbolAttachment("chevron.down",
                                                     color: .secondaryLabelColor, size: fontSize * 0.5)
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
                                    text: String, symbol: String, color: NSColor, fontSize: CGFloat, paletteColors: [NSColor]? = nil) {
        let checkNS = NSRange(checkRange, in: text)
        // Bracket area: `[` before check char, `]` after -> 3 characters total
        guard checkNS.location > 0, checkNS.location + checkNS.length + 1 <= attributed.length else { return }
        let bracketRange = NSRange(location: checkNS.location - 1, length: checkNS.length + 2)

        // Preserve existing attributes (interactive element, tooltip, etc.)
        let existingAttrs = attributed.attributes(at: bracketRange.location, effectiveRange: nil)
        let symbolStr = makeSFSymbolAttachment(symbol, color: color, size: fontSize, paletteColors: paletteColors)
        let mutable = NSMutableAttributedString(attributedString: symbolStr)
        mutable.addAttributes(existingAttrs, range: NSRange(location: 0, length: mutable.length))
        attributed.replaceCharacters(in: bracketRange, with: mutable)
    }

    /// Creates an NSAttributedString containing a colored SF Symbol as an inline text attachment.
    private func makeSFSymbolAttachment(_ name: String, color: NSColor, size: CGFloat, paletteColors: [NSColor]? = nil) -> NSAttributedString {
        let sizeConfig = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        let colorConfig = NSImage.SymbolConfiguration(paletteColors: paletteColors ?? [color])
        let config = sizeConfig.applying(colorConfig)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else {
            return NSAttributedString(string: "\u{2022}")
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        return NSAttributedString(attachment: attachment)
    }

    // MARK: - Plain Mode Annotation

    /// Plain mode: adds only click targets and tooltips without visual enhancements.
    private func annotatePlainClickTargets(_ attributed: NSMutableAttributedString, elements: [InteractiveElement], text: String) {
        for element in elements {
            guard let nsRange = validNSRange(for: element, in: text, length: attributed.length) else { continue }
            let wrapper = InteractiveElementWrapper(element)

            switch element {
            case .checkbox(let cb):
                addClickTarget(attributed, wrapper: wrapper, range: nsRange,
                               tooltip: cb.isChecked ? "Click to uncheck" : "Click to mark as complete")
            case .choice(let ch):
                addOptionClickTargets(attributed, options: ch.options, element: element, text: text, tooltip: "Click to select this option")
            case .review(let rv):
                addReviewClickTargets(attributed, options: rv.options, element: element, text: text)
            case .fillIn(let fi):
                addClickTarget(attributed, wrapper: wrapper, range: nsRange, tooltip: fillInTooltip(fi))
            case .feedback(let fb):
                addClickTarget(attributed, wrapper: wrapper, range: nsRange,
                               tooltip: fb.existingText != nil ? "Click to edit feedback" : "Click to leave feedback")
            case .suggestion(let s):
                addClickTarget(attributed, wrapper: wrapper, range: nsRange, tooltip: suggestionTooltip(s))
            case .status(let st):
                annotatePlainStatus(attributed, st: st, wrapper: wrapper, text: text)
            case .confidence(let c):
                addClickTarget(attributed, wrapper: wrapper, range: nsRange, tooltip: confidenceTooltip(c))
            case .conditional, .collapsible:
                attributed.addAttribute(.interactiveElement, value: wrapper, range: nsRange)
            case .auditableCheckbox(let ac):
                addClickTarget(attributed, wrapper: wrapper, range: nsRange,
                               tooltip: ac.isChecked ? "Click to uncheck (auditable)" : "Click to mark as complete (will prompt for note)")
            case .slider(let s):
                addClickTarget(attributed, wrapper: wrapper, range: nsRange,
                               tooltip: "Slider \(s.minValue)–\(s.maxValue) — switch to Enhanced mode to use")
            case .stepper:
                addClickTarget(attributed, wrapper: wrapper, range: nsRange, tooltip: "Stepper — switch to Enhanced mode to use")
            case .toggle:
                addClickTarget(attributed, wrapper: wrapper, range: nsRange, tooltip: "Toggle — switch to Enhanced mode to use")
            case .colorPicker:
                addClickTarget(attributed, wrapper: wrapper, range: nsRange, tooltip: "Color picker — switch to Enhanced mode to use")
            }
        }
    }

    // MARK: - Plain Mode Helpers

    private func addClickTarget(_ attributed: NSMutableAttributedString, wrapper: InteractiveElementWrapper, range: NSRange, tooltip: String) {
        attributed.addAttribute(.interactiveElement, value: wrapper, range: range)
        attributed.addAttribute(.toolTip, value: tooltip, range: range)
    }

    private func addOptionClickTargets(
        _ attributed: NSMutableAttributedString, options: [ChoiceOption],
        element: InteractiveElement, text: String, tooltip: String
    ) {
        for (i, option) in options.enumerated() {
            let optionNS = NSRange(option.range, in: text)
            guard optionNS.location + optionNS.length <= attributed.length else { continue }
            attributed.addAttribute(.interactiveElement, value: InteractiveElementWrapper(element, optionIndex: i), range: optionNS)
            attributed.addAttribute(.toolTip, value: tooltip, range: optionNS)
        }
    }

    private func addReviewClickTargets(_ attributed: NSMutableAttributedString, options: [ReviewOption], element: InteractiveElement, text: String) {
        for (i, option) in options.enumerated() {
            let optionNS = NSRange(option.range, in: text)
            guard optionNS.location + optionNS.length <= attributed.length else { continue }
            attributed.addAttribute(.interactiveElement, value: InteractiveElementWrapper(element, optionIndex: i), range: optionNS)
            attributed.addAttribute(.toolTip, value: "Click to set review: \(option.status.rawValue)", range: optionNS)
        }
    }

    private func annotatePlainStatus(_ attributed: NSMutableAttributedString, st: StatusElement, wrapper: InteractiveElementWrapper, text: String) {
        let labelNS = NSRange(st.labelRange, in: text)
        guard labelNS.location + labelNS.length <= attributed.length else { return }
        attributed.addAttribute(.interactiveElement, value: wrapper, range: labelNS)
        attributed.addAttribute(.toolTip, value: st.nextStates.isEmpty ? "Status complete" : "Click to advance status", range: labelNS)
    }

    private func fillInTooltip(_ fi: FillInElement) -> String {
        switch fi.type {
        case .text: "Click to fill in: \(fi.hint)"
        case .file: "Click to choose a file"
        case .folder: "Click to choose a folder"
        case .date: "Click to pick a date"
        }
    }

    private func suggestionTooltip(_ s: SuggestionElement) -> String {
        switch s.type {
        case .addition: "Suggested addition — click to review"
        case .deletion: "Suggested deletion — click to review"
        case .substitution: "Suggested change — click to review"
        case .highlight: "Highlighted — click to review"
        }
    }

    private func confidenceTooltip(_ c: ConfidenceElement) -> String {
        switch c.level {
        case .high: "AI is confident — click to confirm"
        case .medium: "AI confidence: medium"
        case .low: "AI is uncertain — click to challenge"
        case .confirmed: "Confirmed"
        }
    }

    // MARK: - CriticMarkup Helpers

    /// CriticMarkup decoration type for unified styling
    private enum CriticDecoration { case none, strikethrough }

    /// Cached compiled regexes for CriticMarkup delimiters
    private static let criticMarkupDelimiterRegexes: [NSRegularExpression] = [
        #"\{\+\+"#, #"\+\+\}"#,
        #"\{--"#, #"--\}"#,
        #"\{~~"#, #"~>"#, #"~~\}"#,
        #"\{=="#, #"==\}"#, #"\{>>"#, #"<<\}"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    /// Dims CriticMarkup delimiters to make the content stand out over the syntax.
    private static func dimCriticMarkupDelimiters(in attributed: NSMutableAttributedString, range: NSRange, text: String) {
        let delimiterColor = NSColor.tertiaryLabelColor

        for regex in criticMarkupDelimiterRegexes {
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
