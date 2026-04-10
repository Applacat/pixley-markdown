import Testing
import SwiftUI
import Foundation
@testable import aimdRenderer

@Suite("Theme System Tests")
struct ThemeTests {

    // MARK: - Syntax Theme Tests

    @Test("All syntax themes have palettes")
    func allThemesHavePalettes() {
        for theme in SyntaxTheme.allCases {
            let palette = theme.palette
            // Verify all color properties are accessible (non-optional Color)
            _ = palette.background
            _ = palette.foreground
            _ = palette.keyword
        }
    }

    @Test("Syntax themes have correct dark/light classification")
    func darkLightClassification() {
        // Light themes
        #expect(SyntaxTheme.xcodeLight.isDark == false)
        #expect(SyntaxTheme.githubLight.isDark == false)
        #expect(SyntaxTheme.solarizedLight.isDark == false)

        // Dark themes
        #expect(SyntaxTheme.xcodeDark.isDark == true)
        #expect(SyntaxTheme.githubDark.isDark == true)
        #expect(SyntaxTheme.oneDark.isDark == true)
        #expect(SyntaxTheme.dracula.isDark == true)
        #expect(SyntaxTheme.solarizedDark.isDark == true)
        #expect(SyntaxTheme.monokai.isDark == true)
        #expect(SyntaxTheme.nord.isDark == true)
    }

    @Test("All 10+ themes are available")
    func tenPlusThemes() {
        #expect(SyntaxTheme.allCases.count >= 10)
    }

    // MARK: - Theme Configuration Tests

    @Test("Default configuration has sensible values")
    func defaultConfiguration() {
        let config = ThemeConfiguration()
        #expect(config.fontSize == 14)
        #expect(config.fontFamily == nil)
        #expect(config.syntaxTheme == .xcodeDark)
        #expect(config.headingScale == .normal)
        #expect(config.showLineNumbers == false)
        #expect(config.underlineLinks == true)
    }

    @Test("Configuration can be customized")
    func customConfiguration() {
        let config = ThemeConfiguration(
            fontSize: 18,
            fontFamily: "Menlo",
            syntaxTheme: .dracula,
            headingScale: .spacious,
            showLineNumbers: true,
            underlineLinks: false
        )

        #expect(config.fontSize == 18)
        #expect(config.fontFamily == "Menlo")
        #expect(config.syntaxTheme == .dracula)
        #expect(config.headingScale == .spacious)
        #expect(config.showLineNumbers == true)
        #expect(config.underlineLinks == false)
    }

    // MARK: - Heading Scale Tests

    @Test("Heading scale factors decrease with level")
    func headingScaleFactors() {
        for scale in HeadingScale.allCases {
            let h1 = scale.factor(for: 1)
            let h2 = scale.factor(for: 2)
            let h3 = scale.factor(for: 3)
            let h4 = scale.factor(for: 4)
            let h5 = scale.factor(for: 5)
            let h6 = scale.factor(for: 6)

            // Each subsequent heading should be smaller or equal
            #expect(h1 >= h2)
            #expect(h2 >= h3)
            #expect(h3 >= h4)
            #expect(h4 >= h5)
            #expect(h5 >= h6)

            // All factors should be positive
            #expect(h1 > 0)
            #expect(h6 > 0)
        }
    }

    @Test("Spacious scale is larger than compact")
    func scaleOrdering() {
        let h1Compact = HeadingScale.compact.factor(for: 1)
        let h1Normal = HeadingScale.normal.factor(for: 1)
        let h1Spacious = HeadingScale.spacious.factor(for: 1)

        #expect(h1Spacious > h1Normal)
        #expect(h1Normal > h1Compact)
    }

    // MARK: - Palette Color Tests

    @Test("All palettes have distinct foreground and background")
    func paletteForegroundBackgroundDistinct() {
        for theme in SyntaxTheme.allCases {
            let palette = theme.palette
            #expect(palette.foreground != palette.background, "Theme \(theme.rawValue) has identical fg/bg")
        }
    }

    @Test("Palettes are Equatable")
    func paletteEquatable() {
        let a = SyntaxPalette.xcodeDark
        let b = SyntaxPalette.xcodeDark
        let c = SyntaxPalette.dracula
        #expect(a == b)
        #expect(a != c)
    }

    @Test("Color hex initializer produces valid colors")
    func colorHexInit() {
        let white = Color(hex: "#FFFFFF")
        let black = Color(hex: "#000000")
        let red = Color(hex: "#FF0000")
        // Colors are created without crashing — basic validity
        #expect(white != black)
        #expect(red != black)
        #expect(red != white)
    }

    #if canImport(AppKit)
    @Test("NSColor accessors produce valid colors")
    func nsColorAccessors() {
        let palette = SyntaxPalette.xcodeDark
        // Verify NSColor computed properties are accessible
        _ = palette.backgroundNSColor
        _ = palette.foregroundNSColor
        _ = palette.keywordNSColor
        _ = palette.stringNSColor
        _ = palette.commentNSColor
        _ = palette.numberNSColor
        _ = palette.typeNSColor
        _ = palette.functionNSColor
        _ = palette.propertyNSColor
        _ = palette.operatorNSColor
        _ = palette.preprocessorNSColor
        _ = palette.commentHighlightNSColor
    }
    #endif
}

// MARK: - SwiftUI Theme Tests

@Suite("SwiftUI Theme Tests")
@MainActor
struct SwiftUIThemeTests {

    @Test("SwiftUI theme can render heading")
    func renderHeading() async {
        let theme = SwiftUITheme()
        let heading = HeadingInfo(level: 1, text: "Test Heading")
        let _ = theme.render(heading: heading)
    }

    @Test("SwiftUI theme can render paragraph")
    func renderParagraph() async {
        let theme = SwiftUITheme()
        let paragraph = ParagraphInfo(text: "Test paragraph content.")
        let _ = theme.render(paragraph: paragraph)
    }

    @Test("SwiftUI theme can render code block")
    func renderCodeBlock() async {
        let theme = SwiftUITheme()
        let codeBlock = CodeBlockInfo(
            language: "swift",
            code: "let x = 42"
        )
        let _ = theme.render(codeBlock: codeBlock)
    }

    @Test("SwiftUI theme can render document")
    func renderDocument() async {
        let theme = SwiftUITheme()
        let document = DocumentModel(content: "# Hello\n\nWorld")
        let _ = theme.render(document: document)
    }

    @Test("SwiftUI theme respects configuration")
    func respectsConfiguration() async {
        let config = ThemeConfiguration(
            fontSize: 20,
            syntaxTheme: .dracula
        )
        let theme = SwiftUITheme(configuration: config)
        #expect(theme.configuration.fontSize == 20)
        #expect(theme.configuration.syntaxTheme == .dracula)
    }
}
