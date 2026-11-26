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

    @Test func indentedBlockDropsIndentation() {
        #expect(CodeBlockText.content(of: "    if x {\n        y()\n    }") == "if x {\n    y()\n}")
    }
}
