//
//  InteractiveElementSeam.swift
//  MarkdownEngine
//
//  A generic, embedder-driven interactivity seam (no host types in the
//  engine). An embedder overlays two custom attributes onto styled text and
//  supplies a click handler; the engine does the hit-testing, glyph drawing,
//  hover cursor, and invalidation — the same machinery the built-in task
//  checkbox uses, generalized so a host can render its own controls (radio
//  choices, status chips, fill-in fields, …) as styled text.
//
//  Two attributes, both carrying an OPAQUE `String` identifier the engine
//  never interprets — it hands it back to `onInteractiveElementClick`:
//
//    .interactiveGlyph  — value: `InteractiveGlyph`. Draws an SF Symbol inside
//                         the marked range's box (host clears the underlying
//                         glyphs' ink so only the symbol shows). For controls
//                         with a drawn indicator: radio circles, toggles.
//    .interactiveZone   — value: `String` identifier. A clickable text span
//                         with no drawn glyph (the host styles it itself):
//                         status chips, fill-in fields.
//
//  The host re-applies these after every restyle via the overlay hook
//  (`onInteractiveOverlay`); the engine rewrites attributes on each keystroke,
//  so the overlay is the host's chance to reassert its own.
//

import AppKit

extension NSAttributedString.Key {
    /// Value: ``InteractiveGlyph``. A drawn SF-Symbol control occupying the
    /// marked range's box. Opaque identifier returned on click.
    public static let interactiveGlyph = NSAttributedString.Key("MarkdownEngineInteractiveGlyph")
    /// Value: `String` (opaque identifier). A clickable text span with no
    /// engine-drawn glyph — the host styles the span itself.
    public static let interactiveZone = NSAttributedString.Key("MarkdownEngineInteractiveZone")
    /// Value: ``InteractiveAccessory``. Draws a small symbol just past the
    /// TRAILING edge of the range without hiding the text — a disclosure
    /// affordance (e.g. a `chevron.down`), or a clickable action (e.g. a `+`
    /// to add an item) when it carries an identifier.
    public static let interactiveAccessory = NSAttributedString.Key("MarkdownEngineInteractiveAccessory")
}

/// A small SF Symbol drawn just past a range's trailing edge (text left
/// visible). Decorative when `identifier` is nil; a clickable action —
/// hit-tested and routed to `onInteractiveElementClick` — when it isn't.
public struct InteractiveAccessory: Equatable, Hashable, Sendable {
    public var symbolName: String
    public var identifier: String?

    public init(symbolName: String, identifier: String? = nil) {
        self.symbolName = symbolName
        self.identifier = identifier
    }
}

/// A host-defined control drawn as an SF Symbol inside its text range's box.
/// The engine draws it, hit-tests it, and shows a pointing-hand cursor over
/// it; the `identifier` is opaque and returned verbatim to the click handler.
public struct InteractiveGlyph: Equatable, Hashable, Sendable {
    /// SF Symbol name drawn centered in the marked range's bounding box.
    public var symbolName: String
    /// Selected/active look — tinted with the theme's body ink; otherwise muted.
    public var filled: Bool
    /// Opaque host identifier, returned by `onInteractiveElementClick`.
    public var identifier: String

    public init(symbolName: String, filled: Bool, identifier: String) {
        self.symbolName = symbolName
        self.filled = filled
        self.identifier = identifier
    }
}
