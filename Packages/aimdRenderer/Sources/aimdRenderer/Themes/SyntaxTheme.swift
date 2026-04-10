import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Syntax Theme

/// Enumeration of available syntax highlighting color schemes
public enum SyntaxTheme: String, Sendable, CaseIterable, Identifiable {
    // Apple themes
    case xcodeLight = "Xcode Light"
    case xcodeDark = "Xcode Dark"

    // GitHub themes
    case githubLight = "GitHub Light"
    case githubDark = "GitHub Dark"

    // Popular editor themes
    case oneDark = "One Dark"
    case dracula = "Dracula"
    case solarizedLight = "Solarized Light"
    case solarizedDark = "Solarized Dark"
    case monokai = "Monokai"
    case nord = "Nord"

    public var id: String { rawValue }

    /// Returns the color palette for this theme
    public var palette: SyntaxPalette {
        switch self {
        case .xcodeLight:
            return .xcodeLight
        case .xcodeDark:
            return .xcodeDark
        case .githubLight:
            return .githubLight
        case .githubDark:
            return .githubDark
        case .oneDark:
            return .oneDark
        case .dracula:
            return .dracula
        case .solarizedLight:
            return .solarizedLight
        case .solarizedDark:
            return .solarizedDark
        case .monokai:
            return .monokai
        case .nord:
            return .nord
        }
    }

    /// Whether this is a dark theme
    public var isDark: Bool {
        switch self {
        case .xcodeLight, .githubLight, .solarizedLight:
            return false
        case .xcodeDark, .githubDark, .oneDark, .dracula, .solarizedDark, .monokai, .nord:
            return true
        }
    }
}

// MARK: - Syntax Palette

/// Color palette for syntax highlighting.
/// Stores SwiftUI Color natively; NSColor computed accessors for AppKit rendering.
public struct SyntaxPalette: Sendable, Equatable {

    // MARK: - Base Colors

    /// Background color
    public let background: Color

    /// Default text color
    public let foreground: Color

    /// Selection highlight color
    public let selection: Color

    /// Line number color
    public let lineNumber: Color

    // MARK: - Syntax Colors

    /// Keywords (if, let, func, etc.)
    public let keyword: Color

    /// Strings ("hello", """multiline""")
    public let string: Color

    /// Comments (// and /* */)
    public let comment: Color

    /// Numbers (42, 3.14)
    public let number: Color

    /// Types (String, Int, MyClass)
    public let type: Color

    /// Functions and method names
    public let function: Color

    /// Properties and variables
    public let property: Color

    /// Operators (+, -, ==, etc.)
    public let `operator`: Color

    /// Preprocessor / directives (#if, @main)
    public let preprocessor: Color

    /// Background tint for CriticMarkup comment highlights ({==text==}{>>comment<<})
    public let commentHighlight: Color

    public init(
        background: Color,
        foreground: Color,
        selection: Color,
        lineNumber: Color,
        keyword: Color,
        string: Color,
        comment: Color,
        number: Color,
        type: Color,
        function: Color,
        property: Color,
        `operator`: Color,
        preprocessor: Color,
        commentHighlight: Color = Color(hex: "#FFEEBA")
    ) {
        self.background = background
        self.foreground = foreground
        self.selection = selection
        self.lineNumber = lineNumber
        self.keyword = keyword
        self.string = string
        self.comment = comment
        self.number = number
        self.type = type
        self.function = function
        self.property = property
        self.operator = `operator`
        self.preprocessor = preprocessor
        self.commentHighlight = commentHighlight
    }
}

// MARK: - NSColor Accessors

#if canImport(AppKit)
extension SyntaxPalette {
    public var backgroundNSColor: NSColor { NSColor(background) }
    public var foregroundNSColor: NSColor { NSColor(foreground) }
    public var selectionNSColor: NSColor { NSColor(selection) }
    public var lineNumberNSColor: NSColor { NSColor(lineNumber) }
    public var keywordNSColor: NSColor { NSColor(keyword) }
    public var stringNSColor: NSColor { NSColor(string) }
    public var commentNSColor: NSColor { NSColor(comment) }
    public var numberNSColor: NSColor { NSColor(number) }
    public var typeNSColor: NSColor { NSColor(type) }
    public var functionNSColor: NSColor { NSColor(function) }
    public var propertyNSColor: NSColor { NSColor(property) }
    public var operatorNSColor: NSColor { NSColor(`operator`) }
    public var preprocessorNSColor: NSColor { NSColor(preprocessor) }
    public var commentHighlightNSColor: NSColor { NSColor(commentHighlight) }
}
#endif

