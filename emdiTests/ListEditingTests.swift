import Foundation
import Testing
@testable import emdi

/// Applies an edit function to `text` where `|` marks the caret, and returns the result with the new caret,
/// or nil when the function declines (the text view then does its default behaviour).
private func run(_ make: (NSString, NSRange) -> TextEdit?, _ marked: String) -> String? {
    var text = marked
    let caret = text.firstIndex(of: "|")!
    let location = text.utf16.distance(from: text.startIndex, to: caret)
    text.remove(at: caret)
    guard let edit = make(text as NSString, NSRange(location: location, length: 0)) else { return nil }
    let result = NSMutableString(string: text)
    result.replaceCharacters(in: edit.range, with: edit.replacement)
    result.insert("|", at: edit.selection.location)
    return result as String
}

struct ListEditingTests {
    @Test func returnContinuesBulletsNumbersAndTasks() {
        #expect(run(ListEditing.newline, "- item|") == "- item\n- |")
        #expect(run(ListEditing.newline, "* item|") == "* item\n* |")
        #expect(run(ListEditing.newline, "9. item|") == "9. item\n10. |")
        #expect(run(ListEditing.newline, "1) item|") == "1) item\n2) |")
        #expect(run(ListEditing.newline, "- [x] done|") == "- [x] done\n- [ ] |")
    }

    @Test func returnKeepsIndentationAndQuotes() {
        #expect(run(ListEditing.newline, "  - nested|") == "  - nested\n  - |")
        #expect(run(ListEditing.newline, "> - quoted|") == "> - quoted\n> - |")
        #expect(run(ListEditing.newline, "> a quote|") == "> a quote\n> |")
    }

    @Test func returnInTheMiddleSplitsTheItem() {
        #expect(run(ListEditing.newline, "- one| two") == "- one\n- | two")
    }

    @Test func returnOnAnEmptyItemEndsTheList() {
        #expect(run(ListEditing.newline, "- a\n- |") == "- a\n|")
        #expect(run(ListEditing.newline, "- [ ] |") == "|")
        #expect(run(ListEditing.newline, "> - |") == "> |")
        #expect(run(ListEditing.newline, "> |") == "|")
    }

    @Test func returnOutsideListsIsLeftAlone() {
        #expect(run(ListEditing.newline, "plain text|") == nil)
        #expect(run(ListEditing.newline, "**bold**|") == nil)
        #expect(run(ListEditing.newline, "|- item") == nil)  // caret before the marker
    }

    @Test func tabNestsAndShiftTabUnnests() {
        #expect(run(ListEditing.indent, "- a\n- b|") == "- a\n  - b|")
        #expect(run(ListEditing.indent, "1. a\n2. b|") == "1. a\n   1. b|")
        #expect(run(ListEditing.outdent, "- a\n  - b|") == "- a\n- b|")
        #expect(run(ListEditing.indent, "plain|") == nil)
    }
}

struct RenumberTests {
    private func renumbered(_ text: String, at location: Int = 0) -> String {
        guard let edit = ListEditing.renumber(in: text, touching: NSRange(location: location, length: 0),
                                              selection: NSRange(location: location, length: 0)) else { return text }
        return (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    @Test func countsUpFromTheFirstItem() {
        #expect(renumbered("1. a\n2. b\n2. c\n3. d") == "1. a\n2. b\n3. c\n4. d")
        #expect(renumbered("1. a\n3. c") == "1. a\n2. c")
        #expect(renumbered("5. a\n5. b") == "5. a\n6. b")  // a list may start anywhere
        #expect(renumbered("1) a\n1) b") == "1) a\n2) b")
    }

    @Test func nestedListsCountOnTheirOwn() {
        // A sub-list right under an item's text must start at 1: CommonMark reads "2." there as more text.
        #expect(renumbered("1. a\n   1. x\n   5. y\n2. b") == "1. a\n   1. x\n   2. y\n2. b")
        #expect(renumbered("1. a\n2. b\n   1. x\n4. c") == "1. a\n2. b\n   1. x\n3. c")
    }

    @Test func onlyTouchedListsChange() {
        let text = "1. a\n1. b\n\npara\n\n1. c\n1. d"
        #expect(renumbered(text, at: 0) == "1. a\n2. b\n\npara\n\n1. c\n1. d")
    }

    @Test func caretShiftsWhenANumberGetsLonger() {
        let text = "9. a\n9. b"
        let edit = ListEditing.renumber(in: text, touching: NSRange(location: 6, length: 0),
                                        selection: NSRange(location: 9, length: 0))
        #expect(edit?.replacement == "10")
        #expect(edit?.selection.location == 10)
    }

    @Test func listsInCodeBlocksAreLeftAlone() {
        #expect(ListEditing.renumber(in: "```\n1. a\n1. b\n```", touching: NSRange(location: 5, length: 0),
                                     selection: NSRange(location: 5, length: 0)) == nil)
    }

    @Test func indentRestartsNumberedItemsAtOne() {
        #expect(ListEditing.indent(in: "1. a\n2. b" as NSString, selection: NSRange(location: 8, length: 0))?.replacement
                == "   1. b")
    }
}
