import Foundation
import Markdown

/// One styled range of the raw Markdown text. Ranges are UTF-16 (NSRange).
struct StyleSpan: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        // Block styles
        case heading(level: Int)
        case codeBlock
        case blockQuote
        case thematicBreak
        // Inline styles
        case inlineCode
        case strong
        case emphasis
        case strikethrough
        case link
        /// List bullets and numbers: always visible, dimmed.
        case marker
        /// The `>` markers at the start of a quote line, with the space after the last one. Always hidden:
        /// the quote is drawn as `depth` bars. `blank` lines (nothing after the markers) are drawn short.
        case quoteMarker(depth: Int, blank: Bool)
        /// A whole GitHub-style callout (a top-level quote that opens with `[!NOTE]`, `[!TIP]`, …).
        case callout(CalloutKind)
        /// The `[!KIND]` marker of a callout and the spaces after it: drawn as an icon and title,
        /// shown as text while the caret is on its line.
        case calloutMarker(CalloutKind)
        /// The marker of a list item (`- `, `1. `, `- [ ] `), alongside its `.marker` or `.taskMarker` span.
        /// `depth` is 0 for a top-level item; `bullet` is true for `-`, `*` and `+` items that aren't tasks.
        /// `list` identifies the item's list (the offset where the list starts), so its markers can share a column.
        case listItem(depth: Int, bullet: Bool, list: Int)
        /// A later paragraph of a list item, laid out under the item's text.
        case listContinuation(depth: Int, list: Int)
        /// Syntax delimiters (`**`, `#`, fences, `](url)`, …): hidden unless the caret is in their block.
        case syntax
        /// The `- [ ] ` / `- [x] ` prefix of a task item, always drawn as a checkbox.
        case taskMarker(checked: Bool)
        /// The text of a checked task item.
        case completedTask
        /// One line of a table, from its first character to the end of the line (newline excluded).
        case tableRow(TableRowRole)
        /// The text between two pipes (or a line edge and a pipe), spaces included.
        case tableCell(column: Int, alignment: TableAlignment)
        /// A `|` cell separator, always hidden and drawn as a grid line.
        case tablePipe
        /// A syntax-highlighted token inside a code block.
        case codeToken(CodeTokenKind)
        /// A paragraph that holds only an image (`![alt](path)`), shown as the image itself.
        case blockImage(source: String)
        /// An empty (or whitespace-only) line between blocks, newline included. Drawn short, except
        /// while the caret is on it. The block range is the line without its newline.
        case blankLine
    }

    var kind: Kind
    var range: NSRange
    /// The leaf block (paragraph, heading, code block, …) the span belongs to.
    var blockRange: NSRange

    var dependsOnCaret: Bool {
        switch kind {
        case .syntax, .tableRow, .thematicBreak, .blankLine, .quoteMarker(_, blank: true), .calloutMarker: true
        default: false
        }
    }

    /// A block is active, showing its syntax, when the selection touches it.
    static func isActive(block: NSRange, selection: NSRange) -> Bool {
        selection.location <= NSMaxRange(block) && NSMaxRange(selection) >= block.location
    }
}

struct TableRowRole: OptionSet, Equatable, Sendable {
    let rawValue: Int
    static let header = TableRowRole(rawValue: 1 << 0)
    /// The `| --- | :-: |` line under the header.
    static let delimiter = TableRowRole(rawValue: 1 << 1)
    static let first = TableRowRole(rawValue: 1 << 2)
    static let last = TableRowRole(rawValue: 1 << 3)
    /// Every other body row (the second, fourth, …), drawn with a faint fill.
    static let striped = TableRowRole(rawValue: 1 << 4)
}

enum TableAlignment: Equatable, Sendable {
    case left, center, right
}

extension Array where Element == StyleSpan {
    /// The distinct blocks whose look depends on the caret (syntax to reveal, tables) that the selection is in.
    /// The editor restyles when this changes.
    func activeSyntaxBlocks(for selection: NSRange) -> [NSRange] {
        var blocks: [NSRange] = []
        for span in self where span.dependsOnCaret
            && StyleSpan.isActive(block: span.blockRange, selection: selection)
            && blocks.last != span.blockRange {
            blocks.append(span.blockRange)
        }
        return blocks
    }
}

