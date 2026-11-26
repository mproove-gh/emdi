import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Declared in Info.plist (UTImportedTypeDeclarations) for .md, .markdown, .mdown and .mkd.
    static let markdownDocument = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

/// A Markdown file. The raw Markdown text is the only state: it is saved exactly as typed.
struct MarkdownDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.markdownDocument, .plainText]
    static let writableContentTypes: [UTType] = [.markdownDocument]

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = try Self.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Self.encode(text))
    }

    static func decode(_ data: Data) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return text
    }

    static func encode(_ text: String) -> Data {
        Data(text.utf8)
    }
}
