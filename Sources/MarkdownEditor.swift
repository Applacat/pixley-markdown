import SwiftUI
import AppKit
import aimdRenderer

// MARK: - Configuration

/// Configuration for markdown text handling
/// OOD: Shared, observable configuration that can be modified from multiple places
enum MarkdownConfig {
    /// Maximum allowed text size (10MB) to prevent DoS attacks
    /// Accessible from any context without actor isolation
    static let maxTextSize = 10_485_760

    /// Maximum text size for syntax highlighting (1MB)
    /// Files larger than this show plain text
    static let maxHighlightSize = 1_048_576
}

// MARK: - Interactive Element Attribute Key

extension NSAttributedString.Key {
    /// Custom attribute storing the InteractiveElement at a given range
    static let interactiveElement = NSAttributedString.Key("com.pixley.interactiveElement")
}

// MARK: - Custom NSTextView

/// NSTextView subclass with interactive markdown element click handling.
/// Detects clicks on checkboxes, choices, fill-ins, and feedback markers.
/// Provides hover highlighting and tooltips for discoverability.
final class MarkdownNSTextView: NSTextView {

    /// Callback for handling interactive element clicks. Includes optional option index for choice/review.
    var onInteractiveElementClicked: ((InteractiveElement, Int?, NSPoint) -> Void)?

    /// Callback for status element dropdown selection (element, selected state).
    var onStatusSelected: ((StatusElement, String) -> Void)?

    /// Callback for input popover submissions (element, optionIndex, field name, value).
    var onInputSubmitted: ((InteractiveElement, Int?, String, String) -> Void)?

    /// Tracks the currently hovered interactive element range for hover highlight
    private var hoveredRange: NSRange?

    /// Pending status element for the native dropdown menu
    private var pendingStatusElement: StatusElement?

    /// Tracks the currently focused interactive element range (via Tab navigation)
    private var focusedElementRange: NSRange?

    /// Active upgrade popover (retained to prevent premature dealloc)
    private var upgradePopover: NSPopover?

    /// The tracking area for mouse movement events
    private var hoverTrackingArea: NSTrackingArea?

    // MARK: - Gutter Constants

    /// Width of the line number gutter column (used by GutterOverlayView)
    static let gutterWidth: CGFloat = 44

    override func cancelOperation(_ sender: Any?) {
        // Escape clears Tab focus first, then dismisses find bar
        if focusedElementRange != nil {
            clearFocusHighlight()
            return
        }
        let hideItem = NSMenuItem()
        hideItem.tag = NSTextFinder.Action.hideFindInterface.rawValue
        performFindPanelAction(hideItem)
    }

    // MARK: - Mouse Tracking Setup

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = hoverTrackingArea {
            removeTrackingArea(existing)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    // MARK: - Hover Highlight

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let charIndex = characterIndexForInsertion(at: point)

        guard charIndex >= 0, charIndex < textStorage?.length ?? 0,
              let layoutManager else {
            clearHoverHighlight()
            super.mouseMoved(with: event)
            return
        }

        // Check if mouse is over an interactive element
        var effectiveRange = NSRange()
        if let _ = textStorage?.attribute(.interactiveElement, at: charIndex, effectiveRange: &effectiveRange) as? InteractiveElementWrapper {
            // Only update if the hovered range changed
            if hoveredRange != effectiveRange {
                clearHoverHighlight()
                hoveredRange = effectiveRange
                // Temporary background highlight — overrides any permanent background during hover,
                // restores automatically when removed. The accent color signals "clickable."
                layoutManager.addTemporaryAttribute(
                    .backgroundColor,
                    value: NSColor.controlAccentColor.withAlphaComponent(0.12),
                    forCharacterRange: effectiveRange
                )
            }
        } else {
            clearHoverHighlight()
        }

        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        clearHoverHighlight()
        super.mouseExited(with: event)
    }

