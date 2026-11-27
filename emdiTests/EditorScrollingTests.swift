import AppKit
import Testing
@testable import emdi

/// Simulates real use of samples/showcase.md in an offscreen window and checks that the view stays still:
/// what is at the top of the visible area must not change when the caret moves, when typing, or when
/// a checkbox far from the caret is clicked.
@MainActor
struct EditorScrollingTests {
    @Test func checkboxClickWhileCaretIsFarAway() throws {
        let host = try EditorTestHost()
        defer { host.close() }
        let textView = host.textView
        // Caret in section 2.
        textView.setSelectedRange(NSRange(location: try host.location(of: "bold text with asterisks"), length: 0))
        let caret = textView.selectedRange()
        host.pump()
        // Scroll to the end, as with the scroll wheel: the caret stays where it is.
        let lm = try #require(textView.textLayoutManager)
        lm.ensureLayout(for: lm.documentRange)
        textView.scroll(NSPoint(x: 0, y: textView.frame.height - host.scrollView.contentView.bounds.height))
        host.pump()
        let before = host.topOfView()
        let original = textView.string
        host.click(at: try host.checkboxPoint("Select a word and press"))
        host.pump()
        // The sample file may have been checked by hand: expect the opposite state, whatever it was.
        let wasChecked = original.contains("- [x] Select a word and press")
        #expect(textView.string.contains(wasChecked ? "- [ ] Select a word and press" : "- [x] Select a word and press"))
        #expect(textView.selectedRange() == caret)
        let after = host.topOfView()
        #expect(after.y == before.y)
        #expect(after.char == before.char)
    }

    @Test func clickingAnotherBlockKeepsViewStill() throws {
        let host = try EditorTestHost()
        defer { host.close() }
        let textView = host.textView
        // Scroll to the tables section, laying out only what is above it, as scrolling down would.
        // Every block the caret visits is at or below the top of the view: a block above it may
        // legitimately change height (a wide table shown as Markdown) and move what is in view.
        let lm = try #require(textView.textLayoutManager)
        let content = try #require(lm.textContentManager)
        let heading = try #require(content.location(content.documentRange.location,
                                                    offsetBy: try host.location(of: "## 6. Tables")))
        lm.ensureLayout(for: try #require(NSTextRange(location: content.documentRange.location, end: heading)))
        let tables = try #require(host.fragment(at: try host.location(of: "## 6. Tables")))
        textView.scroll(NSPoint(x: 0, y: tables.layoutFragmentFrame.midY + textView.textContainerOrigin.y))
        host.pump()
        let before = host.topOfView()
        // Move the caret into blocks of different kinds, as clicks would.
        for needle in ["## 6. Tables", "| Lorem        |", "EMD-002", "![The emdi icon, large]", "Three asterisks",
                       "```swift", "Select a word and press"] {
            textView.setSelectedRange(NSRange(location: try host.location(of: needle), length: 0))
            host.pump()
            let now = host.topOfView()
            #expect(now.y == before.y, "caret at \(needle)")
            #expect(now.char == before.char, "caret at \(needle): top shows «\(now.line)» instead of «\(before.line)»")
        }
    }

    @Test func typingKeepsViewStill() throws {
        let host = try EditorTestHost()
        defer { host.close() }
        let textView = host.textView
        let location = try host.location(of: "Sed lectus. Integer euismod")
        textView.setSelectedRange(NSRange(location: location, length: 0))
        textView.scrollRangeToVisible(NSRange(location: location, length: 0))
        host.pump()
        let before = host.topOfView()
        for character in "Hello " {
            textView.insertText(String(character), replacementRange: textView.selectedRange())
            host.pump(0.05)
        }
        let afterTyping = host.topOfView()
        #expect(afterTyping.y == before.y)
        #expect(afterTyping.char == before.char)
        textView.insertNewline(nil)
        host.pump()
        let afterReturn = host.topOfView()
        #expect(afterReturn.y == before.y)
        #expect(afterReturn.char == before.char)
    }
}
