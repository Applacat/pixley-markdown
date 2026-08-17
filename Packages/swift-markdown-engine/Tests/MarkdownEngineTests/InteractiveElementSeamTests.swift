//
//  InteractiveElementSeamTests.swift
//  MarkdownEngineTests
//
//  Hit-test geometry for the generic interactive-element seam: a click inside
//  a glyph/zone range maps to its opaque identifier; a click outside misses;
//  glyph beats an overlapping zone. Headless, real TextKit 2 layout.
//

import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("Interactive element seam hit-testing")
struct InteractiveElementSeamTests {

    private func makeEditor(_ text: String) -> (NativeTextViewCoordinator, NativeTextView, NSWindow) {
        _ = NSApplication.shared
        let coordinator = NativeTextViewCoordinator(
            text: .constant(text), fontName: "SF Pro", fontSize: 16,
            isWikiLinkActive: .constant(false), onLinkClick: nil, onInlineSelectionChange: nil
        )
        let tv = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        tv.isEditable = true
        tv.delegate = coordinator
        // Wire the TextKit 2 layout stack the way makeNSView does — geometry
        // hit-testing needs a real LayoutBridge + fragment delegate.
        let layoutDelegate = MarkdownLayoutManagerDelegate()
        coordinator.layoutDelegate = layoutDelegate
        tv.textLayoutManager?.delegate = layoutDelegate
        if let tlm = tv.textLayoutManager {
            let bridge = LayoutBridge(tlm)
            coordinator.layoutBridge = bridge
            tv.layoutBridge = bridge
        }
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        scrollView.documentView = tv
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = scrollView
        coordinator.textView = tv
        coordinator.rebuildTextStorageAndStyle(tv, from: text)
        coordinator.lastSyncedText = text
        if let tlm = tv.textLayoutManager { tlm.ensureLayout(for: tlm.documentRange) }
        return (coordinator, tv, window)
    }

    /// Center of a character range in container coordinates.
    private func center(of range: NSRange, in tv: NativeTextView) -> CGPoint {
        let rect = tv.layoutBridge!.boundingRect(forCharacterRange: range, in: tv.textContainer!)
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    @Test("A click inside a glyph range returns its identifier")
    func glyphHit() {
        let (_, tv, window) = makeEditor("pick one A B C")
        defer { window.contentView = nil }
        let range = NSRange(location: 9, length: 1) // "A"
        tv.textStorage?.addAttribute(
            .interactiveGlyph,
            value: InteractiveGlyph(symbolName: "circle", filled: false, identifier: "choice:0:0"),
            range: range)

        let hit = tv.interactiveHit(at: center(of: range, in: tv))
        #expect(hit?.identifier == "choice:0:0")
    }

    @Test("A click outside every interactive range misses")
    func missOutside() {
        let (_, tv, window) = makeEditor("pick one A B C")
        defer { window.contentView = nil }
        tv.textStorage?.addAttribute(
            .interactiveGlyph,
            value: InteractiveGlyph(symbolName: "circle", filled: false, identifier: "choice:0:0"),
            range: NSRange(location: 9, length: 1))

        // Far to the right of all content, still on the first line.
        let miss = tv.interactiveHit(at: CGPoint(x: 550, y: 8))
        #expect(miss == nil)
    }

    @Test("A zone range is clickable and returns its identifier")
    func zoneHit() {
        let (_, tv, window) = makeEditor("Status: IN PROGRESS")
        defer { window.contentView = nil }
        let range = NSRange(location: 8, length: 11) // "IN PROGRESS"
        tv.textStorage?.addAttribute(.interactiveZone, value: "status:0", range: range)

        let hit = tv.interactiveHit(at: center(of: range, in: tv))
        #expect(hit?.identifier == "status:0")
    }

    @Test("A glyph wins over an overlapping zone")
    func glyphBeatsZone() {
        let (_, tv, window) = makeEditor("pick one A B C")
        defer { window.contentView = nil }
        let glyphRange = NSRange(location: 9, length: 1)
        let zoneRange = NSRange(location: 9, length: 5)
        tv.textStorage?.addAttribute(.interactiveZone, value: "zone", range: zoneRange)
        tv.textStorage?.addAttribute(
            .interactiveGlyph,
            value: InteractiveGlyph(symbolName: "circle", filled: false, identifier: "glyph"),
            range: glyphRange)

        let hit = tv.interactiveHit(at: center(of: glyphRange, in: tv))
        #expect(hit?.identifier == "glyph")
    }
}
