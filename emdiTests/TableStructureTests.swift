import Foundation
import Testing
@testable import emdi

struct TableStructureTests {
    private let table = "| A | B |\n| --- | :-: |\n| 1 | 2 |\n| 3 | 4 |"

    /// Runs `command` with the caret just before `marker` (first occurrence); returns the text,
    /// and the text from the new caret to the end of its line.
    private func run(_ command: FormatCommand, at marker: String, in text: String? = nil) -> (text: String, caretLine: String) {
        let text = text ?? table
        let location = (text as NSString).range(of: marker).location
        let edit = command.edit(in: text, selection: NSRange(location: location, length: 0))
        let result = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement) as NSString
        let line = result.lineRange(for: NSRange(location: edit.selection.location, length: 0))
        return (result as String,
                result.substring(with: NSRange(location: edit.selection.location, length: NSMaxRange(line) - edit.selection.location))
                    .trimmingCharacters(in: .newlines))
    }

    @Test func parsesAndRendersTables() {
        let model = TableModel(markdown: "|A|B|\n|:--|--:|\n|1|2|")
        #expect(model?.header == ["A", "B"])
        #expect(model?.alignments == [.left, .right])
        #expect(model?.rows == [["1", "2"]])
        #expect(model?.render().markdown == "| A | B |\n| :--- | ---: |\n| 1 | 2 |")
        #expect(TableModel.cells(of: "| a \\| b | c |") == ["a \\| b", "c"])
    }

    // Edited tables are rewritten with one space of padding and normalized delimiters (`:-:` → `:---:`).
    @Test func insertsColumnsEverywhereIncludingTheDelimiterRow() {
        let right = run(.insertColumnRight, at: "1")
        #expect(right.text == "| A |  | B |\n| --- | --- | :---: |\n| 1 |  | 2 |\n| 3 |  | 4 |")
        #expect(right.caretLine == " | 2 |")  // caret in the new, empty cell of the same row
        #expect(run(.insertColumnLeft, at: "B").text == "| A |  | B |\n| --- | --- | :---: |\n| 1 |  | 2 |\n| 3 |  | 4 |")
    }

    @Test func deletesTheCaretsColumn() {
        let result = run(.deleteColumn, at: "2")
        #expect(result.text == "| A |\n| --- |\n| 1 |\n| 3 |")
        #expect(!FormatCommand.deleteColumn.isAvailable(in: "| A |\n| --- |\n| 1 |", selection: NSRange(location: 2, length: 0)))
    }

    @Test func insertsAndDeletesRows() {
        #expect(run(.insertRowBelow, at: "1").text == "| A | B |\n| --- | :---: |\n| 1 | 2 |\n|  |  |\n| 3 | 4 |")
        #expect(run(.insertRowAbove, at: "1").text == "| A | B |\n| --- | :---: |\n|  |  |\n| 1 | 2 |\n| 3 | 4 |")
        #expect(run(.insertRowBelow, at: "A").text == "| A | B |\n| --- | :---: |\n|  |  |\n| 1 | 2 |\n| 3 | 4 |")
        let deleted = run(.deleteRow, at: "1")
        #expect(deleted.text == "| A | B |\n| --- | :---: |\n| 3 | 4 |")
        #expect(deleted.caretLine == "3 | 4 |")
    }

    @Test func theHeaderRowCanNeitherMoveNorGo() {
        let caretInHeader = NSRange(location: 2, length: 0)
        #expect(!FormatCommand.deleteRow.isAvailable(in: table, selection: caretInHeader))
        #expect(!FormatCommand.insertRowAbove.isAvailable(in: table, selection: caretInHeader))
    }

    @Test func setsColumnAlignment() {
        #expect(run(.alignColumnRight, at: "3").text == "| A | B |\n| ---: | :---: |\n| 1 | 2 |\n| 3 | 4 |")
        #expect(run(.alignColumnCenter, at: "4").text.contains("| --- | :---: |"))
    }

    @Test func outsideATableNothingChanges() {
        let text = "Intro\n\n" + table
        #expect(!FormatCommand.insertRowBelow.isAvailable(in: text, selection: NSRange(location: 2, length: 0)))
        #expect(run(.insertRowBelow, at: "ntro", in: text).text == text)
    }
}
