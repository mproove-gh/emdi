import AppKit
import Testing
@testable import emdi

/// Clicks and hovering in a real editor: table cells, code block labels, the pointer over controls.
@MainActor
struct EditorInteractionTests {
    private static let document = """
        Some text first.

        | Name | Empty | Notes |
        | ---- | ----- | ----- |
        | Alpha |  | Long note here |
        | Beta | x | y |

        ```python
        print("hi")
        ```

        ```
        no language
        ```

        - [ ] A task

        End.
        """

    /// The borders and paragraph offset of the table row whose line contains `needle`.
    private func row(_ needle: String, in host: EditorTestHost) throws
        -> (fragment: TableRowLayoutFragment, borders: [CGFloat], start: Int) {
        let location = try host.location(of: needle)
        let fragment = try #require(host.fragment(at: location) as? TableRowLayoutFragment)
        let start = (host.textView.string as NSString).lineRange(for: NSRange(location: location, length: 0)).location
        return (fragment, fragment.cellBorders.map(\.x), start)
    }

    private func clickInRow(_ needle: String, column: Int, fraction: CGFloat, in host: EditorTestHost) throws {
        let (fragment, borders, _) = try row(needle, in: host)
        let line = try #require(fragment.textLineFragments.first)
        let x = borders[column] + (borders[column + 1] - borders[column]) * fraction
        host.click(at: host.viewPoint(CGPoint(x: x, y: line.typographicBounds.midY), in: fragment))
    }

    @Test func clickingAnEmptyCellPutsTheCaretAtItsStart() throws {
        let host = try EditorTestHost(text: Self.document)
        defer { host.close() }
        let (_, _, start) = try row("| Alpha |", in: host)
        let emptyCellStart = start + ("| Alpha |" as NSString).length + 1  // after the pipe and one space
        for fraction: CGFloat in [0.1, 0.5, 0.9] {
            try clickInRow("| Alpha |", column: 1, fraction: fraction, in: host)
            #expect(host.textView.selectedRange() == NSRange(location: emptyCellStart, length: 0), "fraction \(fraction)")
        }
    }

    @Test func clickingPastACellsTextPutsTheCaretAtItsEnd() throws {
        let host = try EditorTestHost(text: Self.document)
        defer { host.close() }
        try clickInRow("| Beta |", column: 0, fraction: 0.95, in: host)
        let afterBeta = try host.location(of: "Beta |") + 4
        #expect(host.textView.selectedRange() == NSRange(location: afterBeta, length: 0))
        try clickInRow("| Beta |", column: 2, fraction: 0.95, in: host)
        let afterY = try host.location(of: "x | y |") + 5
        #expect(host.textView.selectedRange() == NSRange(location: afterY, length: 0))
    }

    @Test func codeBlocksShowTheirLanguageWhileTheFenceIsHidden() throws {
        let host = try EditorTestHost(text: Self.document)
        defer { host.close() }
        let fence = try host.location(of: "```python")
        host.textView.setSelectedRange(NSRange(location: 0, length: 0))
        host.pump()
        let hidden = try #require(host.fragment(at: fence) as? CodeBlockLayoutFragment)
        #expect(hidden.languageLabel?.string == "python")
        let hiddenHeight = hidden.layoutFragmentFrame.height
        let plain = try #require(host.fragment(at: try host.location(of: "```\nno language")) as? CodeBlockLayoutFragment)
        #expect(plain.languageLabel == nil)

        // In the block the fence itself shows, so no label; the line keeps its height.
        host.textView.setSelectedRange(NSRange(location: try host.location(of: "print"), length: 0))
        host.pump()
        let shown = try #require(host.fragment(at: fence) as? CodeBlockLayoutFragment)
        #expect(shown.languageLabel == nil)
        #expect(abs(shown.layoutFragmentFrame.height - hiddenHeight) < 1)
        // The label is drawing only: copying the block still gives just the code.
        #expect(CodeBlockText.content(of: "```python\nprint(\"hi\")\n```") == "print(\"hi\")")
    }

