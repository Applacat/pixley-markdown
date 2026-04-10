import Foundation

// MARK: - Interactive Element Detector

/// Detects all 9 interactive element types in markdown text using regex patterns.
/// Designed for single-pass detection with priority ordering.
public enum InteractiveElementDetector: Sendable {

    /// Detects all interactive elements in the given text.
    /// Elements are returned sorted by their position in the text.
    public static func detect(in text: String) -> [InteractiveElement] {
        var elements: [InteractiveElement] = []

        // Detect blockquote-based patterns first (they contain checkboxes that
        // should NOT be detected as standalone checkboxes)
        let blockquoteRanges = detectBlockquoteGroups(in: text)

        for bqRange in blockquoteRanges {
            let bqText = String(text[bqRange])
            if let review = detectReview(in: text, blockquoteRange: bqRange, blockquoteText: bqText) {
                elements.append(.review(review))
            } else if let choice = detectChoice(in: text, blockquoteRange: bqRange, blockquoteText: bqText) {
                elements.append(.choice(choice))
            }
            // Confidence indicators disabled for v3.0 — revisit in a future version
            // elements.append(contentsOf: detectConfidence(in: text, searchRange: bqRange))
        }

        // Standalone checkboxes (outside blockquotes) — includes auditable checkbox detection
        elements.append(contentsOf: detectCheckboxes(in: text, excludingRanges: blockquoteRanges))

        // Spec 4 new controls — must run BEFORE generic fill-in detection
        // because they use the `[[...]]` syntax
        elements.append(contentsOf: detectSliders(in: text))
        elements.append(contentsOf: detectSteppers(in: text))
        elements.append(contentsOf: detectToggles(in: text))
        elements.append(contentsOf: detectColorPickers(in: text))

        // Collect ranges already claimed by Spec 4 controls so fill-in doesn't re-detect them
        let spec4Ranges: [Range<String.Index>] = elements.compactMap { element in
            switch element {
            case .slider, .stepper, .toggle, .colorPicker: return element.range
            default: return nil
            }
        }

        // Fill-in-the-blank (skips ranges claimed by Spec 4 controls)
        elements.append(contentsOf: detectFillIns(in: text, excludingRanges: spec4Ranges))

        // Feedback comments
        elements.append(contentsOf: detectFeedback(in: text))

        // CriticMarkup suggestions
        elements.append(contentsOf: detectSuggestions(in: text))

        // Status state machines
        elements.append(contentsOf: detectStatuses(in: text))

        // Conditional sections
        elements.append(contentsOf: detectConditionals(in: text))

        // Collapsible sections
        elements.append(contentsOf: detectCollapsibles(in: text))

        // Sort by position
        elements.sort { $0.range.lowerBound < $1.range.lowerBound }

        return elements
    }

    // MARK: - Blockquote Group Detection

    /// Finds contiguous blockquote groups (lines starting with >).
    /// Returns the ranges of each group.
    private static func detectBlockquoteGroups(in text: String) -> [Range<String.Index>] {
        var groups: [Range<String.Index>] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var lineStart = text.startIndex
        var groupStart: String.Index?

        for line in lines {
            let lineEnd = text.index(lineStart, offsetBy: line.count)
            let fullLineEnd = lineEnd < text.endIndex ? text.index(after: lineEnd) : lineEnd

            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            let isBlockquoteLine = trimmed.hasPrefix(">")

            if isBlockquoteLine {
                if groupStart == nil {
                    groupStart = lineStart
                }
            } else {
                if let start = groupStart {
                    groups.append(start..<lineStart)
                    groupStart = nil
                }
            }

            lineStart = fullLineEnd
        }

        // Close final group
        if let start = groupStart {
            groups.append(start..<text.endIndex)
        }

        return groups
    }

    // MARK: - Checkbox Detection

    private static let checkboxPattern = try! NSRegularExpression(
        pattern: #"^[\t ]*[-*+][\t ]+\[([ xX])\][\t ]+(.+)$"#,
        options: .anchorsMatchLines
    )

