import AppKit
import ObjectiveC

/// How documents are saved, depending on the "Save automatically while typing" setting.
///
/// - Off (default): classic saving. Closing a window (or quitting) with unsaved changes asks
///   Save / Don't Save / Cancel, and the window title shows "Edited" until the document is saved.
/// - On: `MarkdownEditorView` saves the file about a second after each pause in typing
///   (`saveSoon(_:)`), and closing saves without asking.
///
/// SwiftUI's `DocumentGroup` creates its own `NSDocument` subclass, which always autosaves in place and
/// therefore never asks. There is no SwiftUI API to change that, so the class's `autosavesInPlace` is
/// overridden at runtime to follow the setting, the first time a document window appears.
@MainActor
enum DocumentSaving {
    nonisolated static let autosaveKey = "autosaveWhileTyping"
    /// Pause in typing after which the document is saved, when autosave is on.
    static let autosaveDelay: Duration = .milliseconds(800)

    nonisolated static var isAutosaveOn: Bool { UserDefaults.standard.bool(forKey: autosaveKey) }

    private static var patchedClasses: Set<ObjectIdentifier> = []
    private static var pendingSaves: [ObjectIdentifier: Task<Void, Never>] = [:]

    static func askBeforeDiscardingChanges(in window: NSWindow) {
        guard let document = NSDocumentController.shared.document(for: window) else { return }
        followAutosaveSetting(for: type(of: document))
    }

    static func followAutosaveSetting(for documentClass: NSDocument.Type) {
        guard patchedClasses.insert(ObjectIdentifier(documentClass)).inserted,
              let metaclass = object_getClass(documentClass) else { return }
        let selector = #selector(getter: NSDocument.autosavesInPlace)
        guard let method = class_getClassMethod(documentClass, selector) else { return }
        let followSetting: @convention(block) (AnyObject) -> Bool = { _ in DocumentSaving.isAutosaveOn }
        class_replaceMethod(metaclass, selector, imp_implementationWithBlock(followSetting), method_getTypeEncoding(method))
    }

    /// Called after each edit: when autosave is on, saves the window's document once typing pauses.
    /// Untitled documents are left alone (they have no file yet; macOS keeps a backup of them).
    static func saveSoon(_ window: NSWindow?) {
        guard isAutosaveOn, let window, let document = NSDocumentController.shared.document(for: window) else { return }
        let key = ObjectIdentifier(document)
        pendingSaves[key]?.cancel()
        pendingSaves[key] = Task { @MainActor [weak document] in
            try? await Task.sleep(for: autosaveDelay)
            guard !Task.isCancelled, let document else { return }
            pendingSaves[key] = nil
            // Only called after an edit, so save even if AppKit hasn't flagged the change yet.
            guard let url = document.fileURL, let type = document.fileType else { return }
            document.save(to: url, ofType: type, for: .saveOperation) { _ in }
        }
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
