import AppKit
import MarkdownEngine

/// CriticMarkup constructs registered as engine extensions so they render with
/// distinct styling but no interactivity (G4-P3, US-P3.4). Interactivity —
/// accept/reject affordances — is deferred to G5; here they are styled-but-inert
/// (the overlay never marks them as glyph/zone, so no hover cursor, no click).
///
/// Each is a single-line delimited span, matching the engine's `InlineSyntax`.
/// `rejectsOpenerRun: false` because the openers start with `{`, not a repeated
/// delimiter char, so the run-guard (meant for `~~`/`==`) doesn't apply.
enum CriticMarkupExtensions {

    static func all() -> [any MarkdownExtension] {
        [
            CriticSpan(id: "critic-addition", open: "{++", close: "++}",
                       background: NSColor.systemGreen.withAlphaComponent(0.20)),
            CriticSpan(id: "critic-deletion", open: "{--", close: "--}",
                       background: NSColor.systemRed.withAlphaComponent(0.20), strikethrough: true),
            CriticSpan(id: "critic-substitution", open: "{~~", close: "~~}",
                       background: NSColor.systemOrange.withAlphaComponent(0.20)),
            CriticSpan(id: "critic-highlight", open: "{==", close: "==}",
                       background: NSColor.systemYellow.withAlphaComponent(0.28)),
            CriticSpan(id: "critic-comment", open: "{>>", close: "<<}",
                       background: NSColor.secondaryLabelColor.withAlphaComponent(0.12),
                       foreground: NSColor.secondaryLabelColor, italic: true),
        ]
    }
}

private struct CriticSpan: MarkdownExtension {
    let id: String
    let open: String
    let close: String
    var background: NSColor
    var foreground: NSColor?
    var strikethrough: Bool = false
    var italic: Bool = false

    var inline: InlineSyntax? {
        // Opaque content: CriticMarkup interiors are not re-parsed as markdown
        // (a substitution's `~>` and comment prose stay literal).
        InlineSyntax(open: open, close: close, parsesContent: false, rejectsOpenerRun: false)
    }

    func contentAttributes(theme: MarkdownEditorTheme) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [.backgroundColor: background]
        if let foreground { attrs[.foregroundColor] = foreground }
        if strikethrough {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attrs[.strikethroughColor] = NSColor.systemRed
        }
        if italic {
            let base = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            attrs[.font] = NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
        }
        return attrs
    }

    func html(childrenHTML: String) -> String { childrenHTML }
}
