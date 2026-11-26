import Foundation
import Testing
@testable import emdi

/// Applies a command to `text` where `|` marks the caret, or `[` `]` mark the selection,
/// and returns the result in the same notation.
private func run(_ command: FormatCommand, _ marked: String) -> String {
    var text = marked
    let selection: NSRange
    if let start = text.firstIndex(of: "["), let end = text.firstIndex(of: "]"), marked.contains("[") && !marked.contains("|") {
        let location = text.utf16.distance(from: text.startIndex, to: start)
        let length = text.utf16.distance(from: start, to: end) - 1
        text.remove(at: end)
        text.remove(at: start)
        selection = NSRange(location: location, length: length)
    } else {
        let caret = text.firstIndex(of: "|")!
        selection = NSRange(location: text.utf16.distance(from: text.startIndex, to: caret), length: 0)
        text.remove(at: caret)
    }

    let edit = command.edit(in: text, selection: selection)
    let result = NSMutableString(string: text)
    result.replaceCharacters(in: edit.range, with: edit.replacement)
    if edit.selection.length == 0 {
        result.insert("|", at: edit.selection.location)
    } else {
        result.insert("]", at: NSMaxRange(edit.selection))
        result.insert("[", at: edit.selection.location)
    }
    return result as String
}

struct MarkdownFormatterTests {
    @Test func boldWrapsAndUnwraps() {
        #expect(run(.bold, "a [word] b") == "a **[word]** b")
        #expect(run(.bold, "a **[word]** b") == "a [word] b")
        #expect(run(.bold, "a [**word**] b") == "a [word] b")
        #expect(run(.bold, "a |") == "a **|**")
        #expect(run(.bold, "a **|**") == "a |")
    }

    @Test func italicAndBoldStayDistinct() {
        #expect(run(.italic, "**[x]**") == "***[x]***")
        #expect(run(.italic, "***[x]***") == "**[x]**")
        #expect(run(.bold, "***[x]***") == "*[x]*")
    }

    @Test func otherInlineStyles() {
        #expect(run(.strikethrough, "[gone]") == "~~[gone]~~")
        #expect(run(.inlineCode, "[x]") == "`[x]`")
        #expect(run(.link, "[emdi]") == "[emdi]([url])")
    }

    @Test func headingsSetChangeAndToggle() {
        #expect(run(.heading2, "Tit|le") == "## Tit|le")
        #expect(run(.heading1, "## Tit|le") == "# Tit|le")
        #expect(run(.heading2, "## Tit|le") == "Tit|le")
        #expect(run(.paragraph, "### Tit|le") == "Tit|le")
    }

    @Test func listsToggleOnEveryLine() {
        #expect(run(.bulletList, "[a\nb]") == "[- a\n- b]")
        #expect(run(.bulletList, "[- a\n- b]") == "[a\nb]")
        #expect(run(.numberedList, "[- a\n- b]") == "[1. a\n2. b]")
        #expect(run(.taskList, "- it|em") == "- [ ] it|em")
        #expect(run(.quote, "[a\n\nb]") == "[> a\n\n> b]")
    }

    @Test func codeBlockWrapsLines() {
        #expect(run(.codeBlock, "[let a = 1]") == "```|\nlet a = 1\n```")
        #expect(run(.codeBlock, "|") == "```|\n\n```")
    }

    @Test func blocksInsertOnTheirOwnLine() {
        #expect(run(.horizontalRule, "para|") == "para\n\n---\n|")
        #expect(run(.horizontalRule, "para\n|") == "para\n\n---\n|")
        #expect(run(.horizontalRule, "para\n\n|") == "para\n\n---\n|")
        #expect(run(.table, "|") == "| [Column 1] | Column 2 |\n| --- | --- |\n|  |  |\n")
    }
}
