import Foundation

/// A single replacement in the Markdown source, plus the selection to set afterwards. Ranges are UTF-16.
struct TextEdit: Equatable, Sendable {
    var range: NSRange
    var replacement: String
    var selection: NSRange
}

struct ShortcutModifiers: OptionSet, Sendable {
    let rawValue: Int
    static let command = ShortcutModifiers(rawValue: 1 << 0)
    static let option = ShortcutModifiers(rawValue: 1 << 1)
    static let shift = ShortcutModifiers(rawValue: 1 << 2)
    static let control = ShortcutModifiers(rawValue: 1 << 3)
}

struct Shortcut: Sendable {
    var key: Character
    var modifiers: ShortcutModifiers
}

/// The formatting commands shared by the context menu, the Format menu and keyboard shortcuts.
/// Each one rewrites the Markdown source around the selection and toggles off when already applied.
enum FormatCommand: String, CaseIterable, Sendable {
    case bold, italic, strikethrough, inlineCode, link, clearFormatting
    case paragraph, heading1, heading2, heading3, heading4, heading5, heading6
    case quote, bulletList, numberedList, taskList, codeBlock
    case table, horizontalRule
    case insertColumnLeft, insertColumnRight, deleteColumn
    case insertRowAbove, insertRowBelow, deleteRow
    case alignColumnLeft, alignColumnCenter, alignColumnRight

    static let inlineGroup: [FormatCommand] = [.bold, .italic, .strikethrough, .inlineCode, .link, .clearFormatting]
    static let headingGroup: [FormatCommand] = [.paragraph, .heading1, .heading2, .heading3, .heading4, .heading5, .heading6]
    static let blockGroup: [FormatCommand] = [.quote, .bulletList, .numberedList, .taskList, .codeBlock]
    static let insertGroup: [FormatCommand] = [.table, .horizontalRule]
    /// The Table submenu, in sections separated by dividers.
    static let tableSections: [[FormatCommand]] = [
        [.insertRowAbove, .insertRowBelow, .deleteRow],
        [.insertColumnLeft, .insertColumnRight, .deleteColumn],
        [.alignColumnLeft, .alignColumnCenter, .alignColumnRight],
    ]

    /// The row/column operation of a Table command, nil for other commands.
    var tableOperation: TableStructure.Operation? {
        switch self {
        case .insertColumnLeft: .insertColumn(after: false)
        case .insertColumnRight: .insertColumn(after: true)
        case .deleteColumn: .deleteColumn
        case .insertRowAbove: .insertRow(below: false)
        case .insertRowBelow: .insertRow(below: true)
        case .deleteRow: .deleteRow
        case .alignColumnLeft: .align(.left)
        case .alignColumnCenter: .align(.center)
        case .alignColumnRight: .align(.right)
        default: nil
        }
    }

    /// Whether the command applies at `selection` (Table commands need the caret in a table).
    func isAvailable(in text: String, selection: NSRange) -> Bool {
        guard let operation = tableOperation else { return true }
        return TableStructure.canPerform(operation, in: text, selection: selection)
    }

