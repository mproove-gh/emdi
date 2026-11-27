import AppKit
import Testing
@testable import emdi

/// Clicks and hovering in a real editor: table cells, code block labels, the pointer over controls.
@MainActor
struct EditorInteractionTests {
    private static let document = """
        Some text first.

        | Name | Empty | Notes |
        | ---- | ----- | ----- |
        | Alpha |  | Long note here |
        | Beta | x | y |

        ```python
        print("hi")
        ```

        ```
        no language
        ```

        - [ ] A task

        End.
        """

    /// The borders and paragraph offset of the table row whose line contains `needle`.
    private func row(_ needle: String, in host: EditorTestHost) throws
        -> (fragment: TableRowLayoutFragment, borders: [CGFloat], start: Int) {
        let location = try host.location(of: needle)
        let fragment = try #require(host.fragment(at: location) as? TableRowLayoutFragment)
        let start = (host.textView.string as NSString).lineRange(for: NSRange(location: location, length: 0)).location
        return (fragment, fragment.cellBorders.map(\.x), start)
    }

    private func clickInRow(_ needle: String, column: Int, fraction: CGFloat, in host: EditorTestHost) throws {
        let (fragment, borders, _) = try row(needle, in: host)
        let line = try #require(fragment.textLineFragments.first)
        let x = borders[column] + (borders[column + 1] - borders[column]) * fraction
        host.click(at: host.viewPoint(CGPoint(x: x, y: line.typographicBounds.midY), in: fragment))
    }

    @Test func clickingAnEmptyCellPutsTheCaretAtItsStart() throws {
        let host = try EditorTestHost(text: Self.document)
        defer { host.close() }
        let (_, _, start) = try row("| Alpha |", in: host)
        let emptyCellStart = start + ("| Alpha |" as NSString).length + 1  // after the pipe and one space
        for fraction: CGFloat in [0.1, 0.5, 0.9] {
            try clickInRow("| Alpha |", column: 1, fraction: fraction, in: host)
            #expect(host.textView.selectedRange() == NSRange(location: emptyCellStart, length: 0), "fraction \(fraction)")
        }
    }

    @Test func clickingPastACellsTextPutsTheCaretAtItsEnd() throws {
        let host = try EditorTestHost(text: Self.document)
        defer { host.close() }
        try clickInRow("| Beta |", column: 0, fraction: 0.95, in: host)
        let afterBeta = try host.location(of: "Beta |") + 4
        #expect(host.textView.selectedRange() == NSRange(location: afterBeta, length: 0))
        try clickInRow("| Beta |", column: 2, fraction: 0.95, in: host)
        let afterY = try host.location(of: "x | y |") + 5
        #expect(host.textView.selectedRange() == NSRange(location: afterY, length: 0))
    }

    @Test func codeBlocksShowTheirLanguageWhileTheFenceIsHidden() throws {
        let host = try EditorTestHost(text: Self.document)
        defer { host.close() }
        let fence = try host.location(of: "```python")
        host.textView.setSelectedRange(NSRange(location: 0, length: 0))
        host.pump()
        let hidden = try #require(host.fragment(at: fence) as? CodeBlockLayoutFragment)
        #expect(hidden.languageLabel?.string == "python")
        let hiddenHeight = hidden.layoutFragmentFrame.height
        let plain = try #require(host.fragment(at: try host.location(of: "```\nno language")) as? CodeBlockLayoutFragment)
        #expect(plain.languageLabel == nil)

        // In the block the fence itself shows, so no label; the line keeps its height.
        host.textView.setSelectedRange(NSRange(location: try host.location(of: "print"), length: 0))
        host.pump()
        let shown = try #require(host.fragment(at: fence) as? CodeBlockLayoutFragment)
        #expect(shown.languageLabel == nil)
        #expect(abs(shown.layoutFragmentFrame.height - hiddenHeight) < 1)
        // The label is drawing only: copying the block still gives just the code.
        #expect(CodeBlockText.content(of: "```python\nprint(\"hi\")\n```") == "print(\"hi\")")
    }