/// Parses Markdown (GFM) and returns the spans that the editor turns into attributes.
/// Pure and AppKit-free so it can be unit tested.
enum MarkdownStyler {
    static func spans(for text: String) -> [StyleSpan] {
        var walker = SpanWalker(text: text)
        walker.visit(Document(parsing: text))
        return walker.spans + blankLines(in: text as NSString, codeBlocks: walker.spans.filter { $0.kind == .codeBlock })
    }

    /// Whitespace-only lines outside code blocks, where blank lines are content.
    private static func blankLines(in text: NSString, codeBlocks: [StyleSpan]) -> [StyleSpan] {
        var spans: [StyleSpan] = []
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: .byLines) { line, lineRange, enclosing, _ in
            guard let line, line.allSatisfy({ $0 == " " || $0 == "\t" }), enclosing.length > lineRange.length,
                  !codeBlocks.contains(where: { NSIntersectionRange($0.range, lineRange).length > 0
                      || NSLocationInRange(lineRange.location, $0.range) }) else { return }
            spans.append(StyleSpan(kind: .blankLine, range: enclosing, blockRange: lineRange))
        }
        return spans
    }
}

private struct SpanWalker {
    let map: SourceMap
    let nsText: NSString
    var spans: [StyleSpan] = []
    var block = NSRange(location: 0, length: 0)
    /// How many block quotes enclose the node being visited. Markers are added by the outermost one only.
    var quoteNesting = 0

    init(text: String) {
        map = SourceMap(text)
        nsText = text as NSString
    }

    mutating func visit(_ node: any Markup) {
        guard let range = node.range.map(map.nsRange(of:)) else {
            visitChildren(of: node)
            return
        }
        let enclosingBlock = block

        switch node {
        case let heading as Heading:
            block = range
            add(.heading(level: heading.level), range)
            addDelimiters(of: node, in: range)
        case let paragraph as Paragraph:
            block = range
            if paragraph.childCount == 1, let image = paragraph.child(at: 0) as? Image, let source = image.source {
                add(.blockImage(source: source), range)
            }
        case is HTMLBlock:
            block = range
        case let table as Table:
            block = range
            addTable(in: range, alignments: table.columnAlignments.map { alignment in
                switch alignment {
                case .center: .center
                case .right: .right
                default: .left
                }
            })
        case let codeBlock as CodeBlock:
            // An indented block's range starts after the first line's indentation: include it, so the
            // first line is indented like the others.
            let lineStart = nsText.lineRange(for: NSRange(location: range.location, length: 0)).location
            let range = isFence(nsText.lineRange(for: NSRange(location: range.location, length: 0)))
                ? range : NSRange(location: lineStart, length: NSMaxRange(range) - lineStart)
            block = range
            add(.codeBlock, range)
            let content = addFences(in: range)
            addCodeTokens(in: content, language: codeBlock.language)
        case is ThematicBreak:
            // swift-markdown's range runs over the blank lines that follow the rule: keep its own line,
            // otherwise each of those lines is drawn as a rule too.
            let line = nsText.lineRange(for: NSRange(location: range.location, length: 0))
            let range = NSIntersectionRange(range, line).length > 0 ? NSIntersectionRange(range, line) : range
            block = range
            add(.thematicBreak, range)
        case is BlockQuote:
            add(.blockQuote, range)
            if quoteNesting == 0 {
                addQuoteMarkers(in: range)
                let firstLine = nsText.lineRange(for: NSRange(location: range.location, length: 0))
                if let callout = CalloutKind.opening(of: firstLine, in: nsText) {
                    add(.callout(callout.kind), range)
                    let line = NSRange(location: firstLine.location,
                                       length: (nsText.substring(with: firstLine).trimmingCharacters(in: .newlines) as NSString).length)
                    spans.append(StyleSpan(kind: .calloutMarker(callout.kind), range: callout.marker, blockRange: line))
                }
            }
        case let item as ListItem:
            if let first = childRanges(of: node).first {
                let marker = NSRange(location: range.location, length: max(first.location - range.location, 0))
                if let checkbox = item.checkbox {
                    let checked = checkbox == .checked
                    spans.append(StyleSpan(kind: .taskMarker(checked: checked), range: marker, blockRange: first))
                    if checked { spans.append(StyleSpan(kind: .completedTask, range: first, blockRange: first)) }
                } else {
                    spans.append(StyleSpan(kind: .marker, range: marker, blockRange: first))
                }
                var depth = 0
                var ancestor = item.parent
                while let current = ancestor {
                    if current is ListItem { depth += 1 }
                    ancestor = current.parent
                }
                let bullet = item.checkbox == nil && item.parent is UnorderedList
                let list = item.parent?.range.map(map.nsRange(of:))?.location ?? range.location
                spans.append(StyleSpan(kind: .listItem(depth: depth, bullet: bullet, list: list), range: marker, blockRange: first))
                for child in item.children.dropFirst() where child is Paragraph {
                    if let childRange = child.range.map(map.nsRange(of:)) {
                        spans.append(StyleSpan(kind: .listContinuation(depth: depth, list: list), range: childRange,
                                               blockRange: childRange))
                    }
                }
            }
        case is Strong:
            add(.strong, range)
            addDelimiters(of: node, in: range)
        case is Emphasis:
            add(.emphasis, range)
            addDelimiters(of: node, in: range)
        case is Strikethrough:
            add(.strikethrough, range)
            addDelimiters(of: node, in: range)
        case is Link, is Image:
            add(.link, range)
            addDelimiters(of: node, in: range)
        case is InlineCode:
            add(.inlineCode, range)
            addBacktickDelimiters(in: range)
        default:
            break
        }

        let isQuote = node is BlockQuote
        if isQuote { quoteNesting += 1 }
        visitChildren(of: node)
        if isQuote { quoteNesting -= 1 }
        block = enclosingBlock
    }