    var title: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .strikethrough: "Strikethrough"
        case .inlineCode: "Code"
        case .link: "Link"
        case .clearFormatting: "Clear Formatting"
        case .paragraph: "Paragraph"
        case .heading1: "Heading 1"
        case .heading2: "Heading 2"
        case .heading3: "Heading 3"
        case .heading4: "Heading 4"
        case .heading5: "Heading 5"
        case .heading6: "Heading 6"
        case .quote: "Quote"
        case .bulletList: "Bullet List"
        case .numberedList: "Numbered List"
        case .taskList: "Task List"
        case .codeBlock: "Code Block"
        case .table: "Table"
        case .horizontalRule: "Horizontal Rule"
        case .insertColumnLeft: "Insert Column Left"
        case .insertColumnRight: "Insert Column Right"
        case .deleteColumn: "Delete Column"
        case .insertRowAbove: "Insert Row Above"
        case .insertRowBelow: "Insert Row Below"
        case .deleteRow: "Delete Row"
        case .alignColumnLeft: "Align Column Left"
        case .alignColumnCenter: "Align Column Center"
        case .alignColumnRight: "Align Column Right"
        }
    }

    var shortcut: Shortcut? {
        switch self {
        case .bold: Shortcut(key: "b", modifiers: .command)
        case .italic: Shortcut(key: "i", modifiers: .command)
        case .strikethrough: Shortcut(key: "x", modifiers: [.command, .shift])
        case .inlineCode: Shortcut(key: "`", modifiers: .control)
        case .link: Shortcut(key: "k", modifiers: .command)
        case .clearFormatting: Shortcut(key: "\\", modifiers: .command)
        case .paragraph: Shortcut(key: "0", modifiers: .command)
        case .heading1: Shortcut(key: "1", modifiers: .command)
        case .heading2: Shortcut(key: "2", modifiers: .command)
        case .heading3: Shortcut(key: "3", modifiers: .command)
        case .heading4: Shortcut(key: "4", modifiers: .command)
        case .heading5: Shortcut(key: "5", modifiers: .command)
        case .heading6: Shortcut(key: "6", modifiers: .command)
        case .quote: Shortcut(key: "q", modifiers: [.command, .option])
        case .bulletList: Shortcut(key: "u", modifiers: [.command, .option])
        case .numberedList: Shortcut(key: "o", modifiers: [.command, .option])
        case .taskList: Shortcut(key: "x", modifiers: [.command, .option])
        case .codeBlock: Shortcut(key: "c", modifiers: [.command, .option])
        case .table, .horizontalRule: nil  // ⌥⌘T is taken by View ▸ Show Toolbar
        case .insertColumnLeft, .insertColumnRight, .deleteColumn, .insertRowAbove, .insertRowBelow, .deleteRow,
             .alignColumnLeft, .alignColumnCenter, .alignColumnRight: nil
        }
    }

    func edit(in text: String, selection: NSRange) -> TextEdit {
        if let operation = tableOperation {
            // Outside a table (or when impossible, like deleting the only column) nothing changes.
            return TableStructure.edit(operation, in: text, selection: selection)
                ?? TextEdit(range: NSRange(location: selection.location, length: 0), replacement: "", selection: selection)
        }
        let text = text as NSString
        switch self {
        case .bold: return MarkdownFormatter.toggleInline("**", in: text, selection: selection)
        case .italic: return MarkdownFormatter.toggleInline("*", in: text, selection: selection)
        case .strikethrough: return MarkdownFormatter.toggleInline("~~", in: text, selection: selection)
        case .inlineCode: return MarkdownFormatter.toggleInline("`", in: text, selection: selection)
        case .link: return MarkdownFormatter.link(in: text, selection: selection)
        case .clearFormatting: return MarkdownFormatter.clearFormatting(in: text as String, selection: selection)
        case .paragraph: return MarkdownFormatter.heading(level: 0, in: text, selection: selection)
        case .heading1: return MarkdownFormatter.heading(level: 1, in: text, selection: selection)
        case .heading2: return MarkdownFormatter.heading(level: 2, in: text, selection: selection)
        case .heading3: return MarkdownFormatter.heading(level: 3, in: text, selection: selection)
        case .heading4: return MarkdownFormatter.heading(level: 4, in: text, selection: selection)
        case .heading5: return MarkdownFormatter.heading(level: 5, in: text, selection: selection)
        case .heading6: return MarkdownFormatter.heading(level: 6, in: text, selection: selection)
        case .quote: return MarkdownFormatter.toggleLinePrefix(.quote, in: text, selection: selection)
        case .bulletList: return MarkdownFormatter.toggleLinePrefix(.bullet, in: text, selection: selection)
        case .numberedList: return MarkdownFormatter.toggleLinePrefix(.numbered, in: text, selection: selection)
        case .taskList: return MarkdownFormatter.toggleLinePrefix(.task, in: text, selection: selection)
        case .codeBlock: return MarkdownFormatter.codeBlock(in: text, selection: selection)
        case .table:
            return MarkdownFormatter.insertBlock("| Column 1 | Column 2 |\n| --- | --- |\n|  |  |\n",
                                                 select: NSRange(location: 2, length: 8), in: text, selection: selection)
        case .horizontalRule:
            return MarkdownFormatter.insertBlock("---\n", select: NSRange(location: 4, length: 0), in: text, selection: selection)
        case .insertColumnLeft, .insertColumnRight, .deleteColumn, .insertRowAbove, .insertRowBelow, .deleteRow,
             .alignColumnLeft, .alignColumnCenter, .alignColumnRight:
            preconditionFailure("handled above")
        }
    }
}

