# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**emdi** is a native macOS Markdown editor/viewer in the spirit of Typora: a single-pane WYSIWYG editor where Markdown syntax renders live as you type. Its two guiding goals, in priority order when they conflict with features:

1. **As simple to use as possible**: open a `.md` file and write. No settings screens, sidebars or modes unless clearly needed.
2. **As light as possible**: small binary, fast launch, low memory use. No web views, no JavaScript, as few dependencies as possible.

The project is for personal use only (no App Store and no notarization).

Status: live rendering v1 is in place. That covers headings, bold, italic, strikethrough, inline code, links, lists, quotes, fenced code blocks and rules, with syntax hidden outside the caret's block. The formatting commands are in place too: context menu, Format menu and shortcuts. Tables, clickable task checkboxes, local images and code highlighting are in too, which completes the initial feature set. Keep this file up to date as they land.

## Platform and language

- macOS 26+ only, Apple Silicon only (`ARCHS = arm64`).
- Swift 6 (strict concurrency), SwiftUI for the app shell, AppKit (`NSTextView` with TextKit 2) for the editor.
- The UI is in English only. All code, identifiers and comments are also in English.
- Signing: "Sign to Run Locally" (ad-hoc). App Sandbox is **off**, so the app can read images referenced relative to the open file without security-scoped bookmarks.

## Build and test

You need full Xcode (not only the Command Line Tools) and XcodeGen (`brew install xcodegen`). The `.xcodeproj` is generated from `project.yml`: edit `project.yml`, never the `.xcodeproj`, which is not committed.

```bash
xcodegen generate                                                  # regenerate emdi.xcodeproj (and emdi/Info.plist) after changing project.yml or adding/removing files
xcodebuild -scheme emdi -derivedDataPath build build               # build
xcodebuild -scheme emdi -derivedDataPath build test                # all tests
xcodebuild -scheme emdi -derivedDataPath build test -only-testing:emdiTests/MarkdownDocumentTests/roundTripsUTF8Text  # one test
open build/Build/Products/Debug/emdi.app                           # run
```

- `emdi/Info.plist` is generated from the `info:` section of `project.yml`, so edit document types and other plist keys there.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest.
- Sources are grouped by role: `emdi/App`, `emdi/Document`, `emdi/Markdown` (pure parsing, no AppKit) and `emdi/Editor` (AppKit). New files are picked up after `xcodegen generate`.

## Rendering pipeline (implemented)

1. `MarkdownStyler.spans(for:)` (`emdi/Markdown`) parses the whole text with swift-markdown and returns `[StyleSpan]`. Each span has a kind (heading, strong, link, `.syntax`, …), an `NSRange`, and the `blockRange` of the leaf block it belongs to. Delimiters are derived as "node range minus its children's ranges".
2. `SourceMap` converts swift-markdown locations (1-based line, **UTF-8 byte** column) to UTF-16 offsets. Every range in the pipeline is UTF-16 / `NSRange`, so non-ASCII text breaks any code that skips this conversion.
3. `MarkdownTheme.apply` (`emdi/Editor`) resets the storage to the base attributes, then applies the spans in order: blocks, inline code, inline traits, syntax. A `.syntax` span is shown dimmed when `StyleSpan.isActive(block:selection:)`, and otherwise hidden with a 0.01 pt font and a clear color. The characters always stay in the text.
4. `MarkdownEditorView.Coordinator` re-parses on `textDidChange`. On a selection change it only re-applies styles, and only if the set of active blocks changed. It never restyles while `hasMarkedText()` is true, because that would break dead keys and accents, nor between `shouldChangeTextIn` and `textDidChange`, when the spans are stale.

## Code blocks (implemented)

- `MarkdownTheme` tags every line of a code block, including its newline so empty lines count, with `.codeBlockEdges` (top/bottom) and a padded, gap-free paragraph style.
- `CodeBlockLayoutDelegate`, the `NSTextLayoutManagerDelegate`, returns a `CodeBlockLayoutFragment` for those paragraphs. The fragment paints the background across the full text-container width, with rounded outer corners, before drawing the text. Backgrounds are drawn by fragments, never with `.backgroundColor`, which only highlights the glyphs. The delegate is a separate nonisolated object, because a `@MainActor` coordinator can't conform under Swift 6.
- Copy button: `MarkdownTextView` tracks mouse movement and shows a single `NSButton` at the top right of the hovered block, found through `codeBlockRanges`, which the coordinator sets after each parse. The button copies `CodeBlockText.content(of:)`, the code without its fences or indentation.

