import Foundation
import Testing
@testable import emdi

struct ClearFormattingTests {
    /// Clears formatting with the selection on `«`…`»` (or the caret on `|`); returns the result in the same notation.
    private func clear(_ marked: String) -> String {
        var text = marked
        let selection: NSRange
        if let caret = text.firstIndex(of: "|"), !text.contains("«") {
            selection = NSRange(location: text.utf16.distance(from: text.startIndex, to: caret), length: 0)
            text.remove(at: caret)
        } else {
            let open = text.firstIndex(of: "«")!
            let location = text.utf16.distance(from: text.startIndex, to: open)
            text.remove(at: open)
            let close = text.firstIndex(of: "»")!
            let length = text.utf16.distance(from: text.startIndex, to: close) - location
            text.remove(at: close)
            selection = NSRange(location: location, length: length)
        }
        let edit = FormatCommand.clearFormatting.edit(in: text, selection: selection)
        let result = NSMutableString(string: (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement))
        if edit.selection.length == 0 {
            result.insert("|", at: edit.selection.location)
        } else {
            result.insert("»", at: NSMaxRange(edit.selection))
            result.insert("«", at: edit.selection.location)
        }
        return result as String
    }

    @Test func removesInlineFormattingAndKeepsTheSelection() {
        #expect(clear("A «**bold** and *it*» here") == "A «bold and it» here")
        #expect(clear("«~~gone~~ `code`»") == "«gone code»")
        #expect(clear("x **bo|ld** y") == "x bo|ld y")  // caret only: the element under it
    }

    @Test func linksAndImagesKeepTheirText() {
        #expect(clear("See «[a](http://x.io)» now") == "See «a» now")
        #expect(clear("«![a cat](cat.png)»") == "«a cat»")
    }

    @Test func untouchedFormattingStays() {
        #expect(clear("**keep** and «*this*»") == "**keep** and «this»")
    }

    @Test func removesLinePrefixes() {
        #expect(clear("«# Title»") == "«Title»")
        #expect(clear("«- one\n- [ ] two\n> three»") == "«one\ntwo\nthree»")
        #expect(clear("«1. first»") == "«first»")
    }

    @Test func removesCodeFences() {
        #expect(clear("«```swift\nlet a = 1\n```»") == "«let a = 1\n»")
    }

    @Test func tablesAreLeftAlone() {
        let table = "| a | b |\n| --- | --- |\n| **x** | y |"
        #expect(clear("«" + table + "»") == "«" + table.replacingOccurrences(of: "**x**", with: "x") + "»")
    }
}