enum MarkdownFormatter {
    // MARK: Clear formatting

    /// Removes the Markdown formatting that touches the selection (or the caret): emphasis, strikethrough,
    /// inline code, links and images (their text is kept), headings, list and task markers, quote markers
    /// and code block fences. Tables and rules are left as they are. The selection keeps covering the same text.
    static func clearFormatting(in text: String, selection: NSRange) -> TextEdit {
        let ns = text as NSString
        let spans = MarkdownStyler.spans(for: text)
        func touches(_ range: NSRange) -> Bool {
            selection.length == 0
                ? range.location <= selection.location && selection.location <= NSMaxRange(range)
                : NSIntersectionRange(range, selection).length > 0
        }
        let lines = ns.lineRange(for: selection)

        var removals: [NSRange] = []
        // Inline elements and headings: drop the syntax spans inside each touched element.
        let elements = spans.filter { span in
            switch span.kind {
            case .strong, .emphasis, .strikethrough, .link, .inlineCode, .heading, .codeBlock: touches(span.range)
            default: false
            }
        }
        for element in elements {
            for span in spans where span.kind == .syntax
                && NSIntersectionRange(span.range, element.range).length == span.range.length {
                removals.append(span.range)
            }
        }
        // Line prefixes on the selected lines: list bullets and numbers, task boxes, quote markers.
        for span in spans where NSIntersectionRange(span.range, lines).length > 0 {
            switch span.kind {
            case .marker, .taskMarker:
                var range = span.range
                if NSMaxRange(range) < ns.length, ns.character(at: NSMaxRange(range)) == unichar(UInt8(ascii: " ")),
                   ns.substring(with: range).hasSuffix(">") {
                    range.length += 1  // "> " → remove the space after the quote marker too
                }
                removals.append(range)
            default:
                break
            }
        }

        let merged = merge(removals.filter { $0.length > 0 })
        guard let first = merged.first, let last = merged.last else {
            return TextEdit(range: NSRange(location: selection.location, length: 0), replacement: "", selection: selection)
        }
        let span = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        var kept = ""
        var cursor = span.location
        for removal in merged {
            kept += ns.substring(with: NSRange(location: cursor, length: removal.location - cursor))
            cursor = NSMaxRange(removal)
        }
        kept += ns.substring(with: NSRange(location: cursor, length: NSMaxRange(span) - cursor))

        // Map the selection through the removals.
        func mapped(_ location: Int) -> Int {
            location - merged.reduce(0) { total, removal in
                total + max(0, min(location, NSMaxRange(removal)) - removal.location)
            }
        }
        let start = mapped(selection.location)
        let end = mapped(NSMaxRange(selection))
        return TextEdit(range: span, replacement: kept, selection: NSRange(location: start, length: max(end - start, 0)))
    }

    private static func merge(_ ranges: [NSRange]) -> [NSRange] {
        var result: [NSRange] = []
        for range in ranges.sorted(by: { $0.location < $1.location }) {
            if let last = result.last, range.location <= NSMaxRange(last) {
                result[result.count - 1] = NSUnionRange(last, range)
            } else {
                result.append(range)
            }
        }
        return result
    }

    // MARK: Inline

