//
//  NativeTextView+InteractiveElement.swift
//  MarkdownEngine
//
//  Hit-testing and click dispatch for the generic interactive-element seam
//  (`.interactiveGlyph` / `.interactiveZone`). Mirrors the built-in task
//  checkbox hit-test, but the target range and behavior are host-defined —
//  the engine only maps a click to the range's opaque identifier and rect and
//  calls `onInteractiveElementClick`.
//

import AppKit

extension NativeTextView {

    /// The interactive range under `containerPoint`, if any — glyph ranges take
    /// precedence over zone ranges (a glyph is a smaller, more specific target
    /// inside a zone). `searchRange` bounds the scan: the hovered line for
    /// cursor checks, nil (whole doc) for clicks.
    func interactiveHit(at containerPoint: CGPoint,
                        in searchRange: NSRange? = nil) -> (range: NSRange, identifier: String)? {
        guard let textContainer = textContainer,
              let bridge = layoutBridge,
              let storage = textStorage, storage.length > 0 else { return nil }
        let scan = searchRange ?? NSRange(location: 0, length: storage.length)

        var glyphHit: (range: NSRange, identifier: String)?
        storage.enumerateAttribute(.interactiveGlyph, in: scan, options: []) { value, attrRange, stop in
            guard let glyph = value as? InteractiveGlyph else { return }
            let rect = bridge.boundingRect(forCharacterRange: attrRange, in: textContainer)
            if rect.contains(containerPoint) {
                glyphHit = (attrRange, glyph.identifier)
                stop.pointee = true
            }
        }
        if let glyphHit { return glyphHit }

        var zoneHit: (range: NSRange, identifier: String)?
        storage.enumerateAttribute(.interactiveZone, in: scan, options: []) { value, attrRange, stop in
            guard let identifier = value as? String else { return }
            let rect = bridge.boundingRect(forCharacterRange: attrRange, in: textContainer)
            if rect.contains(containerPoint) {
                zoneHit = (attrRange, identifier)
                stop.pointee = true
            }
        }
        return zoneHit
    }

    /// Dispatches a click on an interactive range to the host. Returns true when
    /// a range was hit and the host handled it (mouseDown then early-returns,
    /// exactly like the task-checkbox path).
    func handleInteractiveClickIfHit(event: NSEvent) -> Bool {
        guard let handler = onInteractiveElementClick,
              let bridge = layoutBridge,
              let textContainer = textContainer else { return false }
        let localPoint = convert(event.locationInWindow, from: nil)
        let containerPoint = CGPoint(x: localPoint.x - textContainerOrigin.x,
                                     y: localPoint.y - textContainerOrigin.y)
        guard let (range, identifier) = interactiveHit(at: containerPoint) else { return false }

        // Range rect in window coordinates, for popover/menu anchoring.
        let containerRect = bridge.boundingRect(forCharacterRange: range, in: textContainer)
        let viewRect = CGRect(x: containerRect.minX + textContainerOrigin.x,
                              y: containerRect.minY + textContainerOrigin.y,
                              width: max(containerRect.width, 1),
                              height: max(containerRect.height, 1))
        let windowRect = convert(viewRect, to: nil)
        return handler(identifier, windowRect)
    }

    /// True when the pointer sits over an interactive glyph or zone — drives the
    /// pointing-hand cursor (edit mode) / arrow suppression. Bounded to the
    /// hovered line's fragment so a mouse-move stays O(line), not O(doc).
    func isOverInteractiveElement(_ event: NSEvent) -> Bool {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let containerPoint = CGPoint(x: viewPoint.x - textContainerOrigin.x,
                                     y: viewPoint.y - textContainerOrigin.y)
        guard let tlm = textLayoutManager,
              let tcs = tlm.textContentManager as? NSTextContentStorage,
              let fragment = tlm.textLayoutFragment(for: containerPoint) else { return false }
        let start = tcs.offset(from: tcs.documentRange.location, to: fragment.rangeInElement.location)
        let end = tcs.offset(from: tcs.documentRange.location, to: fragment.rangeInElement.endLocation)
        guard start != NSNotFound, end > start else { return false }
        let lineRange = NSRange(location: start, length: end - start)
        return interactiveHit(at: containerPoint, in: lineRange) != nil
    }
}
