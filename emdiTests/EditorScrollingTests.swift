import AppKit
import SwiftUI
import Testing
@testable import emdi

/// Simulates real use of samples/showcase.md in an offscreen window and checks that the view stays still:
/// what is at the top of the visible area must not change when the caret moves, when typing, or when
/// a checkbox far from the caret is clicked.
@MainActor
struct EditorScrollingTests {
    static let showcase = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("samples/showcase.md")

    final class Box { var text: String; init(_ t: String) { text = t } }

    func host() throws -> (NSWindow, MarkdownTextView, NSScrollView) {
        let box = Box(try String(contentsOf: Self.showcase, encoding: .utf8))
        let binding = Binding(get: { box.text }, set: { box.text = $0 })
        let view = NSHostingView(rootView: MarkdownEditorView(text: binding, fileURL: Self.showcase))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 700),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false  // ARC owns it; close() must not release it again.
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        let scroll = try #require(Self.find(NSScrollView.self, in: view))
        let textView = try #require(scroll.documentView as? MarkdownTextView)
        window.makeFirstResponder(textView)
        pump()
        return (window, textView, scroll)
    }

    static func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let v = view as? T { return v }
        for sub in view.subviews { if let v = find(type, in: sub) { return v } }
        return nil
    }

    func pump(_ seconds: Double = 0.2) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Offset of the first character drawn at the top of the visible area, and the clip's y origin.
    func topOfView(_ textView: MarkdownTextView, _ scroll: NSScrollView) -> (y: CGFloat, char: Int, line: String) {
        let visible = textView.visibleRect
        let lm = textView.textLayoutManager!
        let point = CGPoint(x: 50, y: visible.minY - textView.textContainerOrigin.y + 5)
        lm.ensureLayout(for: NSTextRange(location: lm.documentRange.location))
        guard let fragment = lm.textLayoutFragment(for: point),
              let content = lm.textContentManager else { return (visible.minY, -1, "?") }
        let offset = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        let text = textView.string as NSString
        let line = text.substring(with: text.lineRange(for: NSRange(location: offset, length: 0)))
        return (scroll.contentView.bounds.minY, offset, String(line.prefix(50)).trimmingCharacters(in: .newlines))
    }

    func scroll(_ scroll: NSScrollView, toCharacter index: Int, in textView: MarkdownTextView) {
        textView.scrollRangeToVisible(NSRange(location: index, length: 0))
        pump()
    }

    func click(_ textView: MarkdownTextView, atViewPoint point: NSPoint) {
        let windowPoint = textView.convert(point, to: nil)
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: windowPoint, modifierFlags: [],
                                       timestamp: 0, windowNumber: textView.window!.windowNumber, context: nil,
                                       eventNumber: 0, clickCount: 1, pressure: 1)!
        textView.mouseDown(with: event)
    }

    /// The view point of the checkbox of the task whose line contains `needle`.
    func checkboxPoint(_ needle: String, in textView: MarkdownTextView) -> NSPoint? {
        let text = textView.string as NSString
        let location = text.range(of: needle).location
        guard location != NSNotFound, let lm = textView.textLayoutManager, let content = lm.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: location) else { return nil }
        lm.ensureLayout(for: NSTextRange(location: start))
        guard let fragment = lm.textLayoutFragment(for: start) as? TaskLayoutFragment else { return nil }
        let r = fragment.checkboxRect.offsetBy(dx: fragment.layoutFragmentFrame.minX, dy: fragment.layoutFragmentFrame.minY)
        let o = textView.textContainerOrigin
        return NSPoint(x: r.midX + o.x, y: r.midY + o.y)
    }

    @Test func checkboxClickWhileCaretIsFarAway() throws {
        let (window, textView, scroll) = try host()
        defer { window.close() }
        let text = textView.string as NSString
        // Caret in section 2.
        textView.setSelectedRange(NSRange(location: text.range(of: "bold text with asterisks").location, length: 0))
        let caret = textView.selectedRange()
        pump()
        // Scroll to the end, as with the scroll wheel: the caret stays where it is.
        let lm = try #require(textView.textLayoutManager)
        lm.ensureLayout(for: lm.documentRange)
        textView.scroll(NSPoint(x: 0, y: textView.frame.height - scroll.contentView.bounds.height))
        pump()
        let before = topOfView(textView, scroll)
        let point = try #require(checkboxPoint("Select a word and press", in: textView))
        let original = textView.string
        click(textView, atViewPoint: point)
        pump()
        // The sample file may have been checked by hand: expect the opposite state, whatever it was.
        let wasChecked = original.contains("- [x] Select a word and press")
        #expect(textView.string.contains(wasChecked ? "- [ ] Select a word and press" : "- [x] Select a word and press"))
        #expect(textView.selectedRange() == caret)
        let after = topOfView(textView, scroll)
        #expect(after.y == before.y)
        #expect(after.char == before.char)
    }

    @Test func clickingAnotherBlockKeepsViewStill() throws {
        let (window, textView, scroll) = try host()
        defer { window.close() }
        let text = textView.string as NSString
        // Scroll to the middle of the document without laying out everything first, like a fresh open.
        textView.scroll(NSPoint(x: 0, y: 4000))
        pump()
        let before = topOfView(textView, scroll)
        // Move the caret into blocks of different kinds, as clicks would.
        for needle in ["## 6. Tables", "| Lorem        |", "EMD-002", "![The emdi icon, large]", "Three asterisks", "```swift", "- [ ] Select a word"] {
            let loc = text.range(of: needle).location
            textView.setSelectedRange(NSRange(location: loc, length: 0))
            pump()
            let now = topOfView(textView, scroll)
            #expect(now.y == before.y, "caret at \(needle)")
            #expect(now.char == before.char, "caret at \(needle): top shows «\(now.line)» instead of «\(before.line)»")
        }
    }

    @Test func typingKeepsViewStill() throws {
        let (window, textView, scroll) = try host()
        defer { window.close() }
        let text = textView.string as NSString
        let loc = text.range(of: "Sed lectus. Integer euismod").location
        textView.setSelectedRange(NSRange(location: loc, length: 0))
        textView.scrollRangeToVisible(NSRange(location: loc, length: 0))
        pump()
        let before = topOfView(textView, scroll)
        for ch in "Hello " {
            textView.insertText(String(ch), replacementRange: textView.selectedRange())
            pump(0.05)
        }
        let afterTyping = topOfView(textView, scroll)
        #expect(afterTyping.y == before.y)
        #expect(afterTyping.char == before.char)
        textView.insertNewline(nil)
        pump()
        let afterReturn = topOfView(textView, scroll)
        #expect(afterReturn.y == before.y)
        #expect(afterReturn.char == before.char)
    }
}