    /// Wraps the selection in `marker`, or removes it when the selection is already wrapped
    /// (markers just outside the selection, or at both ends inside it).
    static func toggleInline(_ marker: String, in text: NSString, selection: NSRange) -> TextEdit {
        let character = marker.utf16.first!
        let width = marker.utf16.count
        // `*` is italic when 1 or 3 stars surround the text, bold when 2+.
        func isApplied(_ count: Int) -> Bool { width == 1 ? count % 2 == 1 : count >= width }

        let before = run(of: character, in: text, endingAt: selection.location)
        let after = run(of: character, in: text, startingAt: NSMaxRange(selection))
        if isApplied(min(before, after)) {
            return TextEdit(
                range: NSRange(location: selection.location - width, length: selection.length + 2 * width),
                replacement: text.substring(with: selection),
                selection: NSRange(location: selection.location - width, length: selection.length))
        }

        let selected = text.substring(with: selection) as NSString
        if selected.length >= 2 * width {
            let leading = run(of: character, in: selected, startingAt: 0)
            let trailing = run(of: character, in: selected, endingAt: selected.length)
            if leading < selected.length, isApplied(min(leading, trailing)) {
                let inner = selected.substring(with: NSRange(location: width, length: selected.length - 2 * width))
                return TextEdit(range: selection, replacement: inner,
                                selection: NSRange(location: selection.location, length: (inner as NSString).length))
            }
        }

        return TextEdit(range: selection, replacement: marker + (selected as String) + marker,
                        selection: NSRange(location: selection.location + width, length: selection.length))
    }

    /// `[selection](url)` with `url` selected, or `[](selection)` when the selection is already a URL.
    static func link(in text: NSString, selection: NSRange) -> TextEdit {
        let selected = text.substring(with: selection)
        if selected.hasPrefix("http://") || selected.hasPrefix("https://") {
            return TextEdit(range: selection, replacement: "[](\(selected))",
                            selection: NSRange(location: selection.location + 1, length: 0))
        }
        let urlStart = selection.location + selection.length + 3  // after "[", the text, "]("
        return TextEdit(range: selection, replacement: "[\(selected)](url)",
                        selection: NSRange(location: urlStart, length: 3))
    }

    // MARK: Lines

    enum LinePrefix {
        case quote, bullet, numbered, task
    }

    private static let headingPrefix = try! NSRegularExpression(pattern: "^#{1,6}(\\s+|$)")
    private static let listPrefix = try! NSRegularExpression(pattern: "^([-*+]|\\d+[.)])\\s+(\\[[ xX]\\]\\s+)?")
    private static let bulletPrefix = try! NSRegularExpression(pattern: "^[-*+]\\s+(?!\\[[ xX]\\])")
    private static let numberedPrefix = try! NSRegularExpression(pattern: "^\\d+[.)]\\s+")
    private static let taskPrefix = try! NSRegularExpression(pattern: "^[-*+]\\s+\\[[ xX]\\]\\s+")
    private static let quotePrefix = try! NSRegularExpression(pattern: "^>\\s?")

    /// Sets the heading level of every selected line; the same level again (or 0) makes them paragraphs.
    static func heading(level: Int, in text: NSString, selection: NSRange) -> TextEdit {
        editLines(in: text, selection: selection) { lines in
            let alreadyAtLevel = level > 0 && lines.allSatisfy { headingLevel(of: $0) == level }
            return lines.map { line in
                let body = strip(headingPrefix, from: line)
                return level == 0 || alreadyAtLevel ? body : String(repeating: "#", count: level) + " " + body
            }
        }
    }