// MARK: - Built-in Palettes

extension SyntaxPalette {

    // MARK: - Xcode Light

    public static let xcodeLight = SyntaxPalette(
        background: Color(hex: "#FFFFFF"),
        foreground: Color(hex: "#000000"),
        selection: Color(hex: "#B4D8FD"),
        lineNumber: Color(hex: "#A8A8A8"),
        keyword: Color(hex: "#9B2393"),
        string: Color(hex: "#D12F1B"),
        comment: Color(hex: "#5D6C79"),
        number: Color(hex: "#272AD8"),
        type: Color(hex: "#3900A0"),
        function: Color(hex: "#0F68A0"),
        property: Color(hex: "#326D74"),
        operator: Color(hex: "#000000"),
        preprocessor: Color(hex: "#78492A"),
        commentHighlight: Color(hex: "#FFF3CD")
    )

    // MARK: - Xcode Dark

    public static let xcodeDark = SyntaxPalette(
        background: Color(hex: "#1F1F24"),
        foreground: Color(hex: "#FFFFFF"),
        selection: Color(hex: "#515B70"),
        lineNumber: Color(hex: "#6C6C6C"),
        keyword: Color(hex: "#FF7AB2"),
        string: Color(hex: "#FF8170"),
        comment: Color(hex: "#7F8C98"),
        number: Color(hex: "#D0BF69"),
        type: Color(hex: "#ACF2E4"),
        function: Color(hex: "#67B7A4"),
        property: Color(hex: "#5DD8FF"),
        operator: Color(hex: "#FFFFFF"),
        preprocessor: Color(hex: "#FFA14F"),
        commentHighlight: Color(hex: "#3D3520")
    )

    // MARK: - GitHub Light

    public static let githubLight = SyntaxPalette(
        background: Color(hex: "#FFFFFF"),
        foreground: Color(hex: "#24292E"),
        selection: Color(hex: "#C8C8FA"),
        lineNumber: Color(hex: "#959DA5"),
        keyword: Color(hex: "#D73A49"),
        string: Color(hex: "#032F62"),
        comment: Color(hex: "#6A737D"),
        number: Color(hex: "#005CC5"),
        type: Color(hex: "#6F42C1"),
        function: Color(hex: "#6F42C1"),
        property: Color(hex: "#005CC5"),
        operator: Color(hex: "#D73A49"),
        preprocessor: Color(hex: "#D73A49"),
        commentHighlight: Color(hex: "#FFF8E1")
    )

    // MARK: - GitHub Dark

    public static let githubDark = SyntaxPalette(
        background: Color(hex: "#0D1117"),
        foreground: Color(hex: "#C9D1D9"),
        selection: Color(hex: "#3B5070"),
        lineNumber: Color(hex: "#6E7681"),
        keyword: Color(hex: "#FF7B72"),
        string: Color(hex: "#A5D6FF"),
        comment: Color(hex: "#8B949E"),
        number: Color(hex: "#79C0FF"),
        type: Color(hex: "#FFA657"),
        function: Color(hex: "#D2A8FF"),
        property: Color(hex: "#79C0FF"),
        operator: Color(hex: "#FF7B72"),
        preprocessor: Color(hex: "#FF7B72"),
        commentHighlight: Color(hex: "#2D2A1E")
    )

    // MARK: - One Dark

    public static let oneDark = SyntaxPalette(
        background: Color(hex: "#282C34"),
        foreground: Color(hex: "#ABB2BF"),
        selection: Color(hex: "#3E4451"),
        lineNumber: Color(hex: "#4B5263"),
        keyword: Color(hex: "#C678DD"),
        string: Color(hex: "#98C379"),
        comment: Color(hex: "#5C6370"),
        number: Color(hex: "#D19A66"),
        type: Color(hex: "#E5C07B"),
        function: Color(hex: "#61AFEF"),
        property: Color(hex: "#E06C75"),
        operator: Color(hex: "#56B6C2"),
        preprocessor: Color(hex: "#C678DD"),
        commentHighlight: Color(hex: "#3A3525")
    )

