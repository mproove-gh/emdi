import AppKit
import Testing
@testable import emdi

struct EditorFontsTests {
    @Test func defaultsAreTheSystemFonts() {
        let fonts = EditorFonts(FontSettings())
        #expect(fonts.body.pointSize == 15)
        #expect(fonts.code.pointSize == 14)
        #expect(fonts.code.isFixedPitch)
        #expect(fonts.body.familyName == NSFont.systemFont(ofSize: 15).familyName)
    }

    @Test func chosenFamiliesAndSizeAreUsed() {
        let fonts = EditorFonts(FontSettings(textFamily: "Georgia", textSize: 18, codeFamily: "Courier New"))
        #expect(fonts.body.familyName == "Georgia")
        #expect(fonts.body.pointSize == 18)
        #expect(fonts.code.familyName == "Courier New")
        #expect(fonts.code.pointSize == 17)
    }

    @Test func headingsScaleWithTheTextSizeAndAreBold() {
        let fonts = EditorFonts(FontSettings(textFamily: "Georgia", textSize: 30, codeFamily: ""))
        #expect(fonts.heading(level: 1).pointSize == 56)
        #expect(fonts.heading(level: 1).familyName == "Georgia")
        #expect(NSFontManager.shared.traits(of: fonts.heading(level: 1)).contains(.boldFontMask))
    }

    @Test func missingFamiliesFallBackToTheSystemFonts() {
        let fonts = EditorFonts(FontSettings(textFamily: "No Such Font", textSize: 15, codeFamily: "Nope Mono"))
        #expect(fonts.body.familyName == NSFont.systemFont(ofSize: 15).familyName)
        #expect(fonts.code.isFixedPitch)
    }

    @Test func storedSizeIsClamped() throws {
        let defaults = try #require(UserDefaults(suiteName: "emdi-tests-fonts"))
        defaults.removePersistentDomain(forName: "emdi-tests-fonts")
        defaults.set(99.0, forKey: FontSettings.textSizeKey)
        #expect(FontSettings.current(defaults).textSize == 28)
        defaults.removePersistentDomain(forName: "emdi-tests-fonts")
    }
}
