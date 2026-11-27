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
        #expect(ranges(.marker, in: "> quote").isEmpty)
    }

    @Test func calloutsAreTopLevelQuotesOpeningWithAKind() {
        let text = "> [!Warning] Careful\n> body\n\n> [!NOPE]\n> plain\n\n> > [!NOTE]\n> > nested"
        #expect(ranges(.callout(.warning), in: text) == [r(0, 27)])
        #expect(ranges(.calloutMarker(.warning), in: text) == [r(2, 11)])
        // Unknown kinds and nested quotes are ordinary quotes.
        #expect(MarkdownStyler.spans(for: text).filter { if case .callout = $0.kind { true } else { false } }.count == 1)
    }

    @Test func everyOtherBodyRowIsStriped() {
        let text = "| a |\n| - |\n| 1 |\n| 2 |\n| 3 |\n| 4 |"
        let striped = MarkdownStyler.spans(for: text).compactMap { span -> String? in
            guard case .tableRow(let role) = span.kind, role.contains(.striped) else { return nil }
            return (text as NSString).substring(with: span.range)
        }
        #expect(striped == ["| 2 |", "| 4 |"])
    }

    @Test func quoteMarkersKnowTheirDepth() {
        let text = "> a\n>\n> > b\n>> c"
        #expect(ranges(.quoteMarker(depth: 1, blank: false), in: text) == [r(0, 2)])
        #expect(ranges(.quoteMarker(depth: 1, blank: true), in: text) == [r(4, 1)])
        #expect(ranges(.quoteMarker(depth: 2, blank: false), in: text) == [r(6, 4), r(12, 3)])
        #expect(ranges(.syntax, in: "- item").isEmpty)
    }

    @Test func listItemsKnowTheirDepthAndKind() {
        let text = "- a\n  - b\n    1. c\n- [ ] d\n\n   more d"
        #expect(ranges(.listItem(depth: 0, bullet: true, list: 0), in: text) == [r(0, 2)])
        #expect(ranges(.listItem(depth: 1, bullet: true, list: 6), in: text) == [r(6, 2)])
        #expect(ranges(.listItem(depth: 2, bullet: false, list: 14), in: text) == [r(14, 3)])
        // A task is not a bullet; its later paragraph is a continuation.
        #expect(ranges(.listItem(depth: 0, bullet: false, list: 0), in: text) == [r(19, 6)])
        #expect(ranges(.listContinuation(depth: 0, list: 0), in: text) == [r(31, 6)])
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
        // The blank line between them is its own block: it is drawn full height only under the caret.
        #expect(spans.activeSyntaxBlocks(for: r(6, 0)) == [r(6, 0)])
    }

    @Test func blankLinesOutsideCodeBlocksAreMarked() {
        let text = "a\n\n  \n```\nx\n\ny\n```\n\nb"
        // Lines 2 and 3 (empty, then spaces) and the one after the fence; not the one inside the code.
        #expect(ranges(.blankLine, in: text) == [r(2, 1), r(3, 3), r(19, 1)])
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