    // MARK: - Dracula

    public static let dracula = SyntaxPalette(
        background: Color(hex: "#282A36"),
        foreground: Color(hex: "#F8F8F2"),
        selection: Color(hex: "#44475A"),
        lineNumber: Color(hex: "#6272A4"),
        keyword: Color(hex: "#FF79C6"),
        string: Color(hex: "#F1FA8C"),
        comment: Color(hex: "#6272A4"),
        number: Color(hex: "#BD93F9"),
        type: Color(hex: "#8BE9FD"),
        function: Color(hex: "#50FA7B"),
        property: Color(hex: "#FFB86C"),
        operator: Color(hex: "#FF79C6"),
        preprocessor: Color(hex: "#FF79C6"),
        commentHighlight: Color(hex: "#3D3A2A")
    )

    // MARK: - Solarized Light

    public static let solarizedLight = SyntaxPalette(
        background: Color(hex: "#FDF6E3"),
        foreground: Color(hex: "#657B83"),
        selection: Color(hex: "#EEE8D5"),
        lineNumber: Color(hex: "#93A1A1"),
        keyword: Color(hex: "#859900"),
        string: Color(hex: "#2AA198"),
        comment: Color(hex: "#93A1A1"),
        number: Color(hex: "#D33682"),
        type: Color(hex: "#B58900"),
        function: Color(hex: "#268BD2"),
        property: Color(hex: "#CB4B16"),
        operator: Color(hex: "#657B83"),
        preprocessor: Color(hex: "#CB4B16"),
        commentHighlight: Color(hex: "#F5E6B8")
    )

    // MARK: - Solarized Dark

    public static let solarizedDark = SyntaxPalette(
        background: Color(hex: "#002B36"),
        foreground: Color(hex: "#839496"),
        selection: Color(hex: "#073642"),
        lineNumber: Color(hex: "#586E75"),
        keyword: Color(hex: "#859900"),
        string: Color(hex: "#2AA198"),
        comment: Color(hex: "#586E75"),
        number: Color(hex: "#D33682"),
        type: Color(hex: "#B58900"),
        function: Color(hex: "#268BD2"),
        property: Color(hex: "#CB4B16"),
        operator: Color(hex: "#839496"),
        preprocessor: Color(hex: "#CB4B16"),
        commentHighlight: Color(hex: "#1A3A2A")
    )

    // MARK: - Monokai

    public static let monokai = SyntaxPalette(
        background: Color(hex: "#272822"),
        foreground: Color(hex: "#F8F8F2"),
        selection: Color(hex: "#49483E"),
        lineNumber: Color(hex: "#90908A"),
        keyword: Color(hex: "#F92672"),
        string: Color(hex: "#E6DB74"),
        comment: Color(hex: "#75715E"),
        number: Color(hex: "#AE81FF"),
        type: Color(hex: "#66D9EF"),
        function: Color(hex: "#A6E22E"),
        property: Color(hex: "#FD971F"),
        operator: Color(hex: "#F92672"),
        preprocessor: Color(hex: "#F92672"),
        commentHighlight: Color(hex: "#3D3820")
    )

    // MARK: - Nord

    public static let nord = SyntaxPalette(
        background: Color(hex: "#2E3440"),
        foreground: Color(hex: "#D8DEE9"),
        selection: Color(hex: "#434C5E"),
        lineNumber: Color(hex: "#4C566A"),
        keyword: Color(hex: "#81A1C1"),
        string: Color(hex: "#A3BE8C"),
        comment: Color(hex: "#616E88"),
        number: Color(hex: "#B48EAD"),
        type: Color(hex: "#8FBCBB"),
        function: Color(hex: "#88C0D0"),
        property: Color(hex: "#D8DEE9"),
        operator: Color(hex: "#81A1C1"),
        preprocessor: Color(hex: "#5E81AC"),
        commentHighlight: Color(hex: "#3B4252")
    )
}

// MARK: - Color Hex Initializer

extension Color {
    /// Creates a Color from a hex string (e.g., "#FF5733" or "FF5733")
    public init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b: UInt64
        switch hex.count {
        case 6: // RGB
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8: // AARRGGBB — alpha ignored, & 0xFF masks it out naturally
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (128, 128, 128) // Default gray
        }

        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255
        )
    }
}