    /// Detects standalone checkboxes (not inside blockquotes).
    /// Routes checkboxes with `(notes)` suffix to AuditableCheckboxElement.
    static func detectCheckboxes(in text: String, excludingRanges: [Range<String.Index>]) -> [InteractiveElement] {
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = checkboxPattern.matches(in: text, range: nsRange)

        return matches.compactMap { match -> InteractiveElement? in
            guard let fullRange = Range(match.range, in: text),
                  let checkRange = Range(match.range(at: 1), in: text),
                  let labelRange = Range(match.range(at: 2), in: text) else { return nil }

            // Skip if inside a blockquote
            if excludingRanges.contains(where: { $0.contains(fullRange.lowerBound) }) {
                return nil
            }

            let isChecked = text[checkRange] == "x" || text[checkRange] == "X"
            let label = String(text[labelRange])

            // Check if this is an auditable checkbox (label contains "(notes)" marker)
            if let auditable = classifyAsAuditable(fullRange: fullRange, checkRange: checkRange, isChecked: isChecked, label: label) {
                return .auditableCheckbox(auditable)
            }

            return .checkbox(CheckboxElement(
                range: fullRange,
                checkRange: checkRange,
                isChecked: isChecked,
                label: label
            ))
        }
    }

    /// Pattern for auditable checkbox labels with optional audit trail.
    /// Group 1: label including `(notes)` marker
    /// Group 2: optional date (YYYY-MM-DD)
    /// Group 3: optional note text after colon
    private static let auditablePattern = try! NSRegularExpression(
        pattern: #"^(.*?\(notes\))(?:\s*—\s*(\d{4}-\d{2}-\d{2})(?::\s*(.+))?)?\s*$"#
    )

    /// Detects the `(notes)` marker in a checkbox label and parses the audit trail.
    /// Formats:
    ///   - `Label (notes)` → unchecked auditable
    ///   - `Label (notes) — 2026-04-10` → checked, no note
    ///   - `Label (notes) — 2026-04-10: note text` → checked with note
    private static func classifyAsAuditable(
        fullRange: Range<String.Index>,
        checkRange: Range<String.Index>,
        isChecked: Bool,
        label: String
    ) -> AuditableCheckboxElement? {
        let nsRange = NSRange(label.startIndex..., in: label)
        guard let match = auditablePattern.firstMatch(in: label, range: nsRange),
              let cleanLabelRange = Range(match.range(at: 1), in: label) else {
            return nil
        }

        // Strip `(notes)` from displayed label
        let rawLabel = String(label[cleanLabelRange])
        let cleanLabel = rawLabel
            .replacingOccurrences(of: "(notes)", with: "")
            .trimmingCharacters(in: .whitespaces)

        let date: String? = Range(match.range(at: 2), in: label).map { String(label[$0]) }
        let note: String? = Range(match.range(at: 3), in: label).map { String(label[$0]) }

        return AuditableCheckboxElement(
            range: fullRange,
            checkRange: checkRange,
            isChecked: isChecked,
            label: cleanLabel,
            date: date,
            note: note
        )
    }

    // MARK: - Choice Detection (Radio in Blockquote)

    private static let blockquoteCheckboxPattern = try! NSRegularExpression(
        pattern: #">[\t ]*\[([ xX])\][\t ]+(.+?)(?=[\t ]*\[([ xX])\]|$)"#,
        options: .anchorsMatchLines
    )

    private static let blockquoteLineCheckboxPattern = try! NSRegularExpression(
        pattern: #"(?:>[\t ]*)?(?:[-*+][\t ]+)?\[([ xX])\][\t ]+(.+?)$"#,
        options: .anchorsMatchLines
    )

    /// Detects a choice (radio) element inside a blockquote range.
    /// Returns nil if the blockquote doesn't contain 2+ checkboxes.
    static func detectChoice(in text: String, blockquoteRange: Range<String.Index>, blockquoteText: String) -> ChoiceElement? {
        let options = parseBlockquoteOptions(in: text, blockquoteRange: blockquoteRange)
        guard options.count >= 2 else { return nil }

        let selectedIndex = options.firstIndex(where: { $0.isSelected })

        return ChoiceElement(
            blockquoteRange: blockquoteRange,
            options: options.map { ChoiceOption(
                range: $0.range,
                checkRange: $0.checkRange,
                isSelected: $0.isSelected,
                label: $0.label
            )},
            selectedIndex: selectedIndex
        )
    }

