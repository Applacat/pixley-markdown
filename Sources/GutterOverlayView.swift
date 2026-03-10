import AppKit

// MARK: - Gutter Overlay View

/// Floating line number gutter drawn as a subview of the NSScrollView.
/// Sits above the text view in z-order so nothing can cover it.
/// Reads the text view's layout manager to draw line numbers at exact line positions.
final class GutterOverlayView: NSView {

    override var isFlipped: Bool { true }

    weak var textView: MarkdownNSTextView?

    var lineNumberColor: NSColor = .secondaryLabelColor { didSet { needsDisplay = true } }
    var gutterBackground: NSColor = .textBackgroundColor { didSet { needsDisplay = true } }
    var bookmarkedLines: Set<Int> = [] { didSet { needsDisplay = true } }
    /// Lines that have a `<!-- feedback -->` comment on the next line
    var commentedLines: Set<Int> = [] { didSet { needsDisplay = true } }

    /// Called when gutter popover submits (lineNumber, shouldBookmark, commentText-or-nil)
    var onGutterAction: ((Int, Bool, String?) -> Void)?
    /// Called to toggle bookmark independently
    var onToggleBookmark: ((Int) -> Void)?

    var lineNumberFont: NSFont = .monospacedDigitSystemFont(ofSize: 10, weight: .regular) {
        didSet { needsDisplay = true }
    }

    /// Active gutter popover (retained to prevent premature dealloc)
    private var gutterPopover: NSPopover?

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let textStorage = textView.textStorage else { return }

        // Fill gutter background
        gutterBackground.setFill()
        dirtyRect.fill()

        // Separator line on right edge
        NSColor.separatorColor.withAlphaComponent(0.2).setStroke()
        let sep = NSBezierPath()
        sep.move(to: NSPoint(x: bounds.width - 0.5, y: dirtyRect.origin.y))
        sep.line(to: NSPoint(x: bounds.width - 0.5, y: NSMaxY(dirtyRect)))
        sep.lineWidth = 1
        sep.stroke()