    /// Adds or removes a quote or list prefix on every selected line (blank lines are left alone).
    static func toggleLinePrefix(_ prefix: LinePrefix, in text: NSString, selection: NSRange) -> TextEdit {
        editLines(in: text, selection: selection) { lines in
            let isSingleLine = lines.count == 1
            let targets = lines.map { isSingleLine || !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let pattern: NSRegularExpression = switch prefix {
            case .quote: quotePrefix
            case .bullet: bulletPrefix
            case .numbered: numberedPrefix
            case .task: taskPrefix
            }
            let allHavePrefix = zip(lines, targets).allSatisfy { line, isTarget in
                !isTarget || matches(pattern, line)
            }

            var number = 0
            return zip(lines, targets).map { line, isTarget in
                guard isTarget else { return line }
                if allHavePrefix { return strip(pattern, from: line) }
                switch prefix {
                case .quote:
                    return "> " + line
                case .bullet:
                    return "- " + strip(listPrefix, from: line)
                case .numbered:
                    number += 1
                    return "\(number). " + strip(listPrefix, from: line)
                case .task:
                    return "- [ ] " + strip(listPrefix, from: line)
                }
            }
        }
    }

    /// Wraps the selected lines in a ``` fence and puts the caret where the language goes.
    static func codeBlock(in text: NSString, selection: NSRange) -> TextEdit {
        let (lineRange, content, trailingNewline) = lines(in: text, around: selection)
        let body = content.trimmingCharacters(in: .whitespaces).isEmpty ? "" : content
        return TextEdit(range: lineRange, replacement: "```\n\(body)\n```" + trailingNewline,
                        selection: NSRange(location: lineRange.location + 3, length: 0))
    }

    /// Inserts a block on its own line, separated from a non-empty current line by a blank line.
    /// `select` is relative to the start of `block`.
    static func insertBlock(_ block: String, select: NSRange, in text: NSString, selection: NSRange) -> TextEdit {
        let caret = NSMaxRange(selection)
        let line = text.lineRange(for: NSRange(location: caret, length: 0))
        let lineText = text.substring(with: line)
        if lineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Right under a text line, `---` would turn it into a setext heading: keep a blank line between.
            var separator = ""
            if line.location > 0 {
                let previous = text.substring(with: text.lineRange(for: NSRange(location: line.location - 1, length: 0)))
                if !previous.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { separator = "\n" }
            }
            let replaced = NSRange(location: line.location, length: line.length - (lineText.hasSuffix("\n") ? 1 : 0))
            let body = lineText.hasSuffix("\n") ? String(block.dropLast(block.hasSuffix("\n") ? 1 : 0)) : block
            let start = line.location + (separator as NSString).length
            return TextEdit(range: replaced, replacement: separator + body,
                            selection: NSRange(location: start + select.location, length: select.length))
        }
        let separator = lineText.hasSuffix("\n") ? "\n" : "\n\n"
        let insertion = NSRange(location: NSMaxRange(line), length: 0)
        let start = insertion.location + (separator as NSString).length
        return TextEdit(range: insertion, replacement: separator + block,
                        selection: NSRange(location: start + select.location, length: select.length))
    }

    // MARK: Helpers

    /// Full lines touched by the selection, without the final newline (returned separately).
    private static func lines(in text: NSString, around selection: NSRange) -> (NSRange, String, String) {
        var range = text.lineRange(for: selection)
        var trailing = ""
        if range.length > 0, text.character(at: NSMaxRange(range) - 1) == unichar(UInt8(ascii: "\n")) {
            range.length -= 1
            trailing = "\n"
        }
        return (range, text.substring(with: range), trailing)
    }

    private static func editLines(in text: NSString, selection: NSRange,
                                  transform: ([String]) -> [String]) -> TextEdit {
        let (range, content, _) = lines(in: text, around: selection)
        let oldLines = content.components(separatedBy: "\n")
        let newLines = transform(oldLines)
        let replacement = newLines.joined(separator: "\n")
        let newLength = (replacement as NSString).length

        let newSelection: NSRange
        if selection.length == 0 && oldLines.count == 1 {
            // Keep the caret where it was in the line's text, shifted by the prefix change.
            let delta = newLength - range.length
            let caret = min(max(selection.location + delta, range.location), range.location + newLength)
            newSelection = NSRange(location: caret, length: 0)
        } else {
            newSelection = NSRange(location: range.location, length: newLength)
        }
        return TextEdit(range: range, replacement: replacement, selection: newSelection)
    }

    private static func headingLevel(of line: String) -> Int {
        guard matches(headingPrefix, line) else { return 0 }
        return line.prefix(while: { $0 == "#" }).count
    }

    private static func matches(_ regex: NSRegularExpression, _ line: String) -> Bool {
        regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    private static func strip(_ regex: NSRegularExpression, from line: String) -> String {
        regex.stringByReplacingMatches(in: line, range: NSRange(location: 0, length: (line as NSString).length),
                                       withTemplate: "")
    }

    private static func run(of character: unichar, in text: NSString, endingAt end: Int) -> Int {
        var count = 0
        while end - count - 1 >= 0, text.character(at: end - count - 1) == character { count += 1 }
        return count
    }

    private static func run(of character: unichar, in text: NSString, startingAt start: Int) -> Int {
        var count = 0
        while start + count < text.length, text.character(at: start + count) == character { count += 1 }
        return count
    }
}
