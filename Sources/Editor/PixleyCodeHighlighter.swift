import AppKit
import aimdRenderer
import MarkdownEngine

/// Internal fenced-code syntax highlighter (G4-P4, US-P4.3 / D-H): a
/// lightweight, dependency-free tokenizer for the engine's `SyntaxHighlighter`
/// protocol. Colors comments, strings, numbers, and a shared keyword set
/// across the common C-family / Swift / JS / Python languages — enough for
/// readable fenced code without pulling in a third-party engine.
struct PixleyCodeHighlighter: SyntaxHighlighter {

    let palette: SyntaxPalette
    let fontSize: CGFloat

    func codeFont(size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    func backgroundColor() -> NSColor {
        palette.selectionNSColor.withAlphaComponent(0.30)
    }

    var appearanceDidChangeNotification: Notification.Name? { nil }

    func highlight(code: String, language: String?) -> NSAttributedString? {
        let font = codeFont(size: fontSize)
        let result = NSMutableAttributedString(
            string: code,
            attributes: [.font: font, .foregroundColor: palette.foregroundNSColor])
        let ns = code as NSString
        let full = NSRange(location: 0, length: ns.length)

        // Order matters: strings and comments claim their spans first so a
        // keyword inside a string/comment isn't recolored.
        var claimed = [NSRange]()
        func paint(_ regex: NSRegularExpression, _ color: NSColor, group: Int = 0) {
            for m in regex.matches(in: code, range: full) {
                let r = m.range(at: group)
                guard r.location != NSNotFound else { continue }
                if claimed.contains(where: { NSIntersectionRange($0, r).length > 0 }) { continue }
                claimed.append(r)
                result.addAttribute(.foregroundColor, value: color, range: r)
            }
        }

        paint(Self.commentRegex, palette.commentNSColor)
        paint(Self.stringRegex, palette.stringNSColor)
        paint(Self.numberRegex, palette.numberNSColor)
        // Keywords last, skipping anything already claimed by a string/comment.
        for m in Self.keywordRegex.matches(in: code, range: full) {
            let r = m.range
            if claimed.contains(where: { NSIntersectionRange($0, r).length > 0 }) { continue }
            result.addAttribute(.foregroundColor, value: palette.keywordNSColor, range: r)
        }
        return result
    }

    // MARK: - Patterns (shared across languages — good enough, not perfect)

    private static let commentRegex = try! NSRegularExpression(
        pattern: #"//[^\n]*|/\*[\s\S]*?\*/|#[^\n]*"#)
    private static let stringRegex = try! NSRegularExpression(
        pattern: #""(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`(?:\\.|[^`\\])*`"#)
    private static let numberRegex = try! NSRegularExpression(
        pattern: #"\b(?:0x[0-9A-Fa-f]+|\d+\.?\d*(?:[eE][+-]?\d+)?)\b"#)
    private static let keywordRegex: NSRegularExpression = {
        let keywords = [
            // control flow / decls shared across Swift, JS/TS, Python, C-family
            "func", "function", "def", "return", "if", "else", "elif", "for", "while",
            "do", "switch", "case", "default", "break", "continue", "guard", "in",
            "let", "var", "const", "class", "struct", "enum", "protocol", "interface",
            "extension", "import", "from", "export", "public", "private", "internal",
            "static", "final", "override", "async", "await", "try", "catch", "throw",
            "throws", "self", "this", "super", "new", "delete", "typeof", "void",
            "int", "float", "double", "bool", "boolean", "string", "char", "nil",
            "null", "true", "false", "none", "and", "or", "not", "is", "as", "where",
            "lambda", "yield", "with", "pass", "raise", "except", "finally", "print",
        ]
        let alternation = keywords.joined(separator: "|")
        return try! NSRegularExpression(pattern: #"\b(?:\#(alternation))\b"#)
    }()
}