    private func clearHoverHighlight() {
        guard let hoveredRange, let layoutManager else { return }
        self.hoveredRange = nil
        // Guard against stale range after text storage replacement
        guard hoveredRange.location + hoveredRange.length <= layoutManager.numberOfGlyphs else { return }
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: hoveredRange)
    }

    /// Clears hover state without touching temporary attributes (safe when text storage is being replaced).
    func clearHover() {
        hoveredRange = nil
    }

    // MARK: - Click Handling

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let charIndex = characterIndexForInsertion(at: point)

        guard charIndex >= 0, charIndex < textStorage?.length ?? 0 else {
            super.mouseDown(with: event)
            return
        }

        // Clear Tab-focus when clicking anywhere
        clearFocusHighlight()

        // Check if the click hit an interactive element
        var effectiveRange = NSRange()
        if let wrapper = textStorage?.attribute(.interactiveElement, at: charIndex, effectiveRange: &effectiveRange) as? InteractiveElementWrapper {

            // Save scroll position before handling click to prevent unwanted scrolling
            let scrollView = enclosingScrollView
            let savedScrollOrigin = scrollView?.contentView.bounds.origin

            // Gate: Pro elements require purchase
            if wrapper.element.requiresPro && !StoreService.shared.isUnlocked {
                flashClickFeedback(range: effectiveRange)
                showUpgradePopover(for: wrapper.element, at: effectiveRange)
                // Restore scroll position after popover positioning
                if let origin = savedScrollOrigin {
                    scrollView?.contentView.scroll(to: origin)
                }
                return
            }

            // Status elements with multiple next states: show native dropdown menu
            if case .status(let st) = wrapper.element, st.nextStates.count > 1 {
                flashClickFeedback(range: effectiveRange)
                showStatusMenu(st, at: point)
                // Menu doesn't cause scroll, but keep consistent
                if let origin = savedScrollOrigin {
                    scrollView?.contentView.scroll(to: origin)
                }
                return
            }

            // Popover-based elements: show inline popover instead of calling back
            if showElementPopover(wrapper.element, optionIndex: wrapper.optionIndex, at: effectiveRange) {
                flashClickFeedback(range: effectiveRange)
                // Restore scroll position after popover positioning
                if let origin = savedScrollOrigin {
                    scrollView?.contentView.scroll(to: origin)
                }
                return
            }

            // Direct-action elements: brief accent flash then callback
            flashClickFeedback(range: effectiveRange)
            onInteractiveElementClicked?(wrapper.element, wrapper.optionIndex, point)
            // Direct actions don't create popovers, but keep consistent
            if let origin = savedScrollOrigin {
                scrollView?.contentView.scroll(to: origin)
            }
            return
        }

        super.mouseDown(with: event)
    }

    /// Flashes a brief accent highlight on the clicked element range for tactile feedback.
    /// Respects Reduce Motion accessibility setting.
    private func flashClickFeedback(range: NSRange) {
        guard let layoutManager else { return }
        // Skip flash animation when user prefers reduced motion
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return }
        let flashColor = NSColor.controlAccentColor.withAlphaComponent(0.25)
        layoutManager.addTemporaryAttribute(.backgroundColor, value: flashColor, forCharacterRange: range)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, let layoutManager = self.layoutManager else { return }
            // Guard against text storage replacement during the delay
            guard range.location + range.length <= layoutManager.numberOfGlyphs else { return }
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
        }
    }

    // MARK: - Native Status Menu

    /// Presents a native NSMenu dropdown at the given point for status state selection.
    private func showStatusMenu(_ status: StatusElement, at point: NSPoint) {
        pendingStatusElement = status
        let menu = NSMenu()

        // Current state (disabled, for context)
        let currentItem = NSMenuItem(title: "✓ \(status.currentState)", action: nil, keyEquivalent: "")
        currentItem.isEnabled = false
        menu.addItem(currentItem)
        menu.addItem(.separator())

        // Next states as selectable items
        for state in status.nextStates {
            let item = NSMenuItem(title: state, action: #selector(handleStatusMenuItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = state as NSString
            menu.addItem(item)
        }

        menu.popUp(positioning: nil, at: point, in: self)
    }

    @objc private func handleStatusMenuItem(_ sender: NSMenuItem) {
        guard let state = sender.representedObject as? String,
              let status = pendingStatusElement else { return }
        pendingStatusElement = nil
        onStatusSelected?(status, state)
    }

    // MARK: - Upgrade Popover

    /// Shows an NSPopover at the clicked element prompting the user to upgrade to Pro.
    private func showUpgradePopover(for element: InteractiveElement, at charRange: NSRange) {
        upgradePopover?.close()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 260, height: 150)

        let controller = UpgradePopoverController(
            elementName: element.displayName,
            price: StoreService.shared.productInfo?.displayPrice ?? "$9.99"
        ) { [weak self] in
            self?.upgradePopover?.close()
        }
        popover.contentViewController = controller

        // Position popover at the element's glyph rect
        guard let positionRect = glyphRect(for: charRange) else { return }
        upgradePopover = popover
        popover.show(relativeTo: positionRect, of: self, preferredEdge: .maxY)
    }

    // MARK: - Popover Routing

    /// Active input popover (retained to prevent premature dealloc)
    private var inputPopover: NSPopover?

    /// Returns the view-coordinate rect for a character range (for popover positioning).
    private func glyphRect(for charRange: NSRange) -> NSRect? {
        guard let layoutManager, let textContainer else { return nil }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        return rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    /// Checks if the element needs an inline popover and shows it. Returns true if handled.
    private func showElementPopover(_ element: InteractiveElement, optionIndex: Int?, at charRange: NSRange) -> Bool {
        switch element {
        case .fillIn(let fi):
            switch fi.type {
            case .text:
                showInputPopover(for: element, at: charRange, config: InputPopoverConfig(
                    title: "Fill In",
                    subtitle: fi.hint,
                    fieldName: "value",
                    placeholder: fi.hint,
                    initialValue: fi.value ?? ""
                ))
                return true
            case .date:
                showDatePickerPopover(for: element, at: charRange)
                return true
            case .file, .folder:
                return false // NSOpenPanel handled by callback
            }

        case .feedback(let fb):
            showInputPopover(for: element, at: charRange, config: InputPopoverConfig(
                title: fb.existingText != nil ? "Edit Feedback" : "Leave Feedback",
                subtitle: "Your comment will be saved in the document.",
                fieldName: "text",
                initialValue: fb.existingText ?? "",
                multiline: true
            ))
            return true

        case .suggestion(let s):
            showSuggestionPopover(for: element, suggestion: s, at: charRange)
            return true

        case .review(let rv):
            guard let optionIndex, optionIndex < rv.options.count else { return false }
            if rv.options[optionIndex].status.promptsForNotes {
                showInputPopover(for: element, at: charRange, config: InputPopoverConfig(
                    title: "Review: \(rv.options[optionIndex].status.rawValue)",
                    subtitle: "Add notes for this review status.",
                    fieldName: "notes",
                    multiline: true,
                    allowEmpty: true
                ), optionIndex: optionIndex)
                return true
            }
            return false

        case .confidence(let conf):
            if conf.level == .low {
                showInputPopover(for: element, at: charRange, config: InputPopoverConfig(
                    title: "Challenge AI Confidence",
                    subtitle: "Explain why you disagree with this assessment.",
                    fieldName: "challenge",
                    multiline: true
                ))
                return true
            }
            return false

        default:
            return false
        }
    }

    // MARK: - Input Popover

    /// Shows an inline text input popover at the element's position.
    private func showInputPopover(for element: InteractiveElement, at charRange: NSRange, config: InputPopoverConfig, optionIndex: Int? = nil) {
        inputPopover?.close()

        let popover = NSPopover()
        popover.behavior = .transient

        let controller = InputPopoverController(config: config) { [weak self] value in
            self?.inputPopover?.close()
            self?.inputPopover = nil
            self?.onInputSubmitted?(element, optionIndex, config.fieldName, value)
        } onCancel: { [weak self] in
            self?.inputPopover?.close()
            self?.inputPopover = nil
        }
        popover.contentViewController = controller

        guard let positionRect = glyphRect(for: charRange) else { return }
        inputPopover = popover
        popover.show(relativeTo: positionRect, of: self, preferredEdge: .maxY)
    }

    // MARK: - Date Picker Popover

    /// Shows a graphical date picker popover at the element's position.
    private func showDatePickerPopover(for element: InteractiveElement, at charRange: NSRange) {
        inputPopover?.close()

        let popover = NSPopover()
        popover.behavior = .transient

        let controller = DatePickerPopoverController(
            onSubmit: { [weak self] dateString in
                self?.inputPopover?.close()
                self?.inputPopover = nil
                self?.onInputSubmitted?(element, nil, "value", dateString)
            },
            onCancel: { [weak self] in
                self?.inputPopover?.close()
                self?.inputPopover = nil
            }
        )
        popover.contentViewController = controller

        guard let positionRect = glyphRect(for: charRange) else { return }
        inputPopover = popover
        popover.show(relativeTo: positionRect, of: self, preferredEdge: .maxY)
    }

    // MARK: - Suggestion Popover

    /// Shows an accept/reject popover for CriticMarkup suggestions.
    private func showSuggestionPopover(for element: InteractiveElement, suggestion: SuggestionElement, at charRange: NSRange) {
        inputPopover?.close()

        let popover = NSPopover()
        popover.behavior = .transient

        let controller = SuggestionPopoverController(
            suggestion: suggestion,
            onAccept: { [weak self] in
                self?.inputPopover?.close()
                self?.inputPopover = nil
                self?.onInputSubmitted?(element, nil, "action", "accept")
            },
            onReject: { [weak self] in
                self?.inputPopover?.close()
                self?.inputPopover = nil
                self?.onInputSubmitted?(element, nil, "action", "reject")
            },
            onCancel: { [weak self] in
                self?.inputPopover?.close()
                self?.inputPopover = nil
            }
        )
        popover.contentViewController = controller

        guard let positionRect = glyphRect(for: charRange) else { return }
        inputPopover = popover
        popover.show(relativeTo: positionRect, of: self, preferredEdge: .maxY)
    }

    // MARK: - Tab Navigation

    override func keyDown(with event: NSEvent) {
        // Tab / Shift-Tab navigates between interactive elements
        if event.keyCode == 48 { // Tab key
            let forward = !event.modifierFlags.contains(.shift)
            navigateToElement(forward: forward)
            return
        }
        // Return/Space activates the focused element
        if focusedElementRange != nil && (event.keyCode == 36 || event.keyCode == 49) {
            activateFocusedElement()
            return
        }
        super.keyDown(with: event)
    }

    /// Moves focus to the next (or previous) interactive element and scrolls to it.
    func navigateToElement(forward: Bool) {
        guard let textStorage else { return }
        let length = textStorage.length
        guard length > 0 else { return }

        // Collect all interactive element ranges
        var elementRanges: [NSRange] = []
        textStorage.enumerateAttribute(.interactiveElement, in: NSRange(location: 0, length: length)) { value, range, _ in
            guard value != nil else { return }
            elementRanges.append(range)
        }
        guard !elementRanges.isEmpty else { return }

        // Find the next element after the current focus
        let currentEnd = focusedElementRange.map { $0.location + $0.length } ?? 0
        let currentStart = focusedElementRange?.location ?? length

        let targetRange: NSRange
        if forward {
            targetRange = elementRanges.first(where: { $0.location > currentEnd - 1 && $0 != focusedElementRange })
                ?? elementRanges[0] // Wrap around (safe: guard ensures non-empty)
        } else {
            targetRange = elementRanges.last(where: { $0.location < currentStart && $0 != focusedElementRange })
                ?? elementRanges[elementRanges.count - 1] // Wrap around
        }

        // Clear old focus highlight
        clearFocusHighlight()

        // Set new focus and request redraw for focus ring
        focusedElementRange = targetRange
        needsDisplay = true

        // Scroll to show the focused element
        scrollRangeToVisible(targetRange)

        // VoiceOver: announce the focused element's tooltip
        if let tooltip = textStorage.attribute(.toolTip, at: targetRange.location, effectiveRange: nil) as? String {
            NSAccessibility.post(
                element: self,
                notification: .announcementRequested,
                userInfo: [NSAccessibility.NotificationUserInfoKey.announcement: tooltip]
            )
        }
    }

    /// Activates (clicks) the currently focused interactive element.
    private func activateFocusedElement() {
        guard let focusedElementRange,
              let wrapper = textStorage?.attribute(.interactiveElement, at: focusedElementRange.location, effectiveRange: nil) as? InteractiveElementWrapper else { return }
        flashClickFeedback(range: focusedElementRange)

        // Calculate a point within the element for the callback (in view coordinates)
        let origin = textContainerOrigin
        let point: NSPoint
        if let layoutManager, let textContainer {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: focusedElementRange, actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            point = NSPoint(x: rect.midX + origin.x, y: rect.midY + origin.y)
        } else {
            point = NSPoint(x: origin.x, y: origin.y)
        }

        onInteractiveElementClicked?(wrapper.element, wrapper.optionIndex, point)
    }

    func clearFocusHighlight() {
        guard focusedElementRange != nil else { return }
        focusedElementRange = nil
        needsDisplay = true
    }

    // MARK: - Drawing (Focus Ring only — line numbers handled by GutterOverlayView)

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw focus ring around Tab-focused interactive element
        guard let focusedElementRange, let layoutManager, let textContainer else { return }
        // Guard against stale range after text storage replacement
        guard focusedElementRange.location + focusedElementRange.length <= (textStorage?.length ?? 0) else { return }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: focusedElementRange, actualCharacterRange: nil)
        var focusRects: [NSRect] = []
        layoutManager.enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: textContainer) { rect, _ in
            focusRects.append(rect)
        }

        guard !focusRects.isEmpty else { return }

        // Union all rects into a single bounding rect, offset by text container origin
        let origin = textContainerOrigin
        var unionRect = focusRects[0]
        for rect in focusRects.dropFirst() {
            unionRect = unionRect.union(rect)
        }
        unionRect = unionRect.offsetBy(dx: origin.x, dy: origin.y)

        // Draw rounded focus ring (stronger in high-contrast mode)
        NSGraphicsContext.saveGraphicsState()
        let ringRect = unionRect.insetBy(dx: -3, dy: -2)
        let ringPath = NSBezierPath(roundedRect: ringRect, xRadius: 4, yRadius: 4)
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        NSColor.controlAccentColor.withAlphaComponent(highContrast ? 0.6 : 0.3).setStroke()
        NSColor.controlAccentColor.withAlphaComponent(highContrast ? 0.12 : 0.06).setFill()
        ringPath.lineWidth = highContrast ? 3 : 2
        ringPath.fill()
        ringPath.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    // (Line number drawing moved to GutterOverlayView — a sibling view that can't be covered)

    // MARK: - Cursor Rects

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let textStorage, let layoutManager, let textContainer else { return }

        // Offset from text container coords to view coords
        let origin = textContainerOrigin

        // Add pointing hand cursor over interactive elements
        textStorage.enumerateAttribute(.interactiveElement, in: NSRange(location: 0, length: textStorage.length)) { value, range, _ in
            guard value != nil else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: textContainer) { rect, _ in
                self.addCursorRect(rect.offsetBy(dx: origin.x, dy: origin.y), cursor: .pointingHand)
            }
        }
    }
}