        // Get visible area from clip view
        guard let clipView = textView.enclosingScrollView?.contentView else { return }
        let clipBounds = clipView.bounds

        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: clipBounds, in: textContainer)
        guard visibleGlyphRange.length > 0 else { return }
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        let nsText = textStorage.string as NSString
        guard nsText.length > 0, visibleCharRange.location < nsText.length else { return }

        // Count lines before visible range to get starting line number
        var lineNumber = 1
        let scanEnd = min(visibleCharRange.location, nsText.length)
        for i in 0..<scanEnd {
            if nsText.character(at: i) == 0x0A { lineNumber += 1 }
        }

        let textContainerOrigin = textView.textContainerOrigin
        let gutterContentWidth = bounds.width - 8 // right padding before separator

        // Walk visible lines
        var charIndex = visibleCharRange.location
        while charIndex < NSMaxRange(visibleCharRange) && charIndex < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: charIndex, length: 0))
            let lineGlyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            guard lineGlyphRange.location < layoutManager.numberOfGlyphs else { break }

            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: lineGlyphRange.location, effectiveRange: nil)

            // Convert: text container → text view → gutter overlay
            let yInGutter = lineRect.origin.y + textContainerOrigin.y - clipBounds.origin.y

            if yInGutter + lineRect.height >= dirtyRect.origin.y && yInGutter < NSMaxY(dirtyRect) {
                let isBookmarked = bookmarkedLines.contains(lineNumber)
                let hasComment = commentedLines.contains(lineNumber)
                let numStr = "\(lineNumber)" as NSString
                let color = (isBookmarked || hasComment) ? NSColor.systemOrange : lineNumberColor
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: lineNumberFont,
                    .foregroundColor: color
                ]
                let size = numStr.size(withAttributes: attrs)
                let x = gutterContentWidth - size.width
                let y = yInGutter + (lineRect.height - size.height) / 2
                numStr.draw(at: NSPoint(x: max(4, x), y: y), withAttributes: attrs)

                // Indicator: speech bubble for comments, dot for bookmarks
                if hasComment {
                    let symbolSize: CGFloat = 10
                    let symbolImage = NSImage(systemSymbolName: "text.bubble.fill", accessibilityDescription: "Comment")
                    if let image = symbolImage {
                        let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .regular)
                        let configured = image.withSymbolConfiguration(config) ?? image
                        let iconRect = NSRect(
                            x: 2,
                            y: yInGutter + (lineRect.height - symbolSize) / 2,
                            width: symbolSize,
                            height: symbolSize
                        )
                        NSColor.systemBlue.set()
                        configured.draw(in: iconRect)
                    }
                } else if isBookmarked {
                    let dotSize: CGFloat = 5
                    let dotRect = NSRect(
                        x: 3,
                        y: yInGutter + (lineRect.height - dotSize) / 2,
                        width: dotSize,
                        height: dotSize
                    )
                    NSColor.systemOrange.setFill()
                    NSBezierPath(ovalIn: dotRect).fill()
                }
            }

            lineNumber += 1
            charIndex = NSMaxRange(lineRange)
            if charIndex <= lineRange.location { break } // safety
        }
    }

    // MARK: - Gutter Click (Popover)

    override func mouseDown(with event: NSEvent) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let textStorage = textView.textStorage,
              let clipView = textView.enclosingScrollView?.contentView else {
            super.mouseDown(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let clipBounds = clipView.bounds
        let textContainerOrigin = textView.textContainerOrigin

        // Convert gutter y → text container y
        let tcY = point.y + clipBounds.origin.y - textContainerOrigin.y
        let tcPoint = NSPoint(x: 0, y: tcY)

        let glyphIndex = layoutManager.glyphIndex(for: tcPoint, in: textContainer)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return }
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

        let nsText = textStorage.string as NSString
        var lineNum = 1
        for i in 0..<min(charIndex, nsText.length) {
            if nsText.character(at: i) == 0x0A { lineNum += 1 }
        }

        // Find existing comment on the next line
        let existingComment = findExistingComment(afterLine: lineNum, in: nsText as String)
        let isBookmarked = bookmarkedLines.contains(lineNum)

        showGutterPopover(
            lineNumber: lineNum,
            isBookmarked: isBookmarked,
            existingComment: existingComment,
            at: point
        )
    }

    // MARK: - Comment Detection

    /// Checks if the line after `lineNumber` contains a `<!-- feedback -->` tag and returns its text.
    private func findExistingComment(afterLine lineNumber: Int, in text: String) -> String? {
        let lines = text.components(separatedBy: "\n")
        // lineNumber is 1-based, so the next line index is lineNumber (0-based = lineNumber - 1, next = lineNumber)
        guard lineNumber < lines.count else { return nil }
        let nextLine = lines[lineNumber].trimmingCharacters(in: .whitespaces)

        // Match <!-- feedback --> or <!-- feedback: text -->
        let pattern = #"^<!--\s*feedback\s*(?::\s*(.*?))?\s*-->$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: nextLine, range: NSRange(nextLine.startIndex..., in: nextLine)) else {
            return nil
        }

        if let textRange = Range(match.range(at: 1), in: nextLine) {
            return String(nextLine[textRange])
        }
        return "" // Tag exists but no text
    }

    // MARK: - Gutter Popover

    private func showGutterPopover(lineNumber: Int, isBookmarked: Bool, existingComment: String?, at point: NSPoint) {
        gutterPopover?.close()

        let popover = NSPopover()
        popover.behavior = .transient

        let controller = GutterCommentPopoverController(
            isBookmarked: isBookmarked,
            existingComment: existingComment ?? "",
            onSubmit: { [weak self] (shouldBookmark: Bool, commentText: String) in
                self?.gutterPopover?.close()
                self?.gutterPopover = nil

                // Handle bookmark toggle
                let wasBookmarked = self?.bookmarkedLines.contains(lineNumber) ?? false
                if shouldBookmark != wasBookmarked {
                    self?.onToggleBookmark?(lineNumber)
                }

                // Handle comment (nil = no change, empty = remove, non-empty = set)
                let trimmed = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty && existingComment != nil {
                    // Remove existing comment
                    self?.onGutterAction?(lineNumber, shouldBookmark, nil)
                } else if !trimmed.isEmpty {
                    // Set/update comment
                    self?.onGutterAction?(lineNumber, shouldBookmark, trimmed)
                }
            },
            onCancel: { [weak self] in
                self?.gutterPopover?.close()
                self?.gutterPopover = nil
            }
        )
        popover.contentViewController = controller

        let lineRect = NSRect(x: 0, y: point.y - 8, width: bounds.width, height: 16)
        gutterPopover = popover
        popover.show(relativeTo: lineRect, of: self, preferredEdge: .maxX)
    }
}