## Task items and tables (implemented)

- `MarkdownLayoutDelegate` picks the fragment class for each paragraph from attributes that `MarkdownTheme` sets: `.codeBlockEdges` → `CodeBlockLayoutFragment`, `.tableRow` → `TableRowLayoutFragment`, `.taskCheckbox` → `TaskLayoutFragment`. The attribute keys live in `MarkdownLayoutDelegate.swift`.
- **Tasks**: the `- [ ] ` prefix is always hidden, whatever the caret position, and kern on its last character reserves room for the checkbox that `TaskLayoutFragment` draws. `MarkdownTextView.mouseDown` hit-tests `checkboxRect` and toggles `[ ]`/`[x]` through the undoable edit path. Backspace right after a prefix deletes the whole prefix, using the `taskPrefixRanges` the coordinator sets.
- **Tables**: pipes and the delimiter row are always hidden. `MarkdownTheme.alignTableColumns` measures every cell after all fonts are set, then widens cells to their column's width using **kern on the hidden pipes only**. Kern on a visible character right before a hidden pipe is ignored by TextKit, which was found by testing. The `.tablePipe` value is the border offset after the pipe, and `TableRowLayoutFragment` draws the grid and header fill from it. Column alignment (`:-:`, `--:`) decides how the extra width is split.
- Limits: a table wider than the window wraps and its grid breaks.

## Local images (implemented)

- Only an image that is **alone in its paragraph** is shown as an image (`StyleSpan.Kind.blockImage`). An image inside a line of text keeps link styling, and so does an image whose file can't be loaded.
- `ImageSource.resolve` maps the destination to a file. Relative paths are resolved against the folder of the document's `fileURL`, which `DocumentGroup` passes in through `MarkdownEditorView(fileURL:)`. Remote URLs are deliberately never loaded: no network access. An unsaved document can only show absolute paths.
- `ImageCache` (in `MarkdownEditorView.swift`) reloads an image when its file's modification date changes, and doesn't cache missing files.
- `MarkdownTheme` scales the image to the text width (never up), puts a `BlockImage` in `.blockImage`, and reserves the height with `paragraphSpacingBefore`. `ImageLayoutFragment` draws the image in that space. The `![alt](path)` line is hidden, and shown small and dimmed while the caret is in it.
- The coordinator restyles when the text view's width changes, but only if the document has block images.

## Code highlighting (implemented)

- `CodeHighlighter` (`emdi/Markdown/CodeHighlighter.swift`) is pure and dependency-free. One `Scanner` is driven by a `LanguageSpec` per language: keywords, line and block comments, string delimiters, and flags such as triple quotes, `$variables`, `@attributes` and keys before `:`. HTML/XML have a separate `MarkupScanner`. The language comes from the first word of the fence info string, matched through the aliases in `LanguageSpec.named`. An unknown or missing language gets no colors.
- The styler tokenizes only the code between the fences and emits `.codeToken(kind)` spans with document offsets. `MarkdownTheme.codeColor` maps the kinds to system colors, so light and dark mode both work.
- To add a language, add a `LanguageSpec` and its aliases, then a test in `CodeHighlighterTests`. Those tests compare token texts, not ranges.
- Layout fragments that draw to the last line must skip the empty "extra" line fragment that TextKit 2 adds after a final newline at the end of the document. Use the last line with `characterRange.length > 0`.

## List editing (implemented)

- `ListEditing` (`emdi/Markdown/ListEditing.swift`, pure) turns Return, Tab and Shift-Tab into `TextEdit`s. Return continues bullets, numbers (+1, same `.`/`)` delimiter), tasks (always a new `[ ]`) and quotes, keeping indentation and `>` markers. Return on an empty item removes its marker, which ends the list. Tab and Shift-Tab indent or unindent every list line in the selection by the item's marker width, which is the nesting CommonMark expects. Each function returns nil when the line isn't a list, and the text view then behaves normally.
- `MarkdownTextView` overrides `insertNewline` / `insertTab` / `insertBacktab` and applies these edits through the undoable path. It skips them while an input method is composing and inside code blocks. "Inside" includes a caret at the very end of an unclosed fence, so that test uses `<= NSMaxRange`.
- Following items are not renumbered after an insertion in the middle of a numbered list.
- To simulate typing in a temporary test, call `insertText(_:replacementRange:)` and `insertNewline(nil)` on the text view. All of it lands in one undo group there, unlike real keystrokes.

## Document tabs (implemented)

