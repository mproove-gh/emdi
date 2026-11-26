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

    @Test func tabNeverInsertsATabCharacterInATable() {
        for caret in 0...(table as NSString).length {
            #expect(tab(table, at: caret)?.text.contains("\t") == false)
        }
    }

    @Test func outsideTablesTabIsLeftAlone() {
        #expect(tab("Intro\n\n" + table, at: 2) == nil)
    }
}
