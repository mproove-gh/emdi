import Foundation
import Testing
@testable import emdi

struct CodeHighlighterTests {
    /// The tokens as (kind, text) pairs, easier to read than ranges.
    private func tokens(_ code: String, _ language: String?) -> [(CodeTokenKind, String)] {
        CodeHighlighter.tokens(in: code, language: language).map { ($0.kind, (code as NSString).substring(with: $0.range)) }
    }

    private func texts(_ kind: CodeTokenKind, _ code: String, _ language: String) -> [String] {
        tokens(code, language).filter { $0.0 == kind }.map(\.1)
    }

    @Test func swift() {
        let code = #"@MainActor func greet(name: String) -> Int { let x = 42 // hi"# + "\n" + #"return "a\"b" }"#
        #expect(texts(.attribute, code, "swift") == ["@MainActor"])
        #expect(texts(.keyword, code, "swift") == ["func", "let", "return"])
        #expect(texts(.type, code, "swift") == ["String", "Int"])
        #expect(texts(.number, code, "swift") == ["42"])
        #expect(texts(.comment, code, "swift") == ["// hi"])
        #expect(texts(.string, code, "swift") == [#""a\"b""#])
    }

    @Test func pythonCommentsAndTripleQuotes() {
        let code = "def f():\n    \"\"\"Doc \"quoted\".\"\"\"\n    return None  # done"
        #expect(texts(.keyword, code, "py") == ["def", "return", "None"])
        #expect(texts(.string, code, "python") == ["\"\"\"Doc \"quoted\".\"\"\""])
        #expect(texts(.comment, code, "python") == ["# done"])
    }

    @Test func jsonKeysAndValues() {
        let code = #"{"name": "emdi", "size": 1.7, "ok": true}"#
        #expect(texts(.property, code, "json") == [#""name""#, #""size""#, #""ok""#])
        #expect(texts(.string, code, "json") == [#""emdi""#])
        #expect(texts(.number, code, "json") == ["1.7"])
        #expect(texts(.keyword, code, "json") == ["true"])
    }

    @Test func shellVariablesAndComments() {
        let code = "export PATH=\"$HOME/bin:${PATH}\" # set path\necho $1"
        #expect(texts(.keyword, code, "bash") == ["export", "echo"])
        #expect(texts(.comment, code, "sh") == ["# set path"])
        #expect(texts(.property, code, "zsh") == ["$1"])  // $HOME and ${PATH} are inside the string
    }

    @Test func sqlKeywordsIgnoreCase() {
        #expect(texts(.keyword, "SELECT id FROM users where x = 'a'", "sql") == ["SELECT", "FROM", "where"])
    }

    @Test func htmlTagsAttributesAndComments() {
        let code = #"<!-- note --><a href="/x" class='y'>Link</a>"#
        #expect(texts(.comment, code, "html") == ["<!-- note -->"])
        #expect(texts(.keyword, code, "html") == ["a", "a"])
        #expect(texts(.attribute, code, "html") == ["href", "class"])
        #expect(texts(.string, code, "html") == [#""/x""#, "'y'"])
    }

    @Test func unknownOrMissingLanguageIsPlain() {
        #expect(tokens("let x = 1", nil).isEmpty)
        #expect(tokens("let x = 1", "brainfuck").isEmpty)
    }

    @Test func languageInfoStringMayHaveExtras() {
        #expect(texts(.keyword, "let a = 1", "swift title=\"x\"") == ["let"])
    }

    @Test func numbersInsideIdentifiersAreNotNumbers() {
        #expect(texts(.number, "let utf8 = x2", "swift").isEmpty)
    }

    @Test func styledCodeBlockOffsetsPointIntoTheDocument() {
        let text = "Intro\n\n```swift\nlet a = \"é\"\n```"
        let spans = MarkdownStyler.spans(for: text)
        let strings = spans.filter { $0.kind == .codeToken(.string) }.map { (text as NSString).substring(with: $0.range) }
        let keywords = spans.filter { $0.kind == .codeToken(.keyword) }.map { (text as NSString).substring(with: $0.range) }
        #expect(strings == ["\"é\""])
        #expect(keywords == ["let"])
    }
}