- Every document opens as a tab of the frontmost emdi window, whatever the system's "Prefer tabs when opening documents" setting says. `DocumentTabsHook` (`emdi/App/DocumentTabs.swift`) is a background view in each document scene. It catches the `NSWindow` in `viewDidMoveToWindow`, and `DocumentTabs.adopt` gives it the `emdi.document` tabbing identifier and joins it to the frontmost visible document window with `addTabbedWindow`.
- To check this in the running app without Accessibility access, list emdi's layer-0 windows with `CGWindowListCopyWindowInfo` from a small `swift` script. Tabs show up as several windows with the same frame, only one of them on screen.

## Verifying rendering visually

Screen capture isn't available to Claude here. To check how things look, add a temporary `@MainActor` Swift Testing test. It hosts `MarkdownEditorView` in an `NSHostingView` inside an offscreen `NSWindow`, renders it with `bitmapImageRepForCachingDisplay` / `cacheDisplay(in:to:)`, and writes a PNG to the scratchpad. Run it with `-only-testing`, look at the PNG, then delete the test. Hover states can be triggered by calling `mouseMoved(with:)` with a synthesized event.

## Formatting commands (implemented)

- `FormatCommand` (`emdi/Markdown/MarkdownFormatter.swift`) is the single list of commands. It holds each command's title, shortcut and menu grouping, and its `edit(in:selection:) -> TextEdit` pure transform. Add a command there and it appears in both menus.
- `MarkdownTextView` (an `NSTextView` subclass) implements `@objc performFormatCommand(_:)`. It applies the `TextEdit` through `shouldChangeText` / `replaceCharacters` / `didChangeText`, so the edit is undoable and the coordinator restyles. It also prepends the commands to the standard context menu.
- `FormatCommands` (SwiftUI `CommandMenu("Format")`) owns the real keyboard shortcuts. It reaches the key editor through `NSApp.sendAction(..., to: nil, from: FormatCommandSender(command))`. Context-menu key equivalents are display-only.
- ⌥⌘T is taken by View ▸ Show Toolbar, so Table has no shortcut. Inserted blocks keep a blank line above them, because `---` right under a text line would turn it into a setext heading.
- Formatter tests use a compact notation: `|` is the caret and `[`…`]` is the selection (see `MarkdownFormatterTests.run`).

Known v1 limits: the whole document is re-parsed and restyled on each edit, which is fine for typical notes; optimize if large files lag. The arrow keys also step through hidden syntax characters.

## Architecture (planned)

- **App shell**: a SwiftUI `DocumentGroup` with a `FileDocument` for `.md` / `.markdown`. This gives open, save, autosave, versions, recent files and window tabs for free. Do not build custom file management.
- **The Markdown text is the only source of truth.** The editor never converts to rich text and back. It edits the raw Markdown string in the `NSTextStorage` and only changes *attributes* (fonts, colors, hidden or shrunk syntax markers). What gets saved is exactly what the user typed.
- **Parsing**: [swift-markdown](https://github.com/swiftlang/swift-markdown) (Apple, based on cmark-gfm) for the GFM syntax tree, including tables and task lists. Target: re-parse incrementally, or debounced, and restyle only the blocks that changed. v1 still does the whole document on each edit (see above).
- **Typora-style live rendering**: syntax markers (`**`, `#`, `` ` ``, `[]()`, …) are hidden or dimmed everywhere except in the block that holds the caret, where the raw syntax is shown so it can be edited.
- **Rich blocks**: local images (paths resolved relative to the document's folder), tables and task-list checkboxes use TextKit 2 text attachments or attachment view providers. Clicking a checkbox toggles `[ ]` / `[x]` in the source text.
- **Code highlighting**: a small built-in tokenizer covering common languages, applied to fenced code blocks. Do not use JS-based highlighters (Highlight.js, Highlightr, …).
- **Formatting commands**: one shared set of commands (bold, italic, strikethrough, inline code, link, heading 1–6, bullet, numbered and task list, quote, code block, table) used by the editor's **right-click context menu**, the **Format** menu bar menu and keyboard shortcuts (⌘B, ⌘I, ⌘K, ⌘1–⌘6, …). Each command transforms the Markdown source around the selection, toggling when the style is already applied, and registers with the undo manager.

## Constraints

- Do not add `WKWebView`, Electron or any JavaScript runtime. Rendering is native TextKit.
- Every third-party dependency must justify its weight. swift-markdown is the only planned one.
- Keep the UI minimal: one document window and the standard macOS menus.
