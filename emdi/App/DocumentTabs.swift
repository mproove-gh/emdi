import AppKit
import SwiftUI

/// Opens every document as a tab of the existing emdi window instead of a new window,
/// whatever the "Prefer tabs when opening documents" system setting says.
@MainActor
enum DocumentTabs {
    static let identifier = "emdi.document"

    static func adopt(_ window: NSWindow) {
        window.tabbingIdentifier = identifier
        window.tabbingMode = .preferred
        DocumentSaving.askBeforeDiscardingChanges(in: window)
        AppearanceToggle.shared.install(in: window)

        // Join the frontmost visible document window, unless this one is already in its tab group.
        let others = NSApp.orderedWindows.filter {
            $0 !== window && $0.isVisible && $0.tabbingIdentifier == identifier
        }
        guard let host = others.first, host.tabbedWindows?.contains(window) != true else { return }
        host.addTabbedWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil)
    }
}

/// Placed in each document's view hierarchy to reach its NSWindow as soon as it has one.
struct DocumentTabsHook: NSViewRepresentable {
    func makeNSView(context: Context) -> HookView { HookView() }
    func updateNSView(_ nsView: HookView, context: Context) {}

    final class HookView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { DocumentTabs.adopt(window) }
        }
    }
}