    private mutating func visitChildren(of node: any Markup) {
        for child in node.children { visit(child) }
    }

    private func childRanges(of node: any Markup) -> [NSRange] {
        node.children.compactMap { $0.range.map(map.nsRange(of:)) }
    }

    private mutating func add(_ kind: StyleSpan.Kind, _ range: NSRange) {
        guard range.length > 0 else { return }
        spans.append(StyleSpan(kind: kind, range: range, blockRange: block))
    }

    /// Everything in the node that is not covered by its children: `**` … `**`, `# `, `[` … `](url)`.
    private mutating func addDelimiters(of node: any Markup, in range: NSRange) {
        let children = childRanges(of: node)
        guard let first = children.first, let last = children.last else {
            add(.syntax, range)
            return
        }
        add(.syntax, NSRange(location: range.location, length: first.location - range.location))
        add(.syntax, NSRange(location: NSMaxRange(last), length: NSMaxRange(range) - NSMaxRange(last)))
    }

    private mutating func addBacktickDelimiters(in range: NSRange) {
        let tick = unichar(UInt8(ascii: "`"))
        var open = 0
        while open < range.length, nsText.character(at: range.location + open) == tick { open += 1 }
        var close = 0
        while close < range.length - open, nsText.character(at: NSMaxRange(range) - 1 - close) == tick { close += 1 }
        add(.syntax, NSRange(location: range.location, length: open))
        add(.syntax, NSRange(location: NSMaxRange(range) - close, length: close))
    }

    /// Hides the opening ```lang line and the closing ``` line of a fenced code block.
    /// Returns the range of the code between the fences (the whole block for an indented block).
    private mutating func addFences(in range: NSRange) -> NSRange {
        let firstLine = nsText.lineRange(for: NSRange(location: range.location, length: 0))
        guard isFence(firstLine) else { return range }  // indented code block: no fences
        add(.syntax, NSIntersectionRange(firstLine, range))
        let start = min(NSMaxRange(firstLine), NSMaxRange(range))
        var end = NSMaxRange(range)

        let lastLine = nsText.lineRange(for: NSRange(location: max(NSMaxRange(range) - 1, range.location), length: 0))
        if lastLine.location > firstLine.location, isFence(lastLine) {
            add(.syntax, NSIntersectionRange(lastLine, range))
            end = lastLine.location
        }
        return NSRange(location: start, length: max(end - start, 0))
    }

