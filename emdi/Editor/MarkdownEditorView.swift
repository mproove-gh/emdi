import AppKit
import SwiftUI

/// Hosts the AppKit text view (TextKit 2) that edits the raw Markdown text and renders it live:
/// styles are applied as attributes, and syntax markers are hidden outside the block holding the caret.
struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    /// The document's file, used to resolve relative image paths. Nil for an unsaved document.
    var fileURL: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownTextView(usingTextLayoutManager: true)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView

        textView.delegate = context.coordinator
        textView.textLayoutManager?.delegate = context.coordinator.layoutDelegate
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 40, height: 30)
        textView.drawsBackground = true
        textView.backgroundColor = EditorPalette.background
        textView.insertionPointColor = EditorPalette.cursor
        scrollView.drawsBackground = true
        scrollView.backgroundColor = EditorPalette.background

        // Markdown characters must stay exactly as typed.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        textView.string = text
        context.coordinator.fileURL = fileURL
        context.coordinator.attach(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        if context.coordinator.fileURL != fileURL {
            context.coordinator.fileURL = fileURL  // Saved under a new name: relative images may resolve differently.
            (scrollView.documentView as? MarkdownTextView)?.documentURL = fileURL
            context.coordinator.reparse()
        }
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
        context.coordinator.reparse()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        private weak var textView: MarkdownTextView?
        /// The layout manager holds its delegate weakly, so the coordinator keeps it alive.
        let layoutDelegate = MarkdownLayoutDelegate()
        private var spans: [StyleSpan] = []
        private var activeBlocks: [NSRange] = []
        /// True between an edit starting and `textDidChange`, when `spans` no longer match the text.
        private var isEditing = false
        var fileURL: URL?
        private let imageCache = ImageCache()
        private var fontSettings = FontSettings()
        private var defaultsObserver: (any NSObjectProtocol)?

        isolated deinit {
            if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        }

        /// Settings changed: restyle with the new fonts if they are what changed.
        private func fontsMayHaveChanged() {
            let current = FontSettings.current()
            guard current != fontSettings else { return }
            fontSettings = current
            restyle(force: true)
        }
        private var lastImageWidth: CGFloat = 0

        init(text: Binding<String>) {
            self.text = text
        }

        func attach(_ textView: MarkdownTextView) {
            self.textView = textView
            textView.documentURL = fileURL
            textView.registerForDraggedTypes([.fileURL])
            textView.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(textViewFrameDidChange),
                                                   name: NSView.frameDidChangeNotification, object: textView)
            fontSettings = FontSettings.current()
            defaultsObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.fontsMayHaveChanged() }
            }
            reparse()
        }

        /// Images and tables are fitted to the text width, so re-lay them out when the window is resized.
        @objc private func textViewFrameDidChange(_ notification: Notification) {
            guard imageWidth != lastImageWidth, spans.contains(where: { span in
                switch span.kind {
                case .blockImage, .tableRow: true
                default: false
                }
            }) else { return }
            restyle(force: true)
        }

        private var imageWidth: CGFloat {
            guard let container = textView?.textContainer else { return 0 }
            return max(container.size.width - 2 * container.lineFragmentPadding, 0)
        }

        private var themeContext: ThemeContext {
            let width = imageWidth
            guard width > 0 else { return .none }
            let documentURL = fileURL
            let cache = imageCache
            return ThemeContext(
                availableWidth: width,
                image: { source in ImageSource.resolve(source, relativeTo: documentURL).flatMap(cache.image(at:)) },
                resolve: { source in ImageSource.resolve(source, relativeTo: documentURL) })
        }

        func reparse() {
            // Never restyle while an input method is composing (dead keys, accents, IME).
            guard let textView, !textView.hasMarkedText() else { return }
            spans = MarkdownStyler.spans(for: textView.string)
            textView.codeBlockRanges = spans.filter { $0.kind == .codeBlock }.map(\.range)
            textView.tableCells = spans.filter { if case .tableCell = $0.kind { true } else { false } }
            textView.taskPrefixRanges = spans.compactMap { span in
                if case .taskMarker = span.kind { span.range } else { nil }
            }
            textView.quotePrefixRanges = spans.compactMap { span in
                if case .quoteMarker = span.kind { span.range } else { nil }
            }
            restyle(force: true)
        }

        private func restyle(force: Bool) {
            guard let textView, let storage = textView.textStorage else { return }
            let selection = textView.selectedRange()
            let active = spans.activeSyntaxBlocks(for: selection)
            guard force || active != activeBlocks else { return }
            activeBlocks = active
            lastImageWidth = imageWidth
            MarkdownTheme.apply(spans, to: storage, selection: selection, context: themeContext)
            textView.typingAttributes = MarkdownTheme.baseAttributes
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            isEditing = true
            return true
        }

        func textDidChange(_ notification: Notification) {
            isEditing = false
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            reparse()
            DocumentSaving.saveSoon(textView.window)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isEditing, textView?.hasMarkedText() == false else { return }
            restyle(force: false)
        }
    }
}

/// Loaded images, reloaded when the file's modification date changes. Missing files are not cached,
/// so an image shows up as soon as the file appears.
@MainActor
final class ImageCache {
    private var entries: [URL: (image: NSImage, modified: Date)] = [:]

    func image(at url: URL) -> NSImage? {
        guard let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else {
            entries[url] = nil
            return nil
        }
        if let entry = entries[url], entry.modified == modified { return entry.image }
        guard let image = NSImage(contentsOf: url) else { return nil }
        entries[url] = (image, modified)
        return image
    }
}
