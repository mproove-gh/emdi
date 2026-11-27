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

    /// Return in a table: go to the cell below (same column), or add a row when on the last one.
    /// Return never splits a table row.
    static func newline(in text: NSString, cells: [StyleSpan], selection: NSRange) -> TextEdit? {
        let caret = selection.location
        guard let block = Set(cells.map(\.blockRange)).first(where: { NSLocationInRange(caret, extendedRange($0)) }) else {
            return nil
        }
        let table = cells.filter { $0.blockRange == block }.sorted { $0.range.location < $1.range.location }
        guard let current = table.last(where: { $0.range.location <= caret }) ?? table.first else { return stay(selection) }
        func lineStart(_ cell: StyleSpan) -> Int { text.lineRange(for: NSRange(location: cell.range.location, length: 0)).location }
        guard case .tableCell(let column, _) = current.kind else { return stay(selection) }
        let below = table.filter { lineStart($0) > lineStart(current) }
        guard let nextLine = below.map(lineStart).min() else {
            return appendRow(after: current, columns: columnCount(table), in: text)
        }
        let nextRow = below.filter { lineStart($0) == nextLine }
        let target = nextRow.first { if case .tableCell(let c, _) = $0.kind { c == column } else { false } } ?? nextRow.last!
        return select(target, in: text)
    }

    /// What an edit typed or deleted by the user should do in a table so the table keeps its shape:
    /// cell separators (`|`) and row breaks are never removed, and new line breaks become spaces.
    /// Returns nil when the edit touches no table structure (let it through), or the replacement edit to
    /// make instead. An edit that would only remove structure becomes a no-op (same text, same selection).
    static func protectingStructure(in text: NSString, tables: [NSRange], range: NSRange,
                                    replacement: String) -> TextEdit? {
        guard tables.contains(where: { NSIntersectionRange($0, range).length > 0
                                       || (range.length == 0 && NSLocationInRange(range.location, $0)) }) else {
            return nil
        }
        let removed = text.substring(with: range)
        let pipe: Character = "|"
        let touchesStructure = removed.contains(pipe) || removed.contains("\n") || replacement.contains("\n")
        guard touchesStructure else { return nil }
        // Keep the structure that was selected; put what was typed or pasted (on one line) before it.
        let kept = String(removed.filter { $0 == pipe || $0 == "\n" })
        let inserted = replacement.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
        let caret = range.location + (inserted as NSString).length
        if inserted.isEmpty && kept == removed {
            // Only structure would go (e.g. Backspace right after a hidden `|`): do nothing.
            return TextEdit(range: NSRange(location: range.location, length: 0), replacement: "",
                            selection: NSRange(location: range.location + (range.length > 0 ? range.length : 0), length: 0))
        }
        return TextEdit(range: range, replacement: inserted + kept, selection: NSRange(location: caret, length: 0))
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
    /// Where a click in `cell` puts the caret, given the index the click hit: at the start of an empty
    /// cell (where Tab would put it), otherwise clamped to the cell's text, never in its padding.
    /// The padding is drawn wider than its spaces (kern on the hidden pipes), so a click in an empty
    /// cell would otherwise land anywhere in it, or even in the next cell.
    static func caret(forClickIn cell: NSRange, of text: NSString, at index: Int) -> Int {
        let content = text.substring(with: cell) as NSString
        var leading = 0
        while leading < content.length, content.character(at: leading) == unichar(UInt8(ascii: " ")) { leading += 1 }
        let trimmed = content.substring(from: leading).trimmingCharacters(in: .whitespaces) as NSString
        guard trimmed.length > 0 else { return cell.location + min(1, cell.length) }
        let start = cell.location + leading
        return min(max(index, start), start + trimmed.length)
    }

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
