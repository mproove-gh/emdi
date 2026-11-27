import AppKit
import UniformTypeIdentifiers

/// Making emdi the app that opens Markdown files from the Finder (Settings ▸ Editing).
@MainActor
enum DefaultMarkdownApp {
    /// The types the Finder may use for .md / .markdown files: the system's own type for the
    /// extension and emdi's imported Markdown type, when they differ.
    static var types: [UTType] {
        var types: [UTType] = []
        for type in [UTType(filenameExtension: "md"), UTType(filenameExtension: "markdown"),
                     UTType("net.daringfireball.markdown")].compactMap({ $0 }) where !types.contains(type) {
            types.append(type)
        }
        return types
    }

    /// True when every Markdown type opens with this copy of emdi.
    static var isEmdi: Bool {
        let emdi = Bundle.main.bundleURL.standardizedFileURL
        return types.allSatisfy { NSWorkspace.shared.urlForApplication(toOpen: $0)?.standardizedFileURL == emdi }
    }

    /// macOS may ask the user to confirm the change.
    static func makeEmdiDefault() async throws {
        for type in types {
            try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type)
        }
    }
}
