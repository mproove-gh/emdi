import SwiftUI

@main
struct EmdiApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            MarkdownEditorView(text: file.$document.text, fileURL: file.fileURL)
                .frame(minWidth: 480, minHeight: 360)
                .background(DocumentTabsHook())
        }
        .commands {
            FormatCommands()
        }
    }
}
