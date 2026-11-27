import Foundation
import Testing
@testable import emdi

struct LinkTargetTests {
    let doc = URL(fileURLWithPath: "/Users/me/notes/today.md")

    @Test func findsTheLinkUnderAnOffset() {
        let text = "See [the docs](https://example.com/a) and [ref][r].\n\n[r]: notes/other.md\n"
        #expect(LinkTarget.link(at: 6, in: text)?.destination == "https://example.com/a")
        #expect(LinkTarget.link(at: 44, in: text)?.destination == "notes/other.md")
        #expect(LinkTarget.link(at: 1, in: text) == nil)
    }

    @Test func resolvesDestinations() {
        #expect(LinkTarget.resolve("https://example.com", relativeTo: nil) == .url(URL(string: "https://example.com")!))
        #expect(LinkTarget.resolve("mailto:a@b.c", relativeTo: nil) == .url(URL(string: "mailto:a@b.c")!))
        #expect(LinkTarget.resolve("www.example.com", relativeTo: nil) == .url(URL(string: "https://www.example.com")!))
        #expect(LinkTarget.resolve("../plan%20B.md#top", relativeTo: doc)
                == .file(URL(fileURLWithPath: "/Users/me/plan B.md")))
        #expect(LinkTarget.resolve("/tmp/x.pdf", relativeTo: nil) == .file(URL(fileURLWithPath: "/tmp/x.pdf")))
        #expect(LinkTarget.resolve("other.md", relativeTo: nil) == nil)
        #expect(LinkTarget.resolve("#Tables-and-more", relativeTo: nil) == .anchor("Tables-and-more"))
        #expect(LinkTarget.resolve("", relativeTo: doc) == nil)
    }

    @Test func findsHeadingsByAnchor() {
        let text = "# Intro\n\n## 6. Tables & more\n\ntext\n\n## Intro\n"
        #expect(LinkTarget.slug("6. Tables & more") == "6-tables--more")
        #expect(LinkTarget.heading(forAnchor: "6-tables--more", in: text)?.location == 9)
        #expect(LinkTarget.heading(forAnchor: "intro-1", in: text)?.location == 36)
        #expect(LinkTarget.heading(forAnchor: "nope", in: text) == nil)
    }
}
