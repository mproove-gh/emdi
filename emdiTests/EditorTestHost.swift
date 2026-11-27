import AppKit
import SwiftUI
import Testing
@testable import emdi

/// Hosts a real `MarkdownEditorView` in an offscreen window, to simulate use: scrolling, clicks, typing.
@MainActor
final class EditorTestHost {
    static let showcase = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("samples/showcase.md")

    private final class Box { var text: String; init(_ text: String) { self.text = text } }

    let window: NSWindow
    let textView: MarkdownTextView
    let scrollView: NSScrollView
    private let box: Box

    /// Loads `text`, or samples/showcase.md when nil.
    init(text: String? = nil, width: CGFloat = 800, height: CGFloat = 700) throws {
        box = Box(try text ?? String(contentsOf: Self.showcase, encoding: .utf8))
        let box = box
        let binding = Binding(get: { box.text }, set: { box.text = $0 })
        let view = NSHostingView(rootView: MarkdownEditorView(text: binding, fileURL: Self.showcase))
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false  // ARC owns it; close() must not release it again.
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        scrollView = try #require(Self.find(NSScrollView.self, in: view))
        textView = try #require(scrollView.documentView as? MarkdownTextView)
        window.makeFirstResponder(textView)
        pump()
    }

    func close() { window.close() }

    private static func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for sub in view.subviews { if let match = find(type, in: sub) { return match } }
        return nil
    }

    func pump(_ seconds: Double = 0.2) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func location(of needle: String) throws -> Int {
        let location = (textView.string as NSString).range(of: needle).location
        try #require(location != NSNotFound, "«\(needle)» is not in the text")
        return location
    }

    /// The layout fragment holding the character at `offset`, laid out.
    func fragment(at offset: Int) -> NSTextLayoutFragment? {
        guard let lm = textView.textLayoutManager, let content = lm.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: offset) else { return nil }
        lm.ensureLayout(for: NSTextRange(location: start))
        return lm.textLayoutFragment(for: start)
    }

    /// Converts a point in fragment coordinates to text view coordinates.
    func viewPoint(_ point: CGPoint, in fragment: NSTextLayoutFragment) -> NSPoint {
        let origin = textView.textContainerOrigin
        return NSPoint(x: point.x + fragment.layoutFragmentFrame.minX + origin.x,
                       y: point.y + fragment.layoutFragmentFrame.minY + origin.y)
    }

    /// Clicks at `point` (text view coordinates) with a real mouse-down and mouse-up.
    func click(at point: NSPoint) {
        let windowPoint = textView.convert(point, to: nil)
        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: windowPoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        // NSTextView tracks the mouse until it is released: queue the mouse-up first.
        NSApp.postEvent(event(.leftMouseUp), atStart: false)
        textView.mouseDown(with: event(.leftMouseDown))
        pump(0.05)
    }

    /// The view point of the checkbox of the task whose line contains `needle`.
    func checkboxPoint(_ needle: String) throws -> NSPoint {
        let fragment = try #require(fragment(at: try location(of: needle)) as? TaskLayoutFragment)
        let rect = fragment.checkboxRect
        return viewPoint(CGPoint(x: rect.midX, y: rect.midY), in: fragment)
    }

    /// The clip view's y origin, and the offset and text of the first line drawn at the top of the visible area.
    func topOfView() -> (y: CGFloat, char: Int, line: String) {
        let visible = textView.visibleRect
        let lm = textView.textLayoutManager!
        let point = CGPoint(x: 50, y: visible.minY - textView.textContainerOrigin.y + 5)
        lm.ensureLayout(for: NSTextRange(location: lm.documentRange.location))
        guard let fragment = lm.textLayoutFragment(for: point),
              let content = lm.textContentManager else { return (visible.minY, -1, "?") }
        let offset = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        let text = textView.string as NSString
        let line = text.substring(with: text.lineRange(for: NSRange(location: offset, length: 0)))
        return (scrollView.contentView.bounds.minY, offset, String(line.prefix(50)).trimmingCharacters(in: .newlines))
    }
}
