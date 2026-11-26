import Foundation

/// A GFM table read from the source, edited as rows and columns, and written back as Markdown.
/// Used by the Table commands (insert/delete rows and columns, column alignment).
struct TableModel: Equatable {
    var header: [String]
    var alignments: [TableAlignment?]
    var rows: [[String]]

    var columnCount: Int { header.count }

    /// Parses the table lines (header, delimiter row, body rows). Nil if they don't look like a table.
    init?(markdown: String) {
        let lines = markdown.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 2 else { return nil }
        let delimiter = Self.cells(of: lines[1])
        guard !delimiter.isEmpty, delimiter.allSatisfy({ $0.allSatisfy { "-:".contains($0) } && $0.contains("-") }) else {
            return nil
        }
        let header = Self.cells(of: lines[0])
        let width = max(header.count, delimiter.count)
        func padded(_ cells: [String]) -> [String] { Array((cells + Array(repeating: "", count: width)).prefix(width)) }
        self.header = padded(header)
        alignments = padded(delimiter).map { cell in
            switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
            case (true, true): .center
            case (false, true): .right
            case (true, false): .left
            default: nil
            }
        }
        rows = lines.dropFirst(2).map { padded(Self.cells(of: $0)) }
    }

    init(header: [String], alignments: [TableAlignment?], rows: [[String]]) {
        self.header = header
        self.alignments = alignments
        self.rows = rows
    }

    /// The table as Markdown, one space of padding in each cell, and the location of each cell's
    /// content (`[row][column]`, row 0 being the header) in that text.
    func render() -> (markdown: String, cellStarts: [[Int]]) {
        var markdown = ""
        var cellStarts: [[Int]] = []
        func appendRow(_ cells: [String], record: Bool) {
            if !markdown.isEmpty { markdown += "\n" }
            var starts: [Int] = []
            markdown += "|"
            for cell in cells {
                markdown += " "
                starts.append((markdown as NSString).length)
                markdown += cell.isEmpty ? " |" : cell + " |"
            }
            if record { cellStarts.append(starts) }
        }
        appendRow(header, record: true)
        appendRow(alignments.map { alignment in
            switch alignment {
            case .left: ":---"
            case .center: ":---:"
            case .right: "---:"
            case nil: "---"
            }
        }, record: false)
        for row in rows { appendRow(row, record: true) }
        return (markdown, cellStarts)
    }

    /// Cells of one line: split on pipes not escaped with `\`, outer pipes dropped, cells trimmed.
    static func cells(of line: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in line {
            if character == "|" && !escaped {
                cells.append(current)
                current = ""
            } else {
                current.append(character)
            }
            escaped = character == "\\" && !escaped
        }
        cells.append(current)
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        if trimmedLine.hasPrefix("|"), !cells.isEmpty { cells.removeFirst() }
        if trimmedLine.hasSuffix("|"), trimmedLine.count > 1, !cells.isEmpty { cells.removeLast() }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

/// Row and column commands on the table that holds the caret.
enum TableStructure {
    enum Operation: Equatable {
        case insertColumn(after: Bool)
        case deleteColumn
        case insertRow(below: Bool)
        case deleteRow
        case align(TableAlignment)
    }

    /// Where the caret is: the table's source range (whole lines) and the cell (row 0 = header).
    struct Position: Equatable {
        var tableRange: NSRange
        var row: Int
        var column: Int
    }

    static func position(in text: String, selection: NSRange) -> Position? {
        let ns = text as NSString
        let caret = selection.location
        guard let table = MarkdownStyler.spans(for: text).first(where: { span in
            if case .tableRow = span.kind { return NSLocationInRange(caret, NSRange(location: span.blockRange.location,
                                                                                    length: span.blockRange.length + 1)) }
            return false
        })?.blockRange else { return nil }

        var range = ns.lineRange(for: table)
        if range.length > 0, ns.character(at: NSMaxRange(range) - 1) == unichar(UInt8(ascii: "\n")) { range.length -= 1 }
        let line = ns.lineRange(for: NSRange(location: min(caret, NSMaxRange(range)), length: 0))
        let lineIndex = ns.substring(with: NSRange(location: range.location, length: line.location - range.location))
            .components(separatedBy: "\n").count - 1
        // Pipes before the caret on its line give the column.
        let before = ns.substring(with: NSRange(location: line.location, length: max(caret - line.location, 0)))
        let column = max(TableModel.cells(of: before + "x").count - 1, 0)
        let row = lineIndex == 0 ? 0 : max(lineIndex - 1, 1)  // the delimiter row counts as the first body row
        return Position(tableRange: range, row: row, column: column)
    }

    /// Whether `operation` makes sense here (for enabling menu items).
    static func canPerform(_ operation: Operation, in text: String, selection: NSRange) -> Bool {
        guard let position = position(in: text, selection: selection),
              let model = TableModel(markdown: (text as NSString).substring(with: position.tableRange)) else { return false }
        switch operation {
        case .deleteColumn: return model.columnCount > 1
        case .deleteRow: return position.row > 0 && position.row <= model.rows.count
        case .insertRow(let below): return below || position.row > 0
        default: return true
        }
    }

    static func edit(_ operation: Operation, in text: String, selection: NSRange) -> TextEdit? {
        guard canPerform(operation, in: text, selection: selection),
              let position = position(in: text, selection: selection),
              var model = TableModel(markdown: (text as NSString).substring(with: position.tableRange)) else { return nil }
        let column = min(position.column, model.columnCount - 1)
        var row = min(position.row, model.rows.count)
        var targetColumn = column

        switch operation {
        case .insertColumn(let after):
            let index = after ? column + 1 : column
            model.header.insert("", at: index)
            model.alignments.insert(nil, at: index)
            for i in model.rows.indices { model.rows[i].insert("", at: index) }
            targetColumn = index
        case .deleteColumn:
            model.header.remove(at: column)
            model.alignments.remove(at: column)
            for i in model.rows.indices { model.rows[i].remove(at: column) }
            targetColumn = min(column, model.columnCount - 1)
        case .insertRow(let below):
            let index = below ? row : row - 1  // index in `rows`; row 0 (header) inserts at the top of the body
            model.rows.insert(Array(repeating: "", count: model.columnCount), at: index)
            row = index + 1
        case .deleteRow:
            model.rows.remove(at: row - 1)
            row = min(row, model.rows.count)  // the row that took its place, or the one above
        case .align(let alignment):
            model.alignments[column] = alignment
        }

        let (markdown, cellStarts) = model.render()
        let caret = position.tableRange.location + cellStarts[min(row, cellStarts.count - 1)][targetColumn]
        return TextEdit(range: position.tableRange, replacement: markdown, selection: NSRange(location: caret, length: 0))
    }
}
