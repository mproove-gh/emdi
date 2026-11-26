import Foundation

/// Tab and Shift-Tab inside a table move between cells, as in spreadsheets and Typora,
/// instead of inserting a tab character (which would break the column alignment).
enum TableEditing {
    /// The edit for Tab (or Shift-Tab when `backwards`) at `selection`, or nil when it is not in a table.
    /// Moving selects the target cell's text (or puts the caret in an empty cell). Tab in the last cell
    /// adds an empty row below and moves into it.
    static func tab(in text: NSString, cells: [StyleSpan], selection: NSRange, backwards: Bool) -> TextEdit? {
        let caret = selection.location
        // Anywhere in a table (delimiter row included), Tab never inserts a tab character.
        guard let block = Set(cells.map(\.blockRange)).first(where: { NSLocationInRange(caret, extendedRange($0)) }) else {
            return nil
        }
        let table = cells.filter { $0.blockRange == block }.sorted { $0.range.location < $1.range.location }
        // The cell holding the caret: the last one starting at or before it (a caret on a pipe counts as
        // being in the cell before it). Nil before the first cell.
        guard let index = table.lastIndex(where: { $0.range.location <= caret }) else {
            return backwards || table.isEmpty ? stay(selection) : select(table[0], in: text)
        }
        let current = table[index]

        if backwards {
            guard index > 0 else { return stay(selection) }
            return select(table[index - 1], in: text)
        }
        if index + 1 < table.count {
            return select(table[index + 1], in: text)
        }
        return appendRow(after: current, columns: columnCount(table), in: text)
    }

    // MARK: Helpers

    /// The table plus one character, so a caret right after the last pipe still counts.
    private static func extendedRange(_ range: NSRange) -> NSRange {
        NSRange(location: range.location, length: range.length + 1)
    }

    private static func columnCount(_ cells: [StyleSpan]) -> Int {
        cells.reduce(0) { result, cell in
            if case .tableCell(let column, _) = cell.kind { max(result, column + 1) } else { result }
        }
    }

    private static func stay(_ selection: NSRange) -> TextEdit {
        TextEdit(range: NSRange(location: selection.location, length: 0), replacement: "", selection: selection)
    }

    /// Selects the cell's text without its padding spaces; an empty cell gets a caret in its middle.
    private static func select(_ cell: StyleSpan, in text: NSString) -> TextEdit {
        let content = text.substring(with: cell.range) as NSString
        var leading = 0
        while leading < content.length, content.character(at: leading) == unichar(UInt8(ascii: " ")) { leading += 1 }
        let trimmed = content.substring(from: leading).trimmingCharacters(in: .whitespaces) as NSString
        let selection = trimmed.length > 0
            ? NSRange(location: cell.range.location + leading, length: trimmed.length)
            : NSRange(location: cell.range.location + min(1, cell.range.length), length: 0)
        return TextEdit(range: NSRange(location: selection.location, length: 0), replacement: "", selection: selection)
    }

    /// Adds `|  |  |` below the row of `cell` and puts the caret in its first cell.
    private static func appendRow(after cell: StyleSpan, columns: Int, in text: NSString) -> TextEdit {
        var lineEnd = NSMaxRange(text.lineRange(for: NSRange(location: cell.range.location, length: 0)))
        if lineEnd > 0, text.character(at: lineEnd - 1) == unichar(UInt8(ascii: "\n")) { lineEnd -= 1 }
        let row = "\n|" + String(repeating: "  |", count: max(columns, 1))
        return TextEdit(range: NSRange(location: lineEnd, length: 0), replacement: row,
                        selection: NSRange(location: lineEnd + 3, length: 0))
    }
}