/// Wrapper to store InteractiveElement as an NSAttributedString attribute value (must be a class).
final class InteractiveElementWrapper: NSObject {
    let element: InteractiveElement
    /// For choice/review elements, which option index this click area represents
    let optionIndex: Int?

    init(_ element: InteractiveElement, optionIndex: Int? = nil) {
        self.element = element
        self.optionIndex = optionIndex
    }
}

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
    var onToggleBookmark: ((Int) -> Void)?

    var lineNumberFont: NSFont = .monospacedDigitSystemFont(ofSize: 10, weight: .regular) {
        didSet { needsDisplay = true }
    }

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
                let numStr = "\(lineNumber)" as NSString
                let color = isBookmarked ? NSColor.systemOrange : lineNumberColor
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: lineNumberFont,
                    .foregroundColor: color
                ]
                let size = numStr.size(withAttributes: attrs)
                let x = gutterContentWidth - size.width
                let y = yInGutter + (lineRect.height - size.height) / 2
                numStr.draw(at: NSPoint(x: max(4, x), y: y), withAttributes: attrs)

                // Bookmark indicator dot
                if isBookmarked {
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

    // MARK: - Gutter Click (Bookmark Toggle)

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

        onToggleBookmark?(lineNum)
    }
}

// MARK: - Markdown Editor