    @Test func controlsGetTheArrowPointer() throws {
        let host = try EditorTestHost(text: Self.document)
        defer { host.close() }
        let checkbox = try host.checkboxPoint("A task")
        #expect(host.textView.isOverControl(checkbox))
        #expect(!host.textView.isOverControl(NSPoint(x: checkbox.x + 120, y: checkbox.y)))

        // Hover the code block: the copy button appears and counts as a control.
        let code = try #require(host.fragment(at: try host.location(of: "print")))
        let line = try #require(code.textLineFragments.first)
        let inBlock = host.viewPoint(CGPoint(x: 40, y: line.typographicBounds.midY), in: code)
        host.textView.mouseMoved(with: NSEvent.mouseEvent(
            with: .mouseMoved, location: host.textView.convert(inBlock, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: host.window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!)
        let button = try #require(host.textView.subviews.first { $0 is NSButton && !$0.isHidden })
        #expect(host.textView.isOverControl(NSPoint(x: button.frame.midX, y: button.frame.midY)))
        #expect(!host.textView.isOverControl(inBlock))
    }

    @Test func bulletsDependOnDepthAndNumbersLineUp() throws {
        let host = try EditorTestHost(text: "- one\n  - two\n    - three\n      - four\n\n9. nine\n10. ten\n")
        defer { host.close() }
        var textStarts: [CGFloat] = []
        for (depth, word) in ["one", "two", "three", "four"].enumerated() {
            let location = try host.location(of: word)
            let fragment = try #require(host.fragment(at: location) as? ListItemLayoutFragment, "\(word)")
            #expect(fragment.depth == depth)
            let line = try #require(fragment.textLineFragments.first)
            let offset = location - (host.textView.string as NSString).lineRange(for: NSRange(location: location, length: 0)).location
            textStarts.append(fragment.layoutFragmentFrame.minX + line.typographicBounds.minX + line.locationForCharacter(at: offset).x)
        }
        // Each level is indented by more than the two source spaces.
        for (outer, inner) in zip(textStarts, textStarts.dropFirst()) { #expect(inner - outer > 20) }

        // Numbers are right-aligned: the text of 9. and 10. starts at the same place.
        func textStart(_ word: String) throws -> CGFloat {
            let location = try host.location(of: word)
            let fragment = try #require(host.fragment(at: location))
            let line = try #require(fragment.textLineFragments.first)
            let offset = location - (host.textView.string as NSString).lineRange(for: NSRange(location: location, length: 0)).location
            return fragment.layoutFragmentFrame.minX + line.typographicBounds.minX + line.locationForCharacter(at: offset).x
        }
        let nine = try textStart("nine"), ten = try textStart("ten")
        #expect(abs(nine - ten) < 0.5, "nine \(nine) ten \(ten)")
    }

    @Test func quotesAreDrawnAsBarsAndBackspaceRemovesALevel() throws {
        let host = try EditorTestHost(text: "> one\n>\n> > two\n> - item\n")
        defer { host.close() }
        host.textView.setSelectedRange(NSRange(location: 0, length: 0))
        host.pump()
        let one = try #require(host.fragment(at: try host.location(of: "one")) as? MarkdownLayoutFragment)
        #expect(one.quoteBars?.depth == 1)
        let two = try #require(host.fragment(at: try host.location(of: "two")) as? MarkdownLayoutFragment)
        #expect(two.quoteBars?.depth == 2)
        // A quoted list item keeps its bullet and gets the bar too.
        let item = try #require(host.fragment(at: try host.location(of: "item")) as? ListItemLayoutFragment)
        #expect(item.quoteBars?.depth == 1)
        // The blank `>` line between paragraphs is drawn short.
        #expect(try #require(host.fragment(at: 6)).layoutFragmentFrame.height < one.layoutFragmentFrame.height)

        // Backspace at the start of the quoted text removes the innermost level.
        host.textView.setSelectedRange(NSRange(location: try host.location(of: "two"), length: 0))
        host.textView.deleteBackward(nil)
        #expect(host.textView.string == "> one\n>\n> two\n> - item\n")
    }

    @Test func calloutsDrawATitleThatTheCaretReveals() throws {
        let host = try EditorTestHost(text: "Intro.\n\n> [!TIP]\n> Body text.\n\n> [!NOTE] Own title\n> More.\n")
        defer { host.close() }
        host.textView.setSelectedRange(NSRange(location: 0, length: 0))
        host.pump()
        let tipLine = try host.location(of: "[!TIP]")
        let title = try #require(host.fragment(at: tipLine) as? MarkdownLayoutFragment)
        #expect(title.callout == .tip)
        #expect(title.calloutTitle?.string == "Tip")
        let hiddenHeight = title.layoutFragmentFrame.height
        let body = try #require(host.fragment(at: try host.location(of: "Body")) as? MarkdownLayoutFragment)
        #expect(body.callout == .tip && body.calloutTitle == nil)
        // A title after the marker replaces the kind's name: only the icon is drawn.
        let own = try #require(host.fragment(at: try host.location(of: "[!NOTE]")) as? MarkdownLayoutFragment)
        #expect(own.calloutTitle?.string == "")

        // On the first line the marker shows as text, without a drawn title; the line keeps its height.
        host.textView.setSelectedRange(NSRange(location: tipLine + 3, length: 0))
        host.pump()
        let shown = try #require(host.fragment(at: tipLine) as? MarkdownLayoutFragment)
        #expect(shown.calloutTitle == nil)
        #expect(abs(shown.layoutFragmentFrame.height - hiddenHeight) < 1)
    }

    @Test func narrowTablesKeepTheirWidthAndWideOnesFillTheColumn() throws {
        let wideCell = String(repeating: "word ", count: 14)
        let host = try EditorTestHost(text: "| A | B |\n|---|---|\n| 1 | 2 |\n\n| Long | Text |\n|---|---|\n| \(wideCell)| x |\n")
        defer { host.close() }
        let column = try #require(host.textView.textContainer?.size.width)
        func width(_ needle: String) throws -> CGFloat {
            let fragment = try #require(host.fragment(at: try host.location(of: needle)) as? TableRowLayoutFragment)
            let borders = fragment.cellBorders.map(\.x)
            return try #require(borders.max()) - (try #require(borders.min()))
        }
        #expect(try width("| 1 | 2 |") < column / 3)
        #expect(try width("| Long |") > column - 20)
    }

    @Test func fencedBlocksHaveAHeaderAndTightLines() throws {
        let host = try EditorTestHost(text: "Intro.\n\n```swift\nlet a = 1\nlet b = 2\n```\n\n```\nplain\n```\n\n    indented\n\nEnd.\n")
        defer { host.close() }
        host.textView.setSelectedRange(NSRange(location: 0, length: 0))
        host.pump()
        let swift = try #require(host.fragment(at: try host.location(of: "```swift")) as? CodeBlockLayoutFragment)
        #expect(swift.edges.contains(.header))
        #expect(swift.languageLabel?.string == "swift" && swift.copyLabel?.string == "Copy")
        // A block without a language still gets the header, with Copy.
        let plain = try #require(host.fragment(at: try host.location(of: "```\nplain")) as? CodeBlockLayoutFragment)
        #expect(plain.edges.contains(.header) && plain.languageLabel == nil && plain.copyLabel != nil)
        // An indented block has no fence, so no header.
        let indented = try #require(host.fragment(at: try host.location(of: "    indented")) as? CodeBlockLayoutFragment)
        #expect(!indented.edges.contains(.header))
        // Code lines are 1.32 × the code size, whatever the font's own line height.
        let line = try #require(host.fragment(at: try host.location(of: "let b")))
        let font = try #require(host.textView.textStorage?.attribute(.font, at: try host.location(of: "let b"), effectiveRange: nil) as? NSFont)
        #expect(abs(line.layoutFragmentFrame.height - (font.pointSize * 1.32).rounded()) < 0.5)
    }

    @Test func missingLocalImagesGetAPlaceholderAndLoadedOnesOpenInQuickLook() throws {
        let host = try EditorTestHost()  // showcase.md, so relative paths resolve
        defer { host.close() }
        host.textView.setSelectedRange(NSRange(location: 0, length: 0))
        host.pump()
        let missing = try #require(host.fragment(at: try host.location(of: "![This file does not exist]")) as? ImageLayoutFragment)
        #expect(missing.blockImage?.missingLabel?.string == "Image not found: images/missing.png")
        // Remote images are never loaded and keep their link styling.
        #expect(!(host.fragment(at: try host.location(of: "![Remote image]")) is ImageLayoutFragment))

        // A double-click target: the loaded image's file, and nothing for the placeholder.
        let large = try #require(host.fragment(at: try host.location(of: "![The emdi icon, large]")) as? ImageLayoutFragment)
        let rect = try #require(large.imageRect)
        let inImage = host.viewPoint(CGPoint(x: rect.midX, y: rect.midY), in: large)
        #expect(host.textView.imageURL(at: inImage)?.lastPathComponent == "emdi-icon-large.png")
        let placeholder = try #require(missing.imageRect)
        #expect(host.textView.imageURL(at: host.viewPoint(CGPoint(x: placeholder.midX, y: placeholder.midY), in: missing)) == nil)
    }

    @Test func pastedImageDataIsSavedNextToTheDocument() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "emdi-paste-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let host = try EditorTestHost(text: "Before.\n")
        defer { host.close() }
        host.textView.documentURL = folder.appending(path: "doc.md")
        host.textView.setSelectedRange(NSRange(location: 8, length: 0))

        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 3, bitsPerSample: 8, samplesPerPixel: 4,
                                      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("emdi-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.declareTypes([.png], owner: nil)
        pasteboard.setData(bitmap.representation(using: .png, properties: [:]), forType: .png)

        #expect(host.textView.pasteImage(from: pasteboard))
        let saved = try FileManager.default.contentsOfDirectory(at: folder.appending(path: "doc_images"), includingPropertiesForKeys: nil)
        #expect(saved.count == 1)
        let name = try #require(saved.first?.lastPathComponent)
        #expect(host.textView.string.contains("](doc_images/\(name))"))

        // Text on the pasteboard is pasted as text, not as an image.
        pasteboard.declareTypes([.string, .png], owner: nil)
        pasteboard.setString("hello", forType: .string)
        #expect(!host.textView.pasteImage(from: pasteboard))
    }

    @Test func pastedTemporaryImageFilesAreCopiedNextToTheDocument() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "emdi-copy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 3, bitsPerSample: 8, samplesPerPixel: 4,
                                      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let captures = FileManager.default.temporaryDirectory.appending(path: "emdi-captures-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: captures) }
        let capture = captures.appending(path: "Capture 1@2x.png")
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: capture)

        let host = try EditorTestHost(text: "Before.\n")
        defer { host.close() }
        host.textView.documentURL = folder.appending(path: "My notes.md")
        host.textView.setSelectedRange(NSRange(location: 8, length: 0))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("emdi-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.writeObjects([capture as NSURL])

        #expect(host.textView.pasteImage(from: pasteboard))
        let copy = folder.appending(path: "My notes_images/Capture 1@2x.png")
        #expect(FileManager.default.fileExists(atPath: copy.path))
        #expect(host.textView.string.contains("](<My notes_images/Capture 1@2x.png>)"))
    }

    @Test func commandClickingAnAnchorLinkMovesToItsHeading() throws {
        let host = try EditorTestHost(text: "Intro with [a link](#the-target) here.\n\nText.\n\n## The Target\n\nEnd.\n")
        defer { host.close() }
        host.textView.setSelectedRange(NSRange(location: 0, length: 0))
        host.pump()
        let label = try host.location(of: "a link")
        var point: NSPoint?
        let layoutManager = try #require(host.textView.textLayoutManager)
        let content = try #require(layoutManager.textContentManager)
        let start = try #require(content.location(content.documentRange.location, offsetBy: label + 2))
        let end = try #require(content.location(start, offsetBy: 1))
        layoutManager.enumerateTextSegments(in: NSTextRange(location: start, end: end)!, type: .standard, options: []) { _, rect, _, _ in
            let origin = host.textView.textContainerOrigin
            point = NSPoint(x: rect.midX + origin.x, y: rect.midY + origin.y)
            return false
        }
        let linkPoint = try #require(point)
        #expect(host.textView.linkRange(at: linkPoint) != nil)

        // A plain click edits the link; a ⌘-click follows it.
        host.click(at: linkPoint)
        #expect(host.textView.selectedRange().location < 30)
        host.click(at: linkPoint, modifiers: .command)
        let headingEnd = try host.location(of: "## The Target") + 13
        #expect(host.textView.selectedRange() == NSRange(location: headingEnd, length: 0))
    }
}