    // MARK: - Review Detection

    private static let reviewKeywords: Set<String> = [
        "APPROVED", "PASS", "FAIL", "PASS WITH NOTES", "BLOCKED", "N/A"
    ]

    /// Detects a review element inside a blockquote range.
    /// Returns nil if the blockquote doesn't contain review keywords.
    static func detectReview(in text: String, blockquoteRange: Range<String.Index>, blockquoteText: String) -> ReviewElement? {
        let options = parseBlockquoteOptions(in: text, blockquoteRange: blockquoteRange)
        guard !options.isEmpty else { return nil }

        // Check if any option label starts with a review keyword
        var reviewOptions: [ReviewOption] = []
        for opt in options {
            let labelUpper = opt.label.trimmingCharacters(in: .whitespaces)
            guard let status = matchReviewStatus(labelUpper) else { continue }

            // Extract date and notes from label like "PASS — 2026-03-07: notes here"
            let (notes, date) = extractDateAndNotes(from: labelUpper, status: status)

            reviewOptions.append(ReviewOption(
                range: opt.range,
                checkRange: opt.checkRange,
                isSelected: opt.isSelected,
                status: status,
                notes: notes,
                date: date
            ))
        }

        // Need at least one review keyword to qualify as a review
        guard !reviewOptions.isEmpty else { return nil }

        let selectedStatus = reviewOptions.first(where: { $0.isSelected })?.status

        return ReviewElement(
            blockquoteRange: blockquoteRange,
            options: reviewOptions,
            selectedStatus: selectedStatus
        )
    }

    private static func matchReviewStatus(_ label: String) -> ReviewStatus? {
        // Check longest matches first to avoid "PASS" matching "PASS WITH NOTES"
        let upper = label.uppercased()
        if upper.hasPrefix("PASS WITH NOTES") { return .passWithNotes }
        if upper.hasPrefix("APPROVED") { return .approved }
        if upper.hasPrefix("BLOCKED") { return .blocked }
        if upper.hasPrefix("PASS") { return .pass }
        if upper.hasPrefix("FAIL") { return .fail }
        if upper.hasPrefix("N/A") { return .notApplicable }
        return nil
    }

    private static func extractDateAndNotes(from label: String, status: ReviewStatus) -> (notes: String?, date: String?) {
        // Pattern: "STATUS — YYYY-MM-DD" or "STATUS — YYYY-MM-DD: notes"
        let datePattern = try! NSRegularExpression(
            pattern: #"—\s*(\d{4}-\d{2}-\d{2})(?::\s*(.+))?"#
        )
        let nsRange = NSRange(label.startIndex..., in: label)
        guard let match = datePattern.firstMatch(in: label, range: nsRange) else {
            return (nil, nil)
        }

        let date: String? = Range(match.range(at: 1), in: label).map { String(label[$0]) }
        let notes: String? = Range(match.range(at: 2), in: label).map { String(label[$0]) }

        return (notes, date)
    }

    // MARK: - Shared Blockquote Option Parsing

    private struct ParsedOption {
        let range: Range<String.Index>
        let checkRange: Range<String.Index>
        let isSelected: Bool
        let label: String
    }

    private static let bqOptionPattern = try! NSRegularExpression(
        pattern: #"\[([ xX])\][\t ]+(.+?)(?=\n|$)"#,
        options: [.anchorsMatchLines]
    )

