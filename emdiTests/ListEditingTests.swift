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
        #expect(run(ListEditing.indent, "1. a\n2. b|") == "1. a\n   2. b|")
        #expect(run(ListEditing.outdent, "- a\n  - b|") == "- a\n- b|")
        #expect(run(ListEditing.indent, "plain|") == nil)
    }
}
