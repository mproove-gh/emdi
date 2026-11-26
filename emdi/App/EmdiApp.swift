import SwiftUI

@main
struct EmdiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            MarkdownEditorView(text: file.$document.text, fileURL: file.fileURL)
                .frame(minWidth: 480, minHeight: 360)
                .background(DocumentTabsHook())
        }
        .commands {
            FormatCommands()
        }

        Settings {
            SettingsView()
        }
    }
}