    private static func parseBlockquoteOptions(in text: String, blockquoteRange: Range<String.Index>) -> [ParsedOption] {
        let nsRange = NSRange(blockquoteRange, in: text)
        let matches = bqOptionPattern.matches(in: text, range: nsRange)

        return matches.compactMap { match -> ParsedOption? in
            guard let fullRange = Range(match.range, in: text),
                  let checkRange = Range(match.range(at: 1), in: text),
                  let labelRange = Range(match.range(at: 2), in: text) else { return nil }

            let checkChar = text[checkRange]
            let isSelected = checkChar == "x" || checkChar == "X"
            let label = String(text[labelRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n> ", with: " ")
                .replacingOccurrences(of: "\n>", with: " ")

            return ParsedOption(
                range: fullRange,
                checkRange: checkRange,
                isSelected: isSelected,
                label: label
            )
        }
    }

    // MARK: - Fill-in-the-Blank Detection

    private static let fillInPattern = try! NSRegularExpression(
        pattern: #"\[\[([^\]]+)\]\]"#
    )

    static func detectFillIns(in text: String, excludingRanges: [Range<String.Index>] = []) -> [InteractiveElement] {
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = fillInPattern.matches(in: text, range: nsRange)

        return matches.compactMap { match -> InteractiveElement? in
            guard let fullRange = Range(match.range, in: text),
                  let hintRange = Range(match.range(at: 1), in: text) else { return nil }

            // Skip ranges already claimed by Spec 4 controls
            if excludingRanges.contains(where: { $0 == fullRange }) {
                return nil
            }

            let hint = String(text[hintRange])

            // Spec 4: Re-pickable file/folder picker — filled values use `file: PATH` or `folder: PATH` prefix
            let trimmedHint = hint.trimmingCharacters(in: .whitespaces)
            if trimmedHint.hasPrefix("file:") {
                let path = String(trimmedHint.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                return .fillIn(FillInElement(
                    range: fullRange,
                    hint: hint,
                    type: .file,
                    value: path
                ))
            }
            if trimmedHint.hasPrefix("folder:") {
                let path = String(trimmedHint.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                return .fillIn(FillInElement(
                    range: fullRange,
                    hint: hint,
                    type: .folder,
                    value: path
                ))
            }

            // Check if this is a filled value (not a placeholder)
            if isFilledValue(hint) {
                // Filled: hint IS the value, type is always .text for re-edit
                return .fillIn(FillInElement(
                    range: fullRange,
                    hint: hint,
                    type: .text,
                    value: hint
                ))
            }

            let type = classifyFillInType(hint)
            return .fillIn(FillInElement(
                range: fullRange,
                hint: hint,
                type: type,
                value: nil
            ))
        }
    }

    // MARK: - Spec 4: Slider Detection

    /// Matches `[[slide MIN-MAX]]` or `[[rate MIN-MAX]]` with strict integer ranges.
    /// MIN must be less than MAX.
    private static let sliderPattern = try! NSRegularExpression(
        pattern: #"\[\[(slide|rate)\s+(\d+)-(\d+)\]\]"#
    )

    static func detectSliders(in text: String) -> [InteractiveElement] {
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = sliderPattern.matches(in: text, range: nsRange)

        return matches.compactMap { match -> InteractiveElement? in
            guard let fullRange = Range(match.range, in: text),
                  let keywordRange = Range(match.range(at: 1), in: text),
                  let minRange = Range(match.range(at: 2), in: text),
                  let maxRange = Range(match.range(at: 3), in: text),
                  let minValue = Int(text[minRange]),
                  let maxValue = Int(text[maxRange]),
                  minValue < maxValue else {
                return nil
            }

            let keyword = String(text[keywordRange])
            return .slider(SliderElement(
                range: fullRange,
                minValue: minValue,
                maxValue: maxValue,
                keyword: keyword
            ))
        }
    }

    // MARK: - Spec 4: Stepper Detection

    /// Matches `[[pick number]]` or `[[pick number MIN-MAX]]`.
    private static let stepperPattern = try! NSRegularExpression(
        pattern: #"\[\[pick\s+number(?:\s+(\d+)-(\d+))?\]\]"#
    )

    static func detectSteppers(in text: String) -> [InteractiveElement] {
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = stepperPattern.matches(in: text, range: nsRange)

        return matches.compactMap { match -> InteractiveElement? in
            guard let fullRange = Range(match.range, in: text) else { return nil }

            var minValue: Int? = nil
            var maxValue: Int? = nil
            if match.numberOfRanges > 2,
               let minR = Range(match.range(at: 1), in: text),
               let maxR = Range(match.range(at: 2), in: text),
               let mn = Int(text[minR]),
               let mx = Int(text[maxR]),
               mn < mx {
                minValue = mn
                maxValue = mx
            }

            return .stepper(StepperElement(
                range: fullRange,
                minValue: minValue,
                maxValue: maxValue
            ))
        }
    }

    // MARK: - Spec 4: Toggle Detection

    /// Matches `[[toggle]]`.
    private static let togglePattern = try! NSRegularExpression(
        pattern: #"\[\[toggle\]\]"#
    )

    static func detectToggles(in text: String) -> [InteractiveElement] {
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = togglePattern.matches(in: text, range: nsRange)

        return matches.compactMap { match -> InteractiveElement? in
            guard let fullRange = Range(match.range, in: text) else { return nil }
            return .toggle(ToggleElement(range: fullRange))
        }
    }

    // MARK: - Spec 4: Color Picker Detection

    /// Matches `[[pick color]]`.
    private static let colorPickerPattern = try! NSRegularExpression(
        pattern: #"\[\[pick\s+color\]\]"#
    )

    static func detectColorPickers(in text: String) -> [InteractiveElement] {
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = colorPickerPattern.matches(in: text, range: nsRange)

        return matches.compactMap { match -> InteractiveElement? in
            guard let fullRange = Range(match.range, in: text) else { return nil }
            return .colorPicker(ColorPickerElement(range: fullRange))
        }
    }

    /// Returns true if the text inside [[ ]] is a user-filled value rather than a placeholder hint.
    /// Placeholder hints contain directive words like "enter", "fill-in", "choose", "pick", "select".
    private static func isFilledValue(_ hint: String) -> Bool {
        let lower = hint.lowercased().trimmingCharacters(in: .whitespaces)
        // Spec 4 keyword prefixes — these are control patterns that failed Spec 4 detection
        // (e.g. invalid `[[slide 10-1]]` range). They should never be treated as filled fill-ins.
        let spec4Keywords = ["slide", "rate", "toggle"]
        for keyword in spec4Keywords {
            if lower == keyword || lower.hasPrefix("\(keyword) ") { return false }
        }
        let placeholderKeywords = ["enter", "fill-in", "fill in", "choose", "pick", "select", "type", "your "]
        // If hint contains a placeholder keyword followed by content description, it's a placeholder
        // Also check for pipe separator (used in [[fill-in: type | hint]] extended syntax)
        if lower.contains("|") { return false }
        if lower.contains(":") { return false }
        for keyword in placeholderKeywords {
            if lower.contains(keyword) { return false }
        }
        return true
    }

    private static func classifyFillInType(_ hint: String) -> FillInType {
        let lower = hint.lowercased().trimmingCharacters(in: .whitespaces)
        if lower.hasPrefix("choose file") { return .file }
        if lower.hasPrefix("choose folder") { return .folder }
        // Match any hint containing "date" — covers "pick date", "choose a date", "start date", etc.
        if lower.contains("date") { return .date }
        return .text
    }

    // MARK: - Feedback Detection

    private static let feedbackPattern = try! NSRegularExpression(
        pattern: #"<!--\s*feedback\s*(?::\s*(.*?))?\s*-->"#,
        options: .dotMatchesLineSeparators
    )

    static func detectFeedback(in text: String) -> [InteractiveElement] {
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = feedbackPattern.matches(in: text, range: nsRange)

        return matches.compactMap { match -> InteractiveElement? in
            guard let fullRange = Range(match.range, in: text) else { return nil }

            let existingText: String?
            if match.range(at: 1).location != NSNotFound,
               let textRange = Range(match.range(at: 1), in: text) {
                let captured = String(text[textRange]).trimmingCharacters(in: .whitespaces)
                existingText = captured.isEmpty ? nil : captured
            } else {
                existingText = nil
            }

            return .feedback(FeedbackElement(
                range: fullRange,
                existingText: existingText
            ))
        }
    }

    // MARK: - CriticMarkup (Suggestion) Detection

    private static let additionPattern = try! NSRegularExpression(
        pattern: #"\{\+\+(.+?)\+\+\}"#,
        options: .dotMatchesLineSeparators
    )

    private static let deletionPattern = try! NSRegularExpression(
        pattern: #"\{--(.+?)--\}"#,
        options: .dotMatchesLineSeparators
    )

    private static let substitutionPattern = try! NSRegularExpression(
        pattern: #"\{~~(.+?)~>(.+?)~~\}"#,
        options: .dotMatchesLineSeparators
    )

    private static let highlightPattern = try! NSRegularExpression(
        pattern: #"\{==(.+?)==\}\{>>(.+?)<<\}"#,
        options: .dotMatchesLineSeparators
    )

    static func detectSuggestions(in text: String) -> [InteractiveElement] {
        let nsRange = NSRange(text.startIndex..., in: text)
        var elements: [InteractiveElement] = []

        // Additions
        for match in additionPattern.matches(in: text, range: nsRange) {
            guard let fullRange = Range(match.range, in: text),
                  let newRange = Range(match.range(at: 1), in: text) else { continue }
            elements.append(.suggestion(SuggestionElement(
                range: fullRange,
                type: .addition,
                oldText: nil,
                newText: String(text[newRange]),
                comment: nil
            )))
        }

        // Deletions
        for match in deletionPattern.matches(in: text, range: nsRange) {
            guard let fullRange = Range(match.range, in: text),
                  let oldRange = Range(match.range(at: 1), in: text) else { continue }
            elements.append(.suggestion(SuggestionElement(
                range: fullRange,
                type: .deletion,
                oldText: String(text[oldRange]),
                newText: nil,
                comment: nil
            )))
        }

        // Substitutions
        for match in substitutionPattern.matches(in: text, range: nsRange) {
            guard let fullRange = Range(match.range, in: text),
                  let oldRange = Range(match.range(at: 1), in: text),
                  let newRange = Range(match.range(at: 2), in: text) else { continue }
            elements.append(.suggestion(SuggestionElement(
                range: fullRange,
                type: .substitution,
                oldText: String(text[oldRange]),
                newText: String(text[newRange]),
                comment: nil
            )))
        }

        // Highlights with comments
        for match in highlightPattern.matches(in: text, range: nsRange) {
            guard let fullRange = Range(match.range, in: text),
                  let textRange = Range(match.range(at: 1), in: text),
                  let commentRange = Range(match.range(at: 2), in: text) else { continue }
            elements.append(.suggestion(SuggestionElement(
                range: fullRange,
                type: .highlight,
                oldText: String(text[textRange]),
                newText: nil,
                comment: String(text[commentRange])
            )))
        }

        return elements
    }

    // MARK: - Status State Machine Detection

    private static let statusCommentPattern = try! NSRegularExpression(
        pattern: #"<!--\s*status:\s*(.+?)\s*-->"#
    )

    private static let statusLabelPattern = try! NSRegularExpression(
        pattern: #"\*\*Status:\*\*\s*(\S+(?:\s*—\s*\d{4}-\d{2}-\d{2})?)"#
    )

    static func detectStatuses(in text: String) -> [InteractiveElement] {
        let nsRange = NSRange(text.startIndex..., in: text)
        let commentMatches = statusCommentPattern.matches(in: text, range: nsRange)

        return commentMatches.compactMap { commentMatch -> InteractiveElement? in
            guard let commentRange = Range(commentMatch.range, in: text),
                  let statesRange = Range(commentMatch.range(at: 1), in: text) else { return nil }

            let statesStr = String(text[statesRange])
            // Support both / and | as separators (/ preferred — doesn't conflict with markdown tables)
            let separator: String = statesStr.contains("/") ? "/" : "|"
            let states = statesStr.components(separatedBy: separator).map { $0.trimmingCharacters(in: .whitespaces) }

            // Look for the status label immediately after the comment
            let searchStart = commentRange.upperBound
            let searchEnd = text.index(searchStart, offsetBy: 200, limitedBy: text.endIndex) ?? text.endIndex
            let searchNSRange = NSRange(searchStart..<searchEnd, in: text)

            guard let labelMatch = statusLabelPattern.firstMatch(in: text, range: searchNSRange),
                  let labelFullRange = Range(labelMatch.range, in: text),
                  let currentStateRange = Range(labelMatch.range(at: 1), in: text) else { return nil }

            let currentStateRaw = String(text[currentStateRange])
            // Strip date suffix if present
            let currentState = currentStateRaw.components(separatedBy: "—").first?.trimmingCharacters(in: .whitespaces) ?? currentStateRaw

            return .status(StatusElement(
                commentRange: commentRange,
                labelRange: labelFullRange,
                states: states,
                currentState: currentState
            ))
        }
    }

    // MARK: - Confidence Indicator Detection

    private static let confidencePattern = try! NSRegularExpression(
        pattern: #">\s*\[confidence:\s*(high|medium|low|confirmed)\]\s*(.+)$"#,
        options: .anchorsMatchLines
    )

    static func detectConfidence(in text: String, searchRange: Range<String.Index>? = nil) -> [InteractiveElement] {
        let range = searchRange ?? text.startIndex..<text.endIndex
        let nsRange = NSRange(range, in: text)
        let matches = confidencePattern.matches(in: text, range: nsRange)

        return matches.compactMap { match -> InteractiveElement? in
            guard let fullRange = Range(match.range, in: text),
                  let levelRange = Range(match.range(at: 1), in: text),
                  let textRange = Range(match.range(at: 2), in: text) else { return nil }

            guard let level = ConfidenceLevel(rawValue: String(text[levelRange])) else { return nil }

            return .confidence(ConfidenceElement(
                range: fullRange,
                level: level,
                text: String(text[textRange]).trimmingCharacters(in: .whitespaces)
            ))
        }
    }

    // MARK: - Conditional Section Detection

    private static let conditionalStartPattern = try! NSRegularExpression(
        pattern: #"<!--\s*if:\s*(\w+)\s*=\s*(.+?)\s*-->"#
    )

    private static let conditionalEndPattern = try! NSRegularExpression(
        pattern: #"<!--\s*endif\s*-->"#
    )

    static func detectConditionals(in text: String) -> [InteractiveElement] {
        let nsRange = NSRange(text.startIndex..., in: text)
        let startMatches = conditionalStartPattern.matches(in: text, range: nsRange)

        return startMatches.compactMap { startMatch -> InteractiveElement? in
            guard let startRange = Range(startMatch.range, in: text),
                  let keyRange = Range(startMatch.range(at: 1), in: text),
                  let valueRange = Range(startMatch.range(at: 2), in: text) else { return nil }

            // Find the matching endif after this start
            let searchStart = startRange.upperBound
            let searchNSRange = NSRange(searchStart..<text.endIndex, in: text)

            guard let endMatch = conditionalEndPattern.firstMatch(in: text, range: searchNSRange),
                  let endRange = Range(endMatch.range, in: text) else { return nil }

            let fullRange = startRange.lowerBound..<endRange.upperBound
            let contentRange = startRange.upperBound..<endRange.lowerBound

            return .conditional(ConditionalElement(
                range: fullRange,
                key: String(text[keyRange]),
                value: String(text[valueRange]),
                contentRange: contentRange
            ))
        }
    }

    // MARK: - Collapsible Section Detection

    private static let collapsibleStartPattern = try! NSRegularExpression(
        pattern: #"<!--\s*collapsible:\s*(.+?)\s*-->"#
    )

    private static let collapsibleEndPattern = try! NSRegularExpression(
        pattern: #"<!--\s*endcollapsible\s*-->"#
    )

    static func detectCollapsibles(in text: String) -> [InteractiveElement] {
        let nsRange = NSRange(text.startIndex..., in: text)
        let startMatches = collapsibleStartPattern.matches(in: text, range: nsRange)

        return startMatches.compactMap { startMatch -> InteractiveElement? in
            guard let startRange = Range(startMatch.range, in: text),
                  let titleRange = Range(startMatch.range(at: 1), in: text) else { return nil }

            let searchStart = startRange.upperBound
            let searchNSRange = NSRange(searchStart..<text.endIndex, in: text)

            guard let endMatch = collapsibleEndPattern.firstMatch(in: text, range: searchNSRange),
                  let endRange = Range(endMatch.range, in: text) else { return nil }

            let fullRange = startRange.lowerBound..<endRange.upperBound
            let contentRange = startRange.upperBound..<endRange.lowerBound

            return .collapsible(CollapsibleElement(
                range: fullRange,
                title: String(text[titleRange]),
                contentRange: contentRange
            ))
        }
    }
}
