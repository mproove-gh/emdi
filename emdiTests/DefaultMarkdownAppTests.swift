import Foundation
import Testing
@testable import emdi

struct DefaultMarkdownAppTests {
    let emdi = URL(fileURLWithPath: "/Users/me/build/emdi.app")

    @Test func recordsTheCurrentHandlers() {
        let result = DefaultMarkdownApp.recording(
            ["md": URL(fileURLWithPath: "/System/Applications/TextEdit.app"), "markdown": nil],
            over: [:], emdi: emdi)
        #expect(result == ["md": "/System/Applications/TextEdit.app"])
    }

    @Test func neverRecordsEmdiItself() {
        let stored = ["md": "/Applications/Xcode.app"]
        let result = DefaultMarkdownApp.recording(
            ["md": emdi, "markdown": URL(fileURLWithPath: "/Applications/emdi.app")],
            over: stored, emdi: emdi)
        #expect(result == stored)
    }
}
