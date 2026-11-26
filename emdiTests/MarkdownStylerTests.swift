import Foundation
import Testing
@testable import emdi

struct MarkdownStylerTests {
    private func ranges(_ kind: StyleSpan.Kind, in text: String) -> [NSRange] {
        MarkdownStyler.spans(for: text).filter { $0.kind == kind }.map(\.range)
    }

    private func r(_ location: Int, _ length: Int) -> NSRange {
        NSRange(location: location, length: length)
    }

    @Test func strongHidesBothDelimiters() {
        let text = "**bold**"
        #expect(ranges(.strong, in: text) == [r(0, 8)])
        #expect(ranges(.syntax, in: text) == [r(0, 2), r(6, 2)])
    }

    @Test func emphasisAndStrikethrough() {
        #expect(ranges(.syntax, in: "*it*") == [r(0, 1), r(3, 1)])
        #expect(ranges(.strikethrough, in: "~~gone~~") == [r(0, 8)])
        #expect(ranges(.syntax, in: "~~gone~~") == [r(0, 2), r(6, 2)])
    }

    @Test func atxHeadingHidesHashes() {
        let text = "## Title"
        #expect(ranges(.heading(level: 2), in: text) == [r(0, 8)])
        #expect(ranges(.syntax, in: text) == [r(0, 3)])
    }

    @Test func inlineCodeHidesBackticks() {
        let text = "a `code` b"
        #expect(ranges(.inlineCode, in: text) == [r(2, 6)])
        #expect(ranges(.syntax, in: text) == [r(2, 1), r(7, 1)])
    }

    @Test func linkHidesBracketsAndDestination() {
        let text = "[emdi](https://x.io)"
        #expect(ranges(.link, in: text) == [r(0, 20)])
        #expect(ranges(.syntax, in: text) == [r(0, 1), r(5, 15)])
    }

    @Test func rangesAreUTF16EvenAfterNonASCII() {
        // "é" is 2 UTF-8 bytes but 1 UTF-16 unit; "🙂" is 4 bytes and 2 units.
        let text = "é🙂 **b**"
        #expect(ranges(.strong, in: text) == [r(4, 5)])
    }

    @Test func fencedCodeBlockHidesFenceLines() {
        let text = "```swift\nlet a = 1\n```"
        #expect(ranges(.codeBlock, in: text) == [r(0, 22)])
        #expect(ranges(.syntax, in: text) == [r(0, 9), r(19, 3)])
    }

    @Test func listAndQuoteMarkersStayVisible() {
        #expect(ranges(.marker, in: "- item") == [r(0, 2)])
        #expect(ranges(.marker, in: "> quote") == [r(0, 1)])
        #expect(ranges(.syntax, in: "- item").isEmpty)
    }

    @Test func syntaxBelongsToItsOwnBlock() {
        let text = "first\n\n**second**"
        let syntax = MarkdownStyler.spans(for: text).filter { $0.kind == .syntax }
        #expect(syntax.allSatisfy { $0.blockRange == r(7, 10) })
    }

    @Test func caretRevealsOnlyItsBlock() {
        let spans = MarkdownStyler.spans(for: "**a**\n\n**b**")
        #expect(spans.activeSyntaxBlocks(for: r(1, 0)) == [r(0, 5)])
        #expect(spans.activeSyntaxBlocks(for: r(12, 0)) == [r(7, 5)])
        #expect(spans.activeSyntaxBlocks(for: r(6, 0)).isEmpty)
    }

    @Test func taskItemsBecomeCheckboxes() {
        #expect(ranges(.taskMarker(checked: false), in: "- [ ] todo") == [r(0, 6)])
        #expect(ranges(.taskMarker(checked: true), in: "- [x] done") == [r(0, 6)])
        #expect(ranges(.completedTask, in: "- [x] done") == [r(6, 4)])
        #expect(ranges(.marker, in: "- [ ] todo").isEmpty)
    }

    @Test func tableRowsCellsAndPipes() {
        let text = "| a | bb |\n| :-: | --: |\n| 1 | 2 |"
        let spans = MarkdownStyler.spans(for: text)
        let rows = spans.compactMap { span -> TableRowRole? in
            if case .tableRow(let role) = span.kind { role } else { nil }
        }
        #expect(rows == [[.header, .first], [.delimiter], [.last]])
        #expect(spans.filter { $0.kind == .tablePipe }.count == 9)
        let cells = spans.compactMap { span -> (Int, TableAlignment, NSRange)? in
            if case .tableCell(let column, let alignment) = span.kind { (column, alignment, span.range) } else { nil }
        }
        #expect(cells.map(\.0) == [0, 1, 0, 1])
        #expect(cells.map(\.1) == [.center, .right, .center, .right])
        #expect(cells.first?.2 == r(1, 3))  // " a " between the first two pipes
    }

    @Test func tableRowsWithoutOuterPipes() {
        let spans = MarkdownStyler.spans(for: "a | b\n--|--\nc | d")
        let cells = spans.filter { if case .tableCell = $0.kind { true } else { false } }.map(\.range)
        #expect(cells == [r(0, 2), r(3, 2), r(12, 2), r(15, 2)])
    }

    @Test func imageAloneInItsParagraphIsABlockImage() {
        #expect(ranges(.blockImage(source: "a.png"), in: "![alt](a.png)") == [r(0, 13)])
        #expect(ranges(.blockImage(source: "a.png"), in: "text ![alt](a.png)").isEmpty)
    }
}
