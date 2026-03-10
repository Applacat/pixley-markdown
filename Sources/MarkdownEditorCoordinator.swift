import SwiftUI
import AppKit
import aimdRenderer

// MARK: - Markdown Editor Coordinator

/// Coordinates between the SwiftUI `MarkdownEditor` and the underlying `MarkdownNSTextView`.
/// Handles syntax highlighting, interactive element annotation, scroll sync, and link navigation.
@MainActor
final class MarkdownEditorCoordinator: NSObject, NSTextViewDelegate {
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
    /// Deferred text when a popover was open during `applyHighlighting`.
    var pendingHighlightText: String?

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

    // MARK: - Highlighting

    func applyHighlighting(to textView: NSTextView, text: String) {
        guard !isUpdating else { return }

        // Don't replace text storage while a popover is open — the setAttributedString
        // call would dismiss a .transient popover immediately. Defer until popover closes.
        if let mdTV = textView as? MarkdownNSTextView, mdTV.inputPopover?.isShown == true {
            pendingHighlightText = text
            return
        }
        pendingHighlightText = nil

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

    // MARK: - Text Change

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
