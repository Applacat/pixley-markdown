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