    @Test func controlsGetTheArrowPointer() throws {
        let host = try EditorTestHost(text: Self.document)
        defer { host.close() }
        let checkbox = try host.checkboxPoint("A task")
        #expect(host.textView.isOverControl(checkbox))
        #expect(!host.textView.isOverControl(NSPoint(x: checkbox.x + 120, y: checkbox.y)))

        // Hover the code block: the copy button appears and counts as a control.
        let code = try #require(host.fragment(at: try host.location(of: "print")))
        let line = try #require(code.textLineFragments.first)
        let inBlock = host.viewPoint(CGPoint(x: 40, y: line.typographicBounds.midY), in: code)
        host.textView.mouseMoved(with: NSEvent.mouseEvent(
            with: .mouseMoved, location: host.textView.convert(inBlock, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: host.window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!)
        let button = try #require(host.textView.subviews.first { $0 is NSButton && !$0.isHidden })
        #expect(host.textView.isOverControl(NSPoint(x: button.frame.midX, y: button.frame.midY)))
        #expect(!host.textView.isOverControl(inBlock))
    }

    @Test func bulletsDependOnDepthAndNumbersLineUp() throws {
        let host = try EditorTestHost(text: "- one\n  - two\n    - three\n      - four\n\n9. nine\n10. ten\n")
        defer { host.close() }
        var textStarts: [CGFloat] = []
        for (depth, word) in ["one", "two", "three", "four"].enumerated() {
            let location = try host.location(of: word)
            let fragment = try #require(host.fragment(at: location) as? ListItemLayoutFragment, "\(word)")
            #expect(fragment.depth == depth)
            let line = try #require(fragment.textLineFragments.first)
            let offset = location - (host.textView.string as NSString).lineRange(for: NSRange(location: location, length: 0)).location
            textStarts.append(fragment.layoutFragmentFrame.minX + line.typographicBounds.minX + line.locationForCharacter(at: offset).x)
        }
        // Each level is indented by more than the two source spaces.
        for (outer, inner) in zip(textStarts, textStarts.dropFirst()) { #expect(inner - outer > 20) }

        // Numbers are right-aligned: the text of 9. and 10. starts at the same place.
        func textStart(_ word: String) throws -> CGFloat {
            let location = try host.location(of: word)
            let fragment = try #require(host.fragment(at: location))
            let line = try #require(fragment.textLineFragments.first)
            let offset = location - (host.textView.string as NSString).lineRange(for: NSRange(location: location, length: 0)).location
            return fragment.layoutFragmentFrame.minX + line.typographicBounds.minX + line.locationForCharacter(at: offset).x
        }
        let nine = try textStart("nine"), ten = try textStart("ten")
        #expect(abs(nine - ten) < 0.5, "nine \(nine) ten \(ten)")
    }

    @Test func quotesAreDrawnAsBarsAndBackspaceRemovesALevel() throws {
        let host = try EditorTestHost(text: "> one\n>\n> > two\n> - item\n")
        defer { host.close() }
        host.textView.setSelectedRange(NSRange(location: 0, length: 0))
        host.pump()
        let one = try #require(host.fragment(at: try host.location(of: "one")) as? MarkdownLayoutFragment)
        #expect(one.quoteBars?.depth == 1)
        let two = try #require(host.fragment(at: try host.location(of: "two")) as? MarkdownLayoutFragment)
        #expect(two.quoteBars?.depth == 2)
        // A quoted list item keeps its bullet and gets the bar too.
        let item = try #require(host.fragment(at: try host.location(of: "item")) as? ListItemLayoutFragment)
        #expect(item.quoteBars?.depth == 1)
        // The blank `>` line between paragraphs is drawn short.
        #expect(try #require(host.fragment(at: 6)).layoutFragmentFrame.height < one.layoutFragmentFrame.height)

        // Backspace at the start of the quoted text removes the innermost level.
        host.textView.setSelectedRange(NSRange(location: try host.location(of: "two"), length: 0))
        host.textView.deleteBackward(nil)
        #expect(host.textView.string == "> one\n>\n> two\n> - item\n")
    }

    @Test func calloutsDrawATitleThatTheCaretReveals() throws {
        let host = try EditorTestHost(text: "Intro.\n\n> [!TIP]\n> Body text.\n\n> [!NOTE] Own title\n> More.\n")
        defer { host.close() }
        host.textView.setSelectedRange(NSRange(location: 0, length: 0))
        host.pump()
        let tipLine = try host.location(of: "[!TIP]")
        let title = try #require(host.fragment(at: tipLine) as? MarkdownLayoutFragment)
        #expect(title.callout == .tip)
        #expect(title.calloutTitle?.string == "Tip")
        let hiddenHeight = title.layoutFragmentFrame.height
        let body = try #require(host.fragment(at: try host.location(of: "Body")) as? MarkdownLayoutFragment)
        #expect(body.callout == .tip && body.calloutTitle == nil)
        // A title after the marker replaces the kind's name: only the icon is drawn.
        let own = try #require(host.fragment(at: try host.location(of: "[!NOTE]")) as? MarkdownLayoutFragment)
        #expect(own.calloutTitle?.string == "")

        // On the first line the marker shows as text, without a drawn title; the line keeps its height.
        host.textView.setSelectedRange(NSRange(location: tipLine + 3, length: 0))
        host.pump()
        let shown = try #require(host.fragment(at: tipLine) as? MarkdownLayoutFragment)
        #expect(shown.calloutTitle == nil)
        #expect(abs(shown.layoutFragmentFrame.height - hiddenHeight) < 1)
    }

    @Test func narrowTablesKeepTheirWidthAndWideOnesFillTheColumn() throws {
        let wideCell = String(repeating: "word ", count: 14)
        let host = try EditorTestHost(text: "| A | B |\n|---|---|\n| 1 | 2 |\n\n| Long | Text |\n|---|---|\n| \(wideCell)| x |\n")
        defer { host.close() }
        let column = try #require(host.textView.textContainer?.size.width)
        func width(_ needle: String) throws -> CGFloat {
            let fragment = try #require(host.fragment(at: try host.location(of: needle)) as? TableRowLayoutFragment)
            let borders = fragment.cellBorders.map(\.x)
            return try #require(borders.max()) - (try #require(borders.min()))
        }
        #expect(try width("| 1 | 2 |") < column / 3)
        #expect(try width("| Long |") > column - 20)
    }

    @Test func fencedBlocksHaveAHeaderAndTightLines() throws {
        let host = try EditorTestHost(text: "Intro.\n\n```swift\nlet a = 1\nlet b = 2\n```\n\n```\nplain\n```\n\n    indented\n\nEnd.\n")
        defer { host.close() }
        host.textView.setSelectedRange(NSRange(location: 0, length: 0))
        host.pump()
        let swift = try #require(host.fragment(at: try host.location(of: "```swift")) as? CodeBlockLayoutFragment)
        #expect(swift.edges.contains(.header))
        #expect(swift.languageLabel?.string == "swift" && swift.copyLabel?.string == "Copy")
        // A block without a language still gets the header, with Copy.
        let plain = try #require(host.fragment(at: try host.location(of: "```\nplain")) as? CodeBlockLayoutFragment)
        #expect(plain.edges.contains(.header) && plain.languageLabel == nil && plain.copyLabel != nil)
        // An indented block has no fence, so no header.
        let indented = try #require(host.fragment(at: try host.location(of: "    indented")) as? CodeBlockLayoutFragment)
        #expect(!indented.edges.contains(.header))
        // Code lines are 1.32 × the code size, whatever the font's own line height.
        let line = try #require(host.fragment(at: try host.location(of: "let b")))
        let font = try #require(host.textView.textStorage?.attribute(.font, at: try host.location(of: "let b"), effectiveRange: nil) as? NSFont)
        #expect(abs(line.layoutFragmentFrame.height - (font.pointSize * 1.32).rounded()) < 0.5)
    }
}
