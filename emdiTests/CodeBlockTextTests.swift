import Testing
@testable import emdi

struct CodeBlockTextTests {
    @Test func fencedBlockDropsFences() {
        #expect(CodeBlockText.content(of: "```swift\nlet a = 1\n\nlet b = 2\n```") == "let a = 1\n\nlet b = 2")
        #expect(CodeBlockText.content(of: "~~~\nx\n~~~\n") == "x")
    }

    @Test func unclosedFenceKeepsAllCode() {
        #expect(CodeBlockText.content(of: "```\nx\ny") == "x\ny")
    }

    @Test func languageComesFromTheOpeningFence() {
        #expect(CodeBlockText.language(of: "```python\nx = 1\n```") == "python")
        #expect(CodeBlockText.language(of: "~~~ bash title=\"run\"\nls\n~~~") == "bash")
        #expect(CodeBlockText.language(of: "  ```js{1,3}\nx\n```") == "js")
        #expect(CodeBlockText.language(of: "```\nplain\n```") == nil)
        #expect(CodeBlockText.language(of: "    indented code") == nil)
    }

    @Test func indentedBlockDropsIndentation() {
        #expect(CodeBlockText.content(of: "    if x {\n        y()\n    }") == "if x {\n    y()\n}")
    }
}