/// NSTextView wrapper with Markdown syntax highlighting.
/// Now uses aimdRenderer's SyntaxTheme system through SettingsRepository.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    @Environment(\.settings) private var settings

    /// Callback for reporting errors (optional)
    var onError: ((AppError) -> Void)? = nil

    /// Callback when scroll position changes (0.0–1.0)
    var onScrollPositionChanged: ((Double) -> Void)? = nil

    /// Scroll position to restore (0.0–1.0), set once after content loads
    var restoreScrollPosition: Double? = nil

    /// Bookmarked line numbers (1-based) to display in the gutter
    var bookmarkedLines: Set<Int> = []

    /// Called when user clicks gutter to toggle a bookmark at a line
    var onToggleBookmark: ((Int) -> Void)? = nil

    /// Callback when an interactive element is clicked (element, optionIndex, point)
    var onInteractiveElementClicked: ((InteractiveElement, Int?, NSPoint) -> Void)? = nil

    /// Callback when a status state is selected via native dropdown (status, selected state)
    var onStatusSelected: ((StatusElement, String) -> Void)? = nil

    /// Callback when a popover-based input is submitted (element, optionIndex, fieldName, value)
    var onInputSubmitted: ((InteractiveElement, Int?, String, String) -> Void)? = nil

    func makeNSView(context: Context) -> NSView {
        // Container: gutter (left) + scroll view (right), side by side via Auto Layout.
        // Gutter is a sibling, not a child of the scroll view — no z-order conflicts.
        let container = NSView()

        // --- Text system ---
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.addTextContainer(textContainer)

        let textView = MarkdownNSTextView(frame: .zero, textContainer: textContainer)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        // --- Scroll view ---
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        // Configure text view (read-only viewer)
        textView.isEditable = false
        textView.isRichText = false

        // Theme colors
        let syntaxTheme = settings.rendering.syntaxTheme.rendererTheme(for: settings.appearance.colorScheme)
        let palette = syntaxTheme.palette
        let fontSize = settings.rendering.fontSize
        textView.font = MarkdownHighlighter.resolveFont(family: settings.rendering.fontFamily, size: fontSize, weight: .regular)
        textView.textColor = NSColor(hex: palette.foreground) ?? .labelColor
        textView.backgroundColor = NSColor(hex: palette.background) ?? .textBackgroundColor
        textView.insertionPointColor = NSColor(hex: palette.foreground) ?? .labelColor
        textView.usesAdaptiveColorMappingForDarkAppearance = false

        // Uniform padding (no gutter space — gutter is a separate sibling view)
        let insetScale = max(1.0, fontSize / 14.0)
        let scaledInset = round(16.0 * insetScale)
        textView.textContainerInset = NSSize(width: scaledInset, height: scaledInset)

        // Native find bar
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        // Link appearance
        var linkAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor(hex: palette.function) ?? .systemTeal,
            .cursor: NSCursor.pointingHand
        ]
        if settings.behavior.underlineLinks {
            linkAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        textView.linkTextAttributes = linkAttrs

        // Accessibility
        textView.setAccessibilityElement(true)
        textView.setAccessibilityLabel("Markdown document viewer")
        textView.setAccessibilityRole(.textArea)
        textView.setAccessibilityHelp("Read-only markdown content with syntax highlighting. Use Cmd+F to search.")

        // Delegate
        textView.delegate = context.coordinator

        // --- Gutter (sibling of scroll view) ---
        let gutterView = GutterOverlayView()
        gutterView.textView = textView
        gutterView.gutterBackground = textView.backgroundColor
        gutterView.lineNumberColor = NSColor(hex: palette.comment) ?? NSColor(hex: palette.lineNumber) ?? .secondaryLabelColor
        gutterView.bookmarkedLines = bookmarkedLines
        gutterView.onToggleBookmark = onToggleBookmark
        let lineNumFontSize = max(9, round(fontSize * 0.78))
        gutterView.lineNumberFont = .monospacedDigitSystemFont(ofSize: lineNumFontSize, weight: .regular)

        // --- Layout: [gutter | scrollView] ---
        gutterView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(gutterView)
        container.addSubview(scrollView)

        let showGutter = settings.rendering.showLineNumbers
        let gutterWidthConstraint = gutterView.widthAnchor.constraint(
            equalToConstant: showGutter ? MarkdownNSTextView.gutterWidth : 0
        )

        NSLayoutConstraint.activate([
            gutterView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            gutterView.topAnchor.constraint(equalTo: container.topAnchor),
            gutterView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            gutterWidthConstraint,

            scrollView.leadingAnchor.constraint(equalTo: gutterView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        // Store references in coordinator
        context.coordinator.scrollView = scrollView
        context.coordinator.gutterView = gutterView
        context.coordinator.gutterWidthConstraint = gutterWidthConstraint

        // Scroll position tracking
        context.coordinator.onScrollPositionChanged = onScrollPositionChanged
        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )

        // Interactive element click handler
        let coordinator = context.coordinator
        textView.onInteractiveElementClicked = { element, optionIndex, point in
            coordinator.parent.onInteractiveElementClicked?(element, optionIndex, point)
        }
        textView.onStatusSelected = { status, state in
            coordinator.parent.onStatusSelected?(status, state)
        }
        textView.onInputSubmitted = { element, optionIndex, fieldName, value in
            coordinator.parent.onInputSubmitted?(element, optionIndex, fieldName, value)
        }

        // Initial content
        context.coordinator.interactiveMode = settings.behavior.interactiveMode
        context.coordinator.applyHighlighting(to: textView, text: text)

        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let scrollView = context.coordinator.scrollView,
              let textView = scrollView.documentView as? NSTextView else { return }

        let currentFontSize = settings.rendering.fontSize
        let currentTheme = settings.rendering.syntaxTheme
        let currentFontFamily = settings.rendering.fontFamily
        let currentHeadingScale = settings.rendering.headingScale
        let currentColorScheme = settings.appearance.colorScheme
        let currentInteractiveMode = settings.behavior.interactiveMode

        // Check if any rendering settings changed
        let fontChanged = context.coordinator.fontSize != currentFontSize
        let themeChanged = context.coordinator.syntaxTheme != currentTheme
        let fontFamilyChanged = context.coordinator.fontFamily != currentFontFamily
        let headingScaleChanged = context.coordinator.headingScale != currentHeadingScale
        let appearanceChanged = context.coordinator.colorScheme != currentColorScheme
        let interactiveModeChanged = context.coordinator.interactiveMode != currentInteractiveMode

        if fontChanged || themeChanged || fontFamilyChanged || headingScaleChanged || appearanceChanged || interactiveModeChanged {
            context.coordinator.interactiveMode = currentInteractiveMode
            context.coordinator.updateSettings(fontSize: currentFontSize, theme: currentTheme, fontFamily: currentFontFamily, headingScale: currentHeadingScale, colorScheme: currentColorScheme)

            let palette = currentTheme.rendererTheme(for: currentColorScheme).palette
            textView.textColor = NSColor(hex: palette.foreground) ?? .labelColor
            textView.backgroundColor = NSColor(hex: palette.background) ?? .textBackgroundColor
            textView.insertionPointColor = NSColor(hex: palette.foreground) ?? .labelColor

            var linkAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor(hex: palette.function) ?? .systemTeal,
                .cursor: NSCursor.pointingHand
            ]
            if settings.behavior.underlineLinks {
                linkAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            textView.linkTextAttributes = linkAttrs

            context.coordinator.applyHighlighting(to: textView, text: text)
        }

        // Re-apply highlighting if text changed externally
        else if context.coordinator.lastAppliedText != text {
            context.coordinator.applyHighlighting(to: textView, text: text)

            if let position = restoreScrollPosition {
                context.coordinator.restoreScrollPosition(position, in: scrollView)
            }
        }

        // Update callback references
        context.coordinator.onScrollPositionChanged = onScrollPositionChanged
        if let tv = textView as? MarkdownNSTextView {
            let coordinator = context.coordinator
            tv.onInteractiveElementClicked = { element, optionIndex, point in
                coordinator.parent.onInteractiveElementClicked?(element, optionIndex, point)
            }
            tv.onStatusSelected = { status, state in
                coordinator.parent.onStatusSelected?(status, state)
            }
            tv.onInputSubmitted = { element, optionIndex, fieldName, value in
                coordinator.parent.onInputSubmitted?(element, optionIndex, fieldName, value)
            }
        }

        // Update text view inset (uniform — gutter is separate)
        let insetScale = max(1.0, currentFontSize / 14.0)
        let scaledInset = round(16.0 * insetScale)
        textView.textContainerInset = NSSize(width: scaledInset, height: scaledInset)

        // Update gutter
        if let gutterView = context.coordinator.gutterView {
            let palette = currentTheme.rendererTheme(for: currentColorScheme).palette
            gutterView.gutterBackground = NSColor(hex: palette.background) ?? .textBackgroundColor
            gutterView.lineNumberColor = NSColor(hex: palette.comment) ?? NSColor(hex: palette.lineNumber) ?? .secondaryLabelColor
            gutterView.bookmarkedLines = bookmarkedLines
            gutterView.onToggleBookmark = onToggleBookmark
            let lineNumFontSize = max(9, round(currentFontSize * 0.78))
            gutterView.lineNumberFont = .monospacedDigitSystemFont(ofSize: lineNumFontSize, weight: .regular)

            // Toggle gutter visibility via constraint
            let showGutter = settings.rendering.showLineNumbers
            context.coordinator.gutterWidthConstraint?.constant = showGutter ? MarkdownNSTextView.gutterWidth : 0
            gutterView.needsDisplay = true
        }
    }

    static func dismantleNSView(_ container: NSView, coordinator: Coordinator) {
        if let scrollView = coordinator.scrollView,
           let textView = scrollView.documentView as? NSTextView {
            textView.delegate = nil
        }
        NotificationCenter.default.removeObserver(coordinator)
        coordinator.scrollView = nil
        coordinator.gutterView = nil
    }

    func makeCoordinator() -> Coordinator {
        let fontSize = settings.rendering.fontSize
        let syntaxTheme = settings.rendering.syntaxTheme
        let fontFamily = settings.rendering.fontFamily
        let headingScale = settings.rendering.headingScale
        let colorScheme = settings.appearance.colorScheme
        return Coordinator(self, fontSize: fontSize, syntaxTheme: syntaxTheme, fontFamily: fontFamily, headingScale: headingScale, colorScheme: colorScheme, onError: onError)
    }

    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        private var debouncedHighlighter: DebouncedHighlighter
        private var isUpdating = false
        var onScrollPositionChanged: ((Double) -> Void)?
        weak var scrollView: NSScrollView?
        weak var gutterView: GutterOverlayView?
        var gutterWidthConstraint: NSLayoutConstraint?
        var fontSize: CGFloat
        var syntaxTheme: SyntaxThemeSetting
        var fontFamily: String?
        var headingScale: HeadingScaleSetting
        var colorScheme: ColorScheme?
        var interactiveMode: InteractiveMode = .enhanced
        var onError: ((AppError) -> Void)?
        /// The source text that was last applied to highlighting.
        /// Used instead of textView.string comparison because native indicator
        /// replacements (SF Symbol attachments) mutate the displayed string.
        private(set) var lastAppliedText: String = ""

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        init(_ parent: MarkdownEditor, fontSize: CGFloat, syntaxTheme: SyntaxThemeSetting, fontFamily: String? = nil, headingScale: HeadingScaleSetting = .normal, colorScheme: ColorScheme? = nil, onError: ((AppError) -> Void)? = nil) {
            self.parent = parent
            self.fontSize = fontSize
            self.syntaxTheme = syntaxTheme
            self.fontFamily = fontFamily
            self.headingScale = headingScale
            self.colorScheme = colorScheme
            self.onError = onError
            let resolved = syntaxTheme.rendererTheme(for: colorScheme)
            let highlighter = MarkdownHighlighter(syntaxTheme: resolved, fontSize: fontSize, fontFamily: fontFamily, headingScale: headingScale.highlighterScale)
            self.debouncedHighlighter = DebouncedHighlighter(highlighter: highlighter, debounceDelay: .milliseconds(150))
        }

        func updateSettings(fontSize: CGFloat, theme: SyntaxThemeSetting, fontFamily: String? = nil, headingScale: HeadingScaleSetting = .normal, colorScheme: ColorScheme? = nil) {
            self.fontSize = fontSize
            self.syntaxTheme = theme
            self.fontFamily = fontFamily
            self.headingScale = headingScale
            self.colorScheme = colorScheme
            let resolved = theme.rendererTheme(for: colorScheme)
            let newHighlighter = MarkdownHighlighter(syntaxTheme: resolved, fontSize: fontSize, fontFamily: fontFamily, headingScale: headingScale.highlighterScale)
            debouncedHighlighter = DebouncedHighlighter(highlighter: newHighlighter, debounceDelay: .milliseconds(150))
        }

        func applyHighlighting(to textView: NSTextView, text: String) {
            guard !isUpdating else { return }

            // Security: Prevent DoS from extremely large files
            guard text.utf8.count <= MarkdownConfig.maxTextSize else {
                onError?(.textSizeExceeded)
                return
            }

            isUpdating = true
            lastAppliedText = text
            // Clear focus and hover state since text storage is being replaced
            if let mdTextView = textView as? MarkdownNSTextView {
                mdTextView.clearFocusHighlight()
                mdTextView.clearHover()
            }
            let selectedRanges = textView.selectedRanges
            // Save scroll position before replacing text storage
            let scrollOrigin = textView.enclosingScrollView?.contentView.bounds.origin

            // Highlight synchronously — the debounced highlighter already coalesces rapid updates.
            // NSAttributedString isn't Sendable on macOS, so offloading to Task.detached
            // would require unsafe transfers. Highlighting is fast enough on-main-actor.
            let attributed = debouncedHighlighter.highlighter.highlight(text)

            // Detect and annotate interactive elements + progress bars
            let elements = InteractiveElementDetector.detect(in: text)
            let mutable = NSMutableAttributedString(attributedString: attributed)
            if !elements.isEmpty {
                let isEnhanced = interactiveMode == .enhanced || interactiveMode == .hybrid
                let annotator = debouncedHighlighter.highlighter.makeAnnotator()
                annotator.annotateInteractiveElements(mutable, elements: elements, text: text, enhanced: isEnhanced)

                // Add progress bars to section headings (only in enhanced mode)
                if isEnhanced {
                    let structure = MarkdownStructureParser.parse(text: text)
                    annotator.annotateProgressBars(mutable, structure: structure, text: text)
                }
            }
            textView.textStorage?.setAttributedString(mutable)

            textView.selectedRanges = selectedRanges
            
            // Restore scroll position — setAttributedString can reset the scroll view.
            // Defer to next run loop to ensure layout is complete and prevent SwiftUI from overriding.
            if let origin = scrollOrigin, let scrollView = textView.enclosingScrollView {
                DispatchQueue.main.async {
                    scrollView.contentView.scroll(to: origin)
                }
            }
            
            // Reset cursor rects so interactive elements get pointing hand
            textView.window?.invalidateCursorRects(for: textView)
            // Redraw gutter after content change
            gutterView?.needsDisplay = true
            isUpdating = false
        }

        nonisolated func textDidChange(_ notification: Notification) {
            // Extract NSTextView before crossing isolation boundary
            guard let textView = notification.object as? NSTextView else { return }

            // AppKit always calls delegate methods on the main thread,
            // so we can safely assume MainActor isolation
            MainActor.assumeIsolated {
                guard !isUpdating else { return }

                let textContent = textView.string

                // Security: Prevent DoS from extremely large files
                guard textContent.utf8.count <= MarkdownConfig.maxTextSize else {
                    onError?(.textSizeExceeded)
                    return
                }

                // Update parent binding synchronously (no Task overhead)
                parent.text = textContent

                // Use debounced highlighting for better performance
                debouncedHighlighter.highlightDebounced(textContent) { [weak self, weak textView] attributed in
                    guard let self, let textView else { return }
                    guard !self.isUpdating else { return }

                    self.isUpdating = true
                    defer { self.isUpdating = false }

                    let selectedRanges = textView.selectedRanges
                    textView.textStorage?.setAttributedString(attributed)
                    textView.selectedRanges = selectedRanges
                }
            }
        }

        // MARK: - Link Handling

        nonisolated func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL else { return false }

            return MainActor.assumeIsolated {
                if url.scheme == nil, let fragment = url.fragment {
                    // Fragment-only link (e.g. #heading) — scroll to matching heading
                    scrollToHeading(fragment: fragment, in: textView)
                    return true
                } else if url.scheme != nil {
                    // External link — open in default browser
                    NSWorkspace.shared.open(url)
                    return true
                }
                // Malformed link (no scheme, no fragment) — ignore gracefully
                return false
            }
        }

        /// Scrolls to the heading whose GitHub-style slug matches the given fragment.
        private func scrollToHeading(fragment: String, in textView: NSTextView) {
            let text = textView.string
            let lines = text.components(separatedBy: .newlines)
            var searchOffset = 0

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") {
                    // Strip leading # characters and whitespace to get heading text
                    let headingText = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                    if Self.slugify(headingText) == fragment.lowercased() {
                        let nsString = text as NSString
                        let lineRange = nsString.range(of: line, range: NSRange(location: searchOffset, length: nsString.length - searchOffset))
                        guard lineRange.location != NSNotFound else { continue }

                        textView.scrollRangeToVisible(lineRange)
                        textView.showFindIndicator(for: lineRange)
                        return
                    }
                }
                // Advance offset past this line + newline
                searchOffset += line.utf16.count + 1
            }
        }

        /// Converts heading text to a GitHub-style slug for anchor matching.
        /// Lowercases, replaces spaces with hyphens, strips non-alphanumeric (except hyphens).
        static func slugify(_ text: String) -> String {
            text.lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .unicodeScalars
                .filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" }
                .reduce(into: "") { $0.unicodeScalars.append($1) }
        }

        // MARK: - Scroll Position

        @objc nonisolated func scrollViewDidScroll(_ notification: Notification) {
            // AppKit delivers boundsDidChange on the main thread.
            // nonisolated(unsafe) required: notification.object is Any? (not Sendable),
            // but we immediately enter MainActor.assumeIsolated — no actual cross-thread access.
            nonisolated(unsafe) let object = notification.object
            MainActor.assumeIsolated {
                guard let clipView = object as? NSClipView,
                      let documentView = clipView.documentView else { return }

                let contentHeight = documentView.frame.height
                let visibleHeight = clipView.bounds.height
                let scrollableHeight = contentHeight - visibleHeight
                guard scrollableHeight > 0 else { return }

                let position = clipView.bounds.origin.y / scrollableHeight
                let clamped = min(max(position, 0.0), 1.0)
                onScrollPositionChanged?(clamped)

                // Redraw gutter line numbers for new scroll position
                gutterView?.needsDisplay = true
            }
        }


        func restoreScrollPosition(_ position: Double, in scrollView: NSScrollView) {
            guard let documentView = scrollView.documentView else { return }

            // Defer to next layout pass so text is fully laid out
            Task { @MainActor in
                let contentHeight = documentView.frame.height
                let visibleHeight = scrollView.contentView.bounds.height
                let scrollableHeight = contentHeight - visibleHeight
                guard scrollableHeight > 0 else { return }

                let yOffset = position * scrollableHeight
                documentView.scroll(NSPoint(x: 0, y: yOffset))
            }
        }
    }
}
