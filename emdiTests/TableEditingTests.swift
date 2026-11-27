import Foundation
import Testing
@testable import emdi

struct TableEditingTests {
    private let table = "| a | bb |\n| --- | --- |\n| 1 | 2 |"

    /// Applies Tab (or Shift-Tab) with the caret at `caret`; returns the new text and the selected text.
    private func tab(_ text: String, at caret: Int, backwards: Bool = false) -> (text: String, selected: String, caret: Int)? {
        let cells = MarkdownStyler.spans(for: text).filter { if case .tableCell = $0.kind { true } else { false } }
        guard let edit = TableEditing.tab(in: text as NSString, cells: cells, selection: NSRange(location: caret, length: 0),
                                          backwards: backwards) else { return nil }
        let result = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement) as NSString
        return (result as String, result.substring(with: edit.selection), edit.selection.location)
    }

    @Test func tabMovesToTheNextCellAndSelectsIt() {
        #expect(tab(table, at: 3)?.selected == "bb")             // in "a" → "bb"
        #expect(tab(table, at: 8)?.selected == "1")              // end of header row → first body cell
        #expect(tab(table, at: 9)?.selected == "1")              // right after the last pipe of the row
        #expect(tab(table, at: 15)?.selected == "1")             // in the hidden delimiter row
    }

    @Test func shiftTabMovesBack() {
        let one = (table as NSString).range(of: "1").location
        #expect(tab(table, at: one, backwards: true)?.selected == "bb")
        #expect(tab(table, at: 2, backwards: true)?.text == table)  // first cell: stays, inserts nothing
    }

    @Test func tabInTheLastCellAddsARow() {
        let result = tab(table, at: (table as NSString).length)
        #expect(result?.text == table + "\n|  |  |")
        #expect(result?.caret == (table as NSString).length + 3)
    }

    @Test func clickingACellPutsTheCaretInItsText() {
        let text = "| a |  | ccc |" as NSString
        let empty = NSRange(location: 5, length: 2)     // "  "
        let filled = NSRange(location: 8, length: 5)    // " ccc "
        // An empty cell: always its start, wherever the click landed.
        #expect(TableEditing.caret(forClickIn: empty, of: text, at: 5) == 6)
        #expect(TableEditing.caret(forClickIn: empty, of: text, at: 7) == 6)
        #expect(TableEditing.caret(forClickIn: empty, of: text, at: 10) == 6)  // hit the next cell
        // A filled cell: clamped to "ccc".
        #expect(TableEditing.caret(forClickIn: filled, of: text, at: 8) == 9)
        #expect(TableEditing.caret(forClickIn: filled, of: text, at: 10) == 10)
        #expect(TableEditing.caret(forClickIn: filled, of: text, at: 12) == 12)
        #expect(TableEditing.caret(forClickIn: filled, of: text, at: 14) == 12)
        // A cell with no padding at all.
        #expect(TableEditing.caret(forClickIn: NSRange(location: 1, length: 0), of: "||" as NSString, at: 1) == 1)
    }

    @Test func tabNeverInsertsATabCharacterInATable() {
        for caret in 0...(table as NSString).length {
            #expect(tab(table, at: caret)?.text.contains("\t") == false)
        }
    }

    @Test func outsideTablesTabIsLeftAlone() {
        #expect(tab("Intro\n\n" + table, at: 2) == nil)
    }

    /// Applies a user edit (replace `range` with `replacement`) through the structure protection.
    private func userEdit(_ text: String, range: NSRange, replacement: String) -> String {
        let tables = Array(Set(MarkdownStyler.spans(for: text).map { span -> NSRange? in
            if case .tableRow = span.kind { span.blockRange } else { nil }
        }.compactMap { $0 }))
        let edit = TableEditing.protectingStructure(in: text as NSString, tables: tables, range: range, replacement: replacement)
            ?? TextEdit(range: range, replacement: replacement, selection: range)
        return (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    @Test func backspaceNeverEatsACellSeparator() {
        let pipe = (table as NSString).range(of: "| 2").location
        #expect(userEdit(table, range: NSRange(location: pipe, length: 1), replacement: "") == table)
        // Deleting a character inside a cell is normal.
        #expect(userEdit(table, range: NSRange(location: pipe - 2, length: 1), replacement: "") == "| a | bb |\n| --- | --- |\n|  | 2 |")
    }

    @Test func deletingAcrossCellsEmptiesThemButKeepsTheRow() {
        let range = (table as NSString).range(of: "1 | 2")
        #expect(userEdit(table, range: range, replacement: "") == "| a | bb |\n| --- | --- |\n| | |")
        #expect(userEdit(table, range: range, replacement: "x") == "| a | bb |\n| --- | --- |\n| x| |")
    }

    @Test func lineBreaksInATableBecomeSpaces() {
        let at = (table as NSString).range(of: "1").location
        #expect(userEdit(table, range: NSRange(location: at, length: 1), replacement: "one\ntwo") == "| a | bb |\n| --- | --- |\n| one two | 2 |")
    }

    @Test func editsOutsideTablesAreUntouched() {
        let text = "Intro | x\n\n" + table
        #expect(TableEditing.protectingStructure(in: text as NSString, tables: [NSRange(location: 12, length: 5)],
                                                 range: NSRange(location: 6, length: 1), replacement: "") == nil)
    }

    @Test func returnMovesDownAndAddsARowAtTheEnd() {
        let cells = MarkdownStyler.spans(for: table).filter { if case .tableCell = $0.kind { true } else { false } }
        let inB = (table as NSString).range(of: "bb").location
        let down = TableEditing.newline(in: table as NSString, cells: cells, selection: NSRange(location: inB, length: 0))
        #expect(down.map { (table as NSString).substring(with: $0.selection) } == "2")
        let last = TableEditing.newline(in: table as NSString, cells: cells,
                                        selection: NSRange(location: (table as NSString).length - 2, length: 0))
        #expect(last?.replacement == "\n|  |  |")
    }
}
