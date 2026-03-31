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

    /// Callback for "Add Comment" action (selected text, selected range in text view).
    var onAddComment: ((String, NSRange) -> Void)?

    /// Tracks the selection popover work item to debounce
    private var selectionPopoverWorkItem: DispatchWorkItem?

    /// Active selection action popover
    private var selectionPopover: NSPopover?

    /// Selection length at mouseDown — used to detect drag-select vs click
    private var selectionLengthAtMouseDown: Int = 0

    /// Whether the mouse is currently down (to detect end of drag-select)
    private var isMouseDown = false

    /// Tracks the currently hovered interactive element range for hover highlight
    private var hoveredRange: NSRange?

    /// Pending status element for the native dropdown menu
    private var pendingStatusElement: StatusElement?

    /// Tracks the currently focused interactive element range (via Tab navigation)
    var focusedElementRange: NSRange?

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

        // Check if mouse is over an interactive element (scan full range across run boundaries)
        if let (_, fullRange) = fullInteractiveElementRange(at: charIndex) {
            // Only update if the hovered range changed
            if hoveredRange != fullRange {
                clearHoverHighlight()
                hoveredRange = fullRange
                // Temporary background highlight — overrides any permanent background during hover,
                // restores automatically when removed. The accent color signals "clickable."
                layoutManager.addTemporaryAttribute(
                    .backgroundColor,
                    value: NSColor.controlAccentColor.withAlphaComponent(0.12),
                    forCharacterRange: fullRange
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

    /// Finds the full range of an interactive element at `charIndex` by scanning adjacent runs.
    /// `effectiveRange` from `attribute(_:at:effectiveRange:)` only returns the current attribute run,
    /// which gets fragmented when other attributes (e.g. foregroundColor) change on subranges.
    private func fullInteractiveElementRange(at charIndex: Int) -> (InteractiveElementWrapper, NSRange)? {
        guard let textStorage, charIndex >= 0, charIndex < textStorage.length else { return nil }
        var runRange = NSRange()
        guard let wrapper = textStorage.attribute(.interactiveElement, at: charIndex, effectiveRange: &runRange) as? InteractiveElementWrapper else { return nil }

        var fullRange = runRange

        // Expand backwards through adjacent runs with the same element
        while fullRange.location > 0 {
            var prevRange = NSRange()
            if let prev = textStorage.attribute(.interactiveElement, at: fullRange.location - 1, effectiveRange: &prevRange) as? InteractiveElementWrapper,
               prev.isEqual(wrapper) {
                fullRange = NSUnionRange(fullRange, prevRange)
            } else {
                break
            }
        }

        // Expand forwards through adjacent runs with the same element
        while NSMaxRange(fullRange) < textStorage.length {
            var nextRange = NSRange()
            if let next = textStorage.attribute(.interactiveElement, at: NSMaxRange(fullRange), effectiveRange: &nextRange) as? InteractiveElementWrapper,
               next.isEqual(wrapper) {
                fullRange = NSUnionRange(fullRange, nextRange)
            } else {
                break
            }
        }

        return (wrapper, fullRange)
    }

    override func mouseDown(with event: NSEvent) {
        selectionLengthAtMouseDown = selectedRange().length
        isMouseDown = true
        selectionPopoverWorkItem?.cancel()
        selectionPopover?.close()
        selectionPopover = nil

        let point = convert(event.locationInWindow, from: nil)
        let charIndex = characterIndexForInsertion(at: point)

        guard charIndex >= 0, charIndex < textStorage?.length ?? 0 else {
            super.mouseDown(with: event)
            return
        }

        // Clear Tab-focus when clicking anywhere
        clearFocusHighlight()

        // Check if the click hit an interactive element (scan for full range across run boundaries)
        if let (wrapper, effectiveRange) = fullInteractiveElementRange(at: charIndex) {

            // Save scroll position before handling click to prevent unwanted scrolling
            let scrollView = enclosingScrollView
            let savedScrollOrigin = scrollView?.contentView.bounds.origin

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
            let popoverResult = showElementPopover(wrapper.element, optionIndex: wrapper.optionIndex, at: effectiveRange)
            if popoverResult {
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
        checkForNewSelectionPopover()
    }

    /// Flashes a brief accent highlight on the clicked element range for tactile feedback.
    /// Respects Reduce Motion accessibility setting.
    func flashClickFeedback(range: NSRange) {
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

    /// Active input popover (retained to prevent premature dealloc).
    /// Popover routing and show methods are in MarkdownTextViewPopovers.swift.
    var inputPopover: NSPopover?

    // MARK: - Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()

        // Add "Add Comment" when text is selected
        if selectedRange().length > 0 {
            let commentItem = NSMenuItem(title: "Add Comment", action: #selector(addCommentAction), keyEquivalent: "C")
            commentItem.keyEquivalentModifierMask = [.command, .shift]
            menu.insertItem(.separator(), at: 0)
            menu.insertItem(commentItem, at: 0)
        }

        return menu
    }

    @objc private func addCommentAction() {
        let range = selectedRange()
        guard range.length > 0,
              let text = textStorage?.string,
              let swiftRange = Range(range, in: text) else { return }
        let selectedText = String(text[swiftRange])
        onAddComment?(selectedText, range)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        isMouseDown = false
        checkForNewSelectionPopover()
    }

    /// Checks if a text selection was created or expanded and shows the "Add Comment" popover.
    private func checkForNewSelectionPopover() {
        let range = selectedRange()
        guard range.length > 0, range.length != selectionLengthAtMouseDown else { return }
        // Avoid showing twice (mouseDown tracking loop + mouseUp both call this)
        guard selectionPopover == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            self?.showSelectionActionPopover(for: range)
        }
        selectionPopoverWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    // MARK: - Selection Action Popover

    private func showSelectionActionPopover(for range: NSRange) {
        guard range.length > 0, let positionRect = glyphRect(for: range) else { return }

        let popover = NSPopover()
        popover.behavior = .transient

        let button = NSButton(title: "Add Comment", target: self, action: #selector(selectionPopoverAddComment))
        button.bezelStyle = .toolbar
        button.isBordered = false
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.contentTintColor = .labelColor

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 28))
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        let vc = NSViewController()
        vc.view = container
        popover.contentViewController = vc

        selectionPopover = popover
        popover.show(relativeTo: positionRect, of: self, preferredEdge: .minY)
    }

    @objc private func selectionPopoverAddComment() {
        selectionPopover?.close()
        selectionPopover = nil
        addCommentAction()
    }

    // MARK: - Keyboard Navigation

    override func keyDown(with event: NSEvent) {
        // Cmd+Shift+C: Add Comment
        if event.modifierFlags.contains([.command, .shift]),
           event.charactersIgnoringModifiers == "c" {
            addCommentAction()
            return
        }
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

    // MARK: - Drawing (Focus Ring)

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawFocusRing(dirtyRect)
    }

    // MARK: - Cursor Rects

    override func resetCursorRects() {
        super.resetCursorRects()
        updateInteractiveCursorRects()
    }
}

/// Wrapper to store InteractiveElement as an NSAttributedString attribute value (must be a class).
/// Overrides `isEqual:` and `hash` so that NSAttributedString coalesces effective ranges
/// across run boundaries (e.g. when delimiter subranges get a separate foregroundColor).
final class InteractiveElementWrapper: NSObject {
    let element: InteractiveElement
    /// For choice/review elements, which option index this click area represents
    let optionIndex: Int?

    init(_ element: InteractiveElement, optionIndex: Int? = nil) {
        self.element = element
        self.optionIndex = optionIndex
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? InteractiveElementWrapper else { return false }
        return element.id == other.element.id
            && optionIndex == other.optionIndex
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(element.id)
        hasher.combine(optionIndex)
        return hasher.finalize()
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

    /// Lines that have a `<!-- feedback -->` comment on the next line
    var commentedLines: Set<Int> = []

    /// Called when gutter popover submits (lineNumber, shouldBookmark, commentText-or-nil)
    var onGutterAction: ((Int, Bool, String?) -> Void)? = nil

    /// Callback when an interactive element is clicked (element, optionIndex, point)
    var onInteractiveElementClicked: ((InteractiveElement, Int?, NSPoint) -> Void)? = nil

    /// Callback when a status state is selected via native dropdown (status, selected state)
    var onStatusSelected: ((StatusElement, String) -> Void)? = nil

    /// Callback when a popover-based input is submitted (element, optionIndex, fieldName, value)
    var onInputSubmitted: ((InteractiveElement, Int?, String, String) -> Void)? = nil

    /// Callback when user triggers "Add Comment" on selected text (selectedText, range)
    var onAddComment: ((String, NSRange) -> Void)? = nil

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
        gutterView.commentedLines = commentedLines
        gutterView.onToggleBookmark = onToggleBookmark
        gutterView.onGutterAction = onGutterAction
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
            selector: #selector(MarkdownEditorCoordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )

        // Interactive element click handler — weak coordinator to avoid delaying deallocation
        let coordinator = context.coordinator
        textView.onInteractiveElementClicked = { [weak coordinator] element, optionIndex, point in
            coordinator?.parent.onInteractiveElementClicked?(element, optionIndex, point)
        }
        textView.onStatusSelected = { [weak coordinator] status, state in
            coordinator?.parent.onStatusSelected?(status, state)
        }
        textView.onInputSubmitted = { [weak coordinator] element, optionIndex, fieldName, value in
            coordinator?.parent.onInputSubmitted?(element, optionIndex, fieldName, value)
        }
        textView.onAddComment = { [weak coordinator] selectedText, range in
            coordinator?.parent.onAddComment?(selectedText, range)
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

        // Flush deferred highlighting once the popover has closed
        if let pending = context.coordinator.pendingHighlightText,
           (textView as? MarkdownNSTextView)?.inputPopover?.isShown != true {
            context.coordinator.applyHighlighting(to: textView, text: pending)
        }

        // Update callback references — weak coordinator to avoid delaying deallocation
        context.coordinator.onScrollPositionChanged = onScrollPositionChanged
        if let tv = textView as? MarkdownNSTextView {
            let coordinator = context.coordinator
            tv.onInteractiveElementClicked = { [weak coordinator] element, optionIndex, point in
                coordinator?.parent.onInteractiveElementClicked?(element, optionIndex, point)
            }
            tv.onStatusSelected = { [weak coordinator] status, state in
                coordinator?.parent.onStatusSelected?(status, state)
            }
            tv.onInputSubmitted = { [weak coordinator] element, optionIndex, fieldName, value in
                coordinator?.parent.onInputSubmitted?(element, optionIndex, fieldName, value)
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
            gutterView.commentedLines = commentedLines
            gutterView.onToggleBookmark = onToggleBookmark
            gutterView.onGutterAction = onGutterAction
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
           let textView = scrollView.documentView as? MarkdownNSTextView {
            textView.delegate = nil
            textView.onInteractiveElementClicked = nil
            textView.onStatusSelected = nil
            textView.onInputSubmitted = nil
            textView.onAddComment = nil
        }
        NotificationCenter.default.removeObserver(coordinator)
        coordinator.scrollView = nil
        coordinator.gutterView = nil
    }

    typealias Coordinator = MarkdownEditorCoordinator

    func makeCoordinator() -> Coordinator {
        let fontSize = settings.rendering.fontSize
        let syntaxTheme = settings.rendering.syntaxTheme
        let fontFamily = settings.rendering.fontFamily
        let headingScale = settings.rendering.headingScale
        let colorScheme = settings.appearance.colorScheme
        return Coordinator(self, fontSize: fontSize, syntaxTheme: syntaxTheme, fontFamily: fontFamily, headingScale: headingScale, colorScheme: colorScheme, onError: onError)
    }
}
