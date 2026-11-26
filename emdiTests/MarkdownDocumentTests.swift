import Foundation
import Testing
@testable import emdi

struct MarkdownDocumentTests {
    @Test func roundTripsUTF8Text() throws {
        let text = "# Title\n\n- [x] Done — café ✅\n"
        #expect(try MarkdownDocument.decode(MarkdownDocument.encode(text)) == text)
    }

    @Test func rejectsNonUTF8Data() {
        #expect(throws: CocoaError.self) {
            try MarkdownDocument.decode(Data([0xFF, 0xFE, 0xFD]))
        }
    }

    @Test func savesNewDocumentsAsMarkdown() {
        #expect(MarkdownDocument.writableContentTypes.first?.preferredFilenameExtension == "md")
    }
}