    private mutating func addCodeTokens(in content: NSRange, language: String?) {
        guard content.length > 0 else { return }
        for token in CodeHighlighter.tokens(in: nsText.substring(with: content), language: language) {
            let range = NSRange(location: content.location + token.range.location, length: token.range.length)
            add(.codeToken(token.kind), range)
        }
    }

    private func isFence(_ line: NSRange) -> Bool {
        let trimmed = nsText.substring(with: line).trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }

    /// Splits each table line into rows, cells and pipes. Only `\|` escapes a pipe, as in GFM.
    private mutating func addTable(in range: NSRange, alignments: [TableAlignment]) {
        let pipe = unichar(UInt8(ascii: "|"))
        let backslash = unichar(UInt8(ascii: "\\"))
        var lines: [NSRange] = []
        nsText.enumerateSubstrings(in: nsText.lineRange(for: range), options: [.byLines, .substringNotRequired]) { _, line, _, _ in
            lines.append(line)
        }

        for (index, line) in lines.enumerated() {
            var role: TableRowRole = index == 0 ? .header : index == 1 ? .delimiter : []
            if index == 0 { role.insert(.first) }
            if index == lines.count - 1 { role.insert(.last) }
            if index >= 2, (index - 2) % 2 == 1 { role.insert(.striped) }
            spans.append(StyleSpan(kind: .tableRow(role), range: line, blockRange: block))

            var pipes: [Int] = []
            var firstContent: Int?
            var lastContent: Int?
            for position in line.location..<NSMaxRange(line) {
                let character = nsText.character(at: position)
                if character != unichar(UInt8(ascii: " ")) && character != unichar(UInt8(ascii: "\t")) {
                    if firstContent == nil { firstContent = position }
                    lastContent = position
                }
                if character == pipe, position == line.location || nsText.character(at: position - 1) != backslash {
                    pipes.append(position)
                    spans.append(StyleSpan(kind: .tablePipe, range: NSRange(location: position, length: 1), blockRange: block))
                }
            }
            guard !role.contains(.delimiter) else { continue }

            // Cell boundaries: the pipes, plus the line edges when the row has no outer pipe.
            var bounds = pipes
            if pipes.first != firstContent { bounds.insert(line.location - 1, at: 0) }
            if pipes.last != lastContent || pipes.isEmpty { bounds.append(NSMaxRange(line)) }
            for column in 0..<max(bounds.count - 1, 0) {
                let start = bounds[column] + 1
                let cell = NSRange(location: start, length: bounds[column + 1] - start)
                let alignment = column < alignments.count ? alignments[column] : .left
                spans.append(StyleSpan(kind: .tableCell(column: column, alignment: alignment), range: cell, blockRange: block))
            }
        }
    }

    /// Marks the leading `>` (and nested `> >`) on each line of a block quote.
    private mutating func addQuoteMarkers(in range: NSRange) {
        let quote = unichar(UInt8(ascii: ">"))
        let space = unichar(UInt8(ascii: " "))
        var lineStart = range.location
        while lineStart < NSMaxRange(range) {
            let line = nsText.lineRange(for: NSRange(location: lineStart, length: 0))
            var position = line.location
            var markerEnd = position
            var depth = 0
            while position < NSMaxRange(line) {
                let character = nsText.character(at: position)
                if character == quote {
                    markerEnd = position + 1
                    depth += 1
                } else if character != space {
                    break
                }
                position += 1
            }
            if depth > 0 {
                let content = nsText.substring(with: line).trimmingCharacters(in: .newlines) as NSString
                let end = line.location + content.length
                if markerEnd < end, [space, unichar(UInt8(ascii: "\t"))].contains(nsText.character(at: markerEnd)) {
                    markerEnd += 1
                }
                let marker = NSRange(location: line.location, length: markerEnd - line.location)
                let rest = nsText.substring(with: NSRange(location: markerEnd, length: end - markerEnd))
                let blank = rest.allSatisfy { $0 == " " || $0 == "\t" }
                spans.append(StyleSpan(kind: .quoteMarker(depth: depth, blank: blank), range: marker,
                                       blockRange: NSRange(location: line.location, length: end - line.location)))
            }
            lineStart = NSMaxRange(line)
        }
    }
}
