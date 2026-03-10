import AppKit
import aimdRenderer

// MARK: - Tab Navigation, Focus Ring Drawing, Cursor Rects

/// Extension extracting keyboard navigation, focus ring drawing, and cursor rects
/// from MarkdownNSTextView. Keeps the main file focused on mouse/hover event handling.
extension MarkdownNSTextView {

    // MARK: - Tab Navigation

    /// Moves focus to the next (or previous) interactive element and scrolls to it.
    func navigateToElement(forward: Bool) {
        guard let textStorage else { return }
        let length = textStorage.length
        guard length > 0 else { return }

        // Collect all interactive element ranges, merging fragmented runs
        // (fill-in elements have split runs due to hidden bracket foreground colors)
        var elementRanges: [NSRange] = []
        textStorage.enumerateAttribute(.interactiveElement, in: NSRange(location: 0, length: length)) { value, range, _ in
            guard let wrapper = value as? InteractiveElementWrapper else { return }
            // Merge with previous range if same element (adjacent run)
            if let last = elementRanges.last,
               NSMaxRange(last) == range.location,
               let prevWrapper = textStorage.attribute(.interactiveElement, at: last.location, effectiveRange: nil) as? InteractiveElementWrapper,
               prevWrapper.isEqual(wrapper) {
                elementRanges[elementRanges.count - 1] = NSUnionRange(last, range)
            } else {
                elementRanges.append(range)
            }
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
    func activateFocusedElement() {
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

    // MARK: - Drawing (Focus Ring)

    /// Draws a rounded focus ring around the Tab-focused interactive element.
    func drawFocusRing(_ dirtyRect: NSRect) {
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

    // MARK: - Cursor Rects

    /// Adds pointing hand cursor over all interactive element ranges.
    func updateInteractiveCursorRects() {
        guard let textStorage, let layoutManager, let textContainer else { return }

        let origin = textContainerOrigin

        textStorage.enumerateAttribute(.interactiveElement, in: NSRange(location: 0, length: textStorage.length)) { value, range, _ in
            guard value != nil else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: textContainer) { rect, _ in
                self.addCursorRect(rect.offsetBy(dx: origin.x, dy: origin.y), cursor: .pointingHand)
            }
        }
    }
}
