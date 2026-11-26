import AppKit
import ObjectiveC

/// Classic save behaviour: no silent autosave. Closing a window (or quitting) with unsaved changes asks
/// Save / Don't Save / Cancel, and the window title shows "Edited" until the document is saved.
///
/// SwiftUI's `DocumentGroup` creates its own `NSDocument` subclass, which autosaves in place and therefore
/// never asks. There is no SwiftUI API to change that, so the class's `autosavesInPlace` is overridden at
/// runtime to return false, the first time a document window appears (before any edit can happen).
@MainActor
enum DocumentSaving {
    private static var patchedClasses: Set<ObjectIdentifier> = []

    static func askBeforeDiscardingChanges(in window: NSWindow) {
        guard let document = NSDocumentController.shared.document(for: window) else { return }
        disableAutosaveInPlace(for: type(of: document))
    }

    static func disableAutosaveInPlace(for documentClass: NSDocument.Type) {
        guard patchedClasses.insert(ObjectIdentifier(documentClass)).inserted,
              let metaclass = object_getClass(documentClass) else { return }
        let selector = #selector(getter: NSDocument.autosavesInPlace)
        guard let method = class_getClassMethod(documentClass, selector) else { return }
        let alwaysFalse: @convention(block) (AnyObject) -> Bool = { _ in false }
        class_replaceMethod(metaclass, selector, imp_implementationWithBlock(alwaysFalse), method_getTypeEncoding(method))
    }
}

/// Quits emdi when its last document window closes, so a lone Settings window never stays behind.
/// Unsaved changes have been dealt with by then: the window only closes once the user chose to save or
/// discard them.
@MainActor
final class LastDocumentQuitter: NSObject {
    static let shared = LastDocumentQuitter()

    /// Replaceable so tests can observe the quit without terminating the test host.
    var terminate: () -> Void = { NSApp.terminate(nil) }

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)),
                                               name: NSWindow.willCloseNotification, object: nil)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow)?.tabbingIdentifier == DocumentTabs.identifier else { return }
        // The document leaves NSDocumentController just after its window: check on the next turn.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.quitIfNoDocumentsLeft() }
        }
    }

    private func quitIfNoDocumentsLeft() {
        let documentWindows = NSApp.windows.filter { $0.isVisible && $0.tabbingIdentifier == DocumentTabs.identifier }
        guard NSDocumentController.shared.documents.isEmpty, documentWindows.isEmpty else { return }
        terminate()
    }
}
