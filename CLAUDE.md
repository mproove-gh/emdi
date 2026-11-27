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

- `emdi/Info.plist` is generated from the `info:` section of `project.yml`, so edit document types and other plist keys there. The About panel's credit line is `NSHumanReadableCopyright`. The version shown there comes from `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` through `$(…)` references in `info:`, so bump those settings, not the plist.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest.
- Sources are grouped by role: `emdi/App`, `emdi/Document`, `emdi/Markdown` (pure parsing, no AppKit) and `emdi/Editor` (AppKit). New files are picked up after `xcodegen generate`.

## Rendering pipeline (implemented)

1. `MarkdownStyler.spans(for:)` (`emdi/Markdown`) parses the whole text with swift-markdown and returns `[StyleSpan]`. Each span has a kind (heading, strong, link, `.syntax`, …), an `NSRange`, and the `blockRange` of the leaf block it belongs to. Delimiters are derived as "node range minus its children's ranges".
2. `SourceMap` converts swift-markdown locations (1-based line, **UTF-8 byte** column) to UTF-16 offsets. Every range in the pipeline is UTF-16 / `NSRange`, so non-ASCII text breaks any code that skips this conversion.
3. `MarkdownTheme.apply` (`emdi/Editor`) resets the storage to the base attributes, then applies the spans in order: blocks, inline code, inline traits, syntax. A `.syntax` span is shown dimmed when `StyleSpan.isActive(block:selection:)`, and otherwise hidden with a 0.01 pt font and a clear color. The characters always stay in the text.
   `apply` computes the attributes on a scratch `NSTextStorage`, then writes back only the paragraphs whose attributes changed. Never reset the whole storage: TextKit 2 discards the measured layout of every paragraph it's told changed, re-estimates the heights, and the content jumps while scrolled (on each caret move between blocks and while typing). Custom attribute values must compare by value for this, like `BlockImage.isEqual`.
4. `MarkdownEditorView.Coordinator` re-parses on `textDidChange`. On a selection change it only re-applies styles, and only if the set of active blocks changed. It never restyles while `hasMarkedText()` is true, because that would break dead keys and accents, nor between `shouldChangeTextIn` and `textDidChange`, when the spans are stale.

## Code blocks (implemented)

- `MarkdownTheme` tags every line of a code block, including its newline so empty lines count, with `.codeBlockEdges` (top/bottom) and a padded, gap-free paragraph style.
- `CodeBlockLayoutDelegate`, the `NSTextLayoutManagerDelegate`, returns a `CodeBlockLayoutFragment` for those paragraphs. The fragment paints the background across the full text-container width, with rounded outer corners, before drawing the text. Backgrounds are drawn by fragments, never with `.backgroundColor`, which only highlights the glyphs. The delegate is a separate nonisolated object, because a `@MainActor` coordinator can't conform under Swift 6.
- Language label: when the opening fence names a language (`CodeBlockText.language(of:)`, first word of the info string) and the fence is hidden, `MarkdownTheme` puts a styled label in `.codeLanguage` on the fence line, and `CodeBlockLayoutFragment` draws it there. It is drawing only, never text, so it is never copied. That fence line gets `minimumLineHeight` of a code line in both states, so entering the block doesn't shift the layout.
- Copy button: `MarkdownTextView` tracks mouse movement and shows a single `NSButton` at the top right of the hovered block, found through `codeBlockRanges`, which the coordinator sets after each parse. The button copies `CodeBlockText.content(of:)`, the code without its fences or indentation.

## Horizontal rules (implemented)

- A `---` (thematic break) line is hidden, with `.horizontalRule` set on it, and `HorizontalRuleLayoutFragment` draws a 1 px line in `EditorPalette.border` across the text column. While the caret is on it, the dashes show dimmed instead. The line keeps a normal text height (`minimumLineHeight`).

## Task items and tables (implemented)

- `MarkdownLayoutDelegate` picks the fragment class for each paragraph from attributes that `MarkdownTheme` sets: `.codeBlockEdges` → `CodeBlockLayoutFragment`, `.tableRow` → `TableRowLayoutFragment`, `.taskCheckbox` → `TaskLayoutFragment`. The attribute keys live in `MarkdownLayoutDelegate.swift`.
- Checkboxes and the code block copy button show the arrow pointer instead of the I-beam (`MarkdownTextView.isOverControl`, applied in `mouseMoved` and `cursorUpdate`).
- **Tasks**: the `- [ ] ` prefix is always hidden, whatever the caret position, and kern on its last character reserves room for the checkbox that `TaskLayoutFragment` draws. `MarkdownTextView.mouseDown` hit-tests `checkboxRect` and toggles `[ ]`/`[x]` through the undoable edit path. Backspace right after a prefix deletes the whole prefix, using the `taskPrefixRanges` the coordinator sets.
- **Tables**: pipes and the delimiter row are always hidden. `MarkdownTheme.alignTableColumns` measures every cell after all fonts are set, then widens cells to their column's width using **kern on the hidden pipes only**. Kern on a visible character right before a hidden pipe is ignored by TextKit, which was found by testing. The `.tablePipe` value is the border offset after the pipe, and `TableRowLayoutFragment` draws the grid and header fill from it. Column alignment (`:-:`, `--:`) decides how the extra width is split.
- Table structure commands (Insert Row Above/Below, Delete Row, Insert Column Left/Right, Delete Column, Align Column Left/Center/Right) are `FormatCommand`s backed by `TableStructure` (`emdi/Markdown/TableStructure.swift`). `TableModel` parses the table, the operation edits rows or columns, and the table is rewritten whole with one space of padding and normalized delimiters (`:-:` becomes `:---:`). The caret lands in the affected cell. `FormatCommand.isAvailable` disables impossible cases: deleting the only column, deleting the header row, inserting above the header. `MarkdownTextView.validateMenuItem` applies it. The context menu shows the Table submenu only when the caret is in a table; the Format menu always shows it, and there the commands do nothing outside a table.
- To test a context menu, right-click at a point computed with `textLayoutManager.enumerateTextSegments`, not `firstRect(forCharacterRange:)`, which is wrong for offscreen windows. NSTextView moves the caret to the click before building the menu.
- Table structure is protected while editing. `MarkdownTextView.shouldChangeText` routes every user edit that touches a table through `TableEditing.protectingStructure`: typing, Backspace, Delete, cut and paste never remove a `|` or a row break, and pasted line breaks become spaces. An edit that would only remove structure is a no-op, and a selection across cells empties them. emdi's own edits (`apply`, with `isApplyingOwnEdit`), renumbering, undo and redo bypass this. Return in a table (`TableEditing.newline`) moves to the cell below, or adds a row on the last one.
- Clicking in a table (`MarkdownTextView.mouseDown`): the cell is found from the drawn borders (`TableRowLayoutFragment.cellBorders`), not from the character under the pointer, because a cell's wide padding is kern on its hidden pipes. After NSTextView places the caret, `TableEditing.caret(forClickIn:of:at:)` moves it to the start of an empty cell or clamps it to the cell's text. Only plain single clicks; shift, command and option clicks and drags are left alone.
- Tab / Shift-Tab in a table (`TableEditing.tab`, pure, using the `.tableCell` spans the coordinator hands to `MarkdownTextView.tableCells`) move to the next or previous cell and select its text. They go row to row and skip the hidden delimiter row. Tab in the last cell appends an empty `|  |  |` row. They never insert a tab character, whose variable width would break the column alignment. This runs before the list Tab handling.
- Tables fill the text column, unless their natural width is under `narrowTableRatio` (2/3) of it, in which case they keep it: `alignColumns(fillWidth:)` grows each column in proportion to its width until the table is as wide as `availableWidth`. The spaces around each cell's text are hidden and only the text is measured (`contentRange(of:)`), so right and centered alignment are exact whatever the source padding; the padding is `tableCellPadding` of kern. A clipped table isn't stretched.
- Look (`TableRowLayoutFragment.drawGrid`): the table is one rounded frame (`cornerRadius`), each row drawing its slice of a taller rounded path clipped to the row. The header is filled and ruled off, every other body row (`TableRowRole.striped`, set by the styler) gets `EditorPalette.tableStripe`, and columns are separated by the quieter `tableColumnRule`. No lines between body rows.
- Wide tables (`MarkdownTheme.layOutTables`): a table wider than the text column is shrunk, with all its fonts scaled down to at least `minimumTableScale` (0.75). If it still doesn't fit, its rows get `lineBreakMode = .byClipping`, and `TableRowLayoutFragment` clips its drawing to the column and fades the last `fadeWidth` points into the page color (`isClipped`, set by the delegate from the paragraph style). While the caret is in such a table, it is shown as plain Markdown instead (`showTableAsMarkdown`: grid attributes removed, pipes and delimiter row visible and dimmed) so long rows wrap and every cell stays editable. `.tableRow` spans count in `activeSyntaxBlocks`, so entering or leaving a table triggers a restyle. The width comes from `ThemeContext.availableWidth`, and the coordinator restyles on resize when the document has tables or images.

## Block quotes (implemented)

- The `>` markers of each quote line (with the space after the last one) are a `.quoteMarker(depth:blank:)` span, added by the outermost `BlockQuote` only. They are always hidden, whatever the caret position, like Typora.
- `MarkdownTheme` sets `.quoteBars` (a `QuoteBars`: depth and step, value-equal) on the line, and `indentQuotes` runs last: it shifts each quote line's existing paragraph style right by `depth × step` (1.2 × size), so lists and headings inside quotes keep their own layout. A blank `>` line is drawn short like a blank line, except under the caret.
- Every emdi fragment inherits from `MarkdownLayoutFragment`, which draws one `EditorPalette.quoteBar` bar per level over the fragment's full height, so the bars of consecutive lines join up. The delegate sets `quoteBars` on whatever fragment it made. Bullets in a quote are drawn in the secondary color, like the quote text.
- Backspace right after a quote prefix removes the innermost level (the last `>` and its space), through `quotePrefixRanges`, which the coordinator sets after each parse.

## Callouts (implemented)

- A top-level quote whose first line is `> [!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]` or `[!CAUTION]` (any case) is a GitHub-style callout: `CalloutKind.opening` (`emdi/Markdown/Callout.swift`) detects it, and the styler emits `.callout(kind)` over the quote and `.calloutMarker(kind)` over `[!KIND]` and its spaces. Unknown kinds and nested quotes stay ordinary quotes.
- `MarkdownTheme` puts the text back in the normal color, sets `.callout` on every line, and hides the marker unless the caret is on its line (it is then shown dimmed). While hidden, the line gets `.calloutTitle`: the kind's name, bold and in the kind's color, or an empty string when text follows the marker, which then is the title (bold, colored) with kern before it for the icon. The title line keeps a full line's height in both states.
- `MarkdownLayoutFragment` paints the tint (`EditorPalette.calloutBackground`) from the bar to the column's right edge, colors the outer bar with `EditorPalette.callout`, and draws the SF Symbol and title. `indentQuotes` gives callout lines a tail indent and the last line some room under the text.
- Palette colors used as attribute values must be created once (static), never per call: dynamic `NSColor`s compare by identity, so a new instance on each restyle makes the paragraphs look changed and TextKit re-lays them out, which moves the view.

## Local images (implemented)

- Only an image that is **alone in its paragraph** is shown as an image (`StyleSpan.Kind.blockImage`). An image inside a line of text keeps link styling, and so does an image whose file can't be loaded.
- `ImageSource.resolve` maps the destination to a file. Relative paths are resolved against the folder of the document's `fileURL`, which `DocumentGroup` passes in through `MarkdownEditorView(fileURL:)`. Remote URLs are deliberately never loaded: no network access. An unsaved document can only show absolute paths.
- `ImageCache` (in `MarkdownEditorView.swift`) reloads an image when its file's modification date changes, and doesn't cache missing files.
- `MarkdownTheme` scales the image to the text width (never up), puts a `BlockImage` in `.blockImage`, and reserves the height with `paragraphSpacingBefore`. `ImageLayoutFragment` draws the image in that space. The `![alt](path)` line is hidden, and shown small and dimmed while the caret is in it.
- The coordinator restyles when the text view's width changes, but only if the document has block images.
- Dropping image files onto the editor (`MarkdownTextView.performDragOperation`) inserts one `![name](path)` paragraph per image at the drop point, through `MarkdownFormatter.insertBlock`. `ImageSource.markdown(forImageAt:relativeTo:)` builds the path: relative to the document folder (`../` allowed) when the document is saved, absolute when it isn't or when the image is on another volume, and `<…>` around paths with spaces or parentheses. Files are referenced where they are, not copied. Other drops keep NSTextView's default behaviour.

## Code highlighting (implemented)

- `CodeHighlighter` (`emdi/Markdown/CodeHighlighter.swift`) is pure and dependency-free. One `Scanner` is driven by a `LanguageSpec` per language: keywords, line and block comments, string delimiters, and flags such as triple quotes, `$variables`, `@attributes` and keys before `:`. HTML/XML have a separate `MarkupScanner`. The language comes from the first word of the fence info string, matched through the aliases in `LanguageSpec.named`. An unknown or missing language gets no colors.
- The styler tokenizes only the code between the fences and emits `.codeToken(kind)` spans with document offsets. `MarkdownTheme.codeColor` maps the kinds to system colors, so light and dark mode both work.
- To add a language, add a `LanguageSpec` and its aliases, then a test in `CodeHighlighterTests`. Those tests compare token texts, not ranges.
- Layout fragments that draw to the last line must skip the empty "extra" line fragment that TextKit 2 adds after a final newline at the end of the document. Use the last line with `characterRange.length > 0`.

## List editing (implemented)

- `ListEditing` (`emdi/Markdown/ListEditing.swift`, pure) turns Return, Tab and Shift-Tab into `TextEdit`s. Return continues bullets, numbers (+1, same `.`/`)` delimiter), tasks (always a new `[ ]`) and quotes, keeping indentation and `>` markers. Return on an empty item removes its marker, which ends the list. Tab and Shift-Tab indent or unindent every list line in the selection by the item's marker width, which is the nesting CommonMark expects. Each function returns nil when the line isn't a list, and the text view then behaves normally.
- `MarkdownTextView` overrides `insertNewline` / `insertTab` / `insertBacktab` and applies these edits through the undoable path. It skips them while an input method is composing and inside code blocks. "Inside" includes a caret at the very end of an unclosed fence, so that test uses `<= NSMaxRange`.
- Renumbering: `ListEditing.renumber(in:touching:selection:)` parses with swift-markdown and rewrites the item numbers of every `OrderedList` the range touches, including all sub-lists of a touched list. Each list counts up from its first item's number, so a list may start at 5. It returns one `TextEdit` spanning the changed numbers, with the caret shifted when a number gets longer (9 → 10). `MarkdownTextView` runs it after every `apply` (list keys and formatting commands) and after any change that adds or removes a line break (typing, deleting, pasting). Line-break changes are flagged in `shouldChangeText` and handled in `didChangeText`. It never runs while undoing or redoing, so undo restores the exact previous text, and the renumbering falls in the same undo group as the keystroke. Tab restarts a numbered item at 1. In CommonMark a sub-list that interrupts an item's text must start at 1, otherwise "2." is read as more text, and test inputs must respect that.
- To simulate typing in a temporary test, call `insertText(_:replacementRange:)` and `insertNewline(nil)` on the text view. All of it lands in one undo group there, unlike real keystrokes.

## Document tabs (implemented)

- Every document opens as a tab of the frontmost emdi window, whatever the system's "Prefer tabs when opening documents" setting says. `DocumentTabsHook` (`emdi/App/DocumentTabs.swift`) is a background view in each document scene. It catches the `NSWindow` in `viewDidMoveToWindow`, and `DocumentTabs.adopt` gives it the `emdi.document` tabbing identifier and joins it to the frontmost visible document window with `addTabbedWindow`.
- To check this in the running app without Accessibility access, list emdi's layer-0 windows with `CGWindowListCopyWindowInfo` from a small `swift` script. Tabs show up as several windows with the same frame, only one of them on screen.

## App icon (implemented)

- The design is serif "eMD" followed by an orange text cursor that stands for the "I". At 32 px and below, only "e" and the cursor are drawn. The icons are **generated**: edit `tools/make-icons.swift` and run `swift tools/make-icons.swift` from the repo root. It writes the default white icon to `emdi/Assets.xcassets/AppIcon.appiconset` and the alternate icon to `emdi/Resources/AppIcon-Anthracite.icns`. Don't edit the PNGs by hand.
- The icon choice is the App Icon pane of Settings (`AppIconPane` in `emdi/App/SettingsView.swift`). It stores the choice in the `appIcon` user default (`white` by default, or `anthracite`). `AppIcon.apply` sets `NSApp.applicationIconImage` for the running Dock icon. It also sets the bundle's custom Finder icon with `NSWorkspace.setIcon(_:forFile:)`, which adds an `Icon\r` file to the bundle; a rebuild discards that file, so `AppDelegate` re-applies a non-default choice at launch.
- To see the icon as the system shows it, render `NSWorkspace.shared.icon(forFile:)` of the built app to a PNG. Running `lsregister -f` on the app first refreshes Launch Services. SwiftUI `Text` doesn't appear in `cacheDisplay` captures; render SwiftUI-only views with `ImageRenderer` instead.

## Settings window (implemented)

- `SettingsView` (`emdi/App/SettingsView.swift`) is a `NavigationSplitView`, like System Settings. On the left, `SettingsSidebar` lists the `SettingsPane` cases, each with a colored SF Symbol tile. On the right is the matching pane (`AppearancePane`, `FontsPane`, `AppIconPane`), each a grouped `Form`. To add a section, add a `SettingsPane` case (title, symbol, tint) and its pane view. Each pane owns its `@AppStorage` values and their `onChange` side effects.
- `AppearancePane` shows the themes as `ThemeThumbnail`s, miniature documents drawn with `EditorPalette.resolve(_:dark:)`, so the previews show the real colors whatever the current appearance.
- `SettingsPane.id` must be the pane itself, not its raw value: `List(selection:)` tags each row with the element's `id`, and a `String` id never matches a `SettingsPane?` selection, which made clicks in the sidebar do nothing. `SettingsPaneTests` guards this. To check pane switching, select rows of the sidebar's `NSTableView` and read `window.title`.
- The Settings panes and sidebar are drawn on the editor's paper (`settingsBackground()`), and the selected option (theme, app icon) is framed in the emdi orange (`Color.emdiSelection`). Those option rows carry `.id(selection)`: without it, the grouped `Form` row kept the frame on a previous choice after the second change.
- `SettingsView(initialPane:)` lets tests open a given pane. In offscreen captures the macOS 26 glass sidebar comes out blank, so render `SettingsSidebar` on its own to check it.

## Themes and colors (implemented)

- Every editor color comes from `EditorPalette` (`emdi/Editor/EditorPalette.swift`). Each color is a dynamic `NSColor` with a light and a dark value that resolves at draw time. Never use system colors such as `NSColor.textColor`, `.systemPink` or `.separatorColor` in the theme or the fragments. Light is soft, warm paper (#F6F4EE, deliberately not bright: `EditorPaletteTests` keeps its luminance between 0.85 and 0.93) with near-black ink, dark a soft charcoal (#252528, not too dark, to soften the contrast) with off-white text. The fills and borders (code, tables, quotes) are set relative to the background: move them with it. The emdi orange is reserved for the insertion point. Code colors follow Xcode's default themes.
- `EditorPaletteTests` enforce WCAG contrast: body text at least 12:1, and secondary text, links and every code color at least 4.5:1 on their background, in both appearances. Run them after changing any color. Revealed syntax (`EditorPalette.syntax`) is deliberately quieter and is not checked.
- The Appearance pane of Settings sets `AppearanceChoice` (`system`, `light`, `dark`; user default `appearance`). `apply()` sets `NSApp.appearance`, and `AppDelegate` applies it at launch. Because the colors are dynamic, switching needs no restyle.
- `AppearanceToggle` (`emdi/App/Appearance.swift`) puts a small button at the right of each document window's title bar (an `NSTitlebarAccessoryViewController`, installed by `DocumentTabs.adopt`). A click cycles System → Light → Dark through the same user default, and every button follows `UserDefaults.didChangeNotification`, so it and Settings stay in step.

## Fonts (implemented)

- The Fonts pane of Settings offers a text font family and size (11–28 pt, default 15) and a code font family. The code picker lists monospaced families first, then all others. Values live in user defaults (`textFontFamily`, `textFontSize`, `codeFontFamily`), and an empty family means the system font (SF Pro, or SF Mono for code).
- `EditorFonts` (`emdi/Editor/EditorFonts.swift`) builds the real fonts from `FontSettings.current()`. Code is the text size minus 1, headings scale with the text size (32/25/21/18/15/14 pt at 15; H6 is in the secondary color), and a missing family falls back to the system font. `MarkdownTheme.apply` creates one `EditorFonts` per pass. Never hard-code font sizes in the theme or the fragments: `TaskLayoutFragment`, for example, reads the x-height from the item's actual font.
- Body spacing scales with the text size (`MarkdownTheme.paragraphStyle(for:)`): line spacing about 0.38 × size (≈ 1.6 line height), paragraph spacing 0.4 × size. The look follows Typora: compact, no superfluous space.
- Blank lines (`StyleSpan.Kind.blankLine`, whitespace-only lines outside code blocks) are separators: drawn 0.35 × size high, except the one holding the caret, which keeps a full line for typing. They count in `activeSyntaxBlocks`, so moving onto or off one restyles.
- List items get a tighter paragraph spacing (0.12 × size); the gap after a list comes from its blank line.
- List layout (`MarkdownTheme.layOutListItems`, from `.listItem(depth:bullet:list:)` spans): each nesting level is indented by `listLevelIndent` (1.8 × size) whatever the source indentation, which is compensated with `firstLineHeadIndent`. Markers are right-aligned in a column as wide as the list's widest marker (at least 1.6 × size), so 9. and 10. line up and every item's text starts at the same place. Wrapped lines hang under the text (`headIndent`), and later paragraphs of an item (`.listContinuation`) are aligned with it too.
- Bullets: the `-`, `*` or `+` stays in the text but is clear, with kern for the gap, and carries `.listBullet` (the depth). `ListItemLayoutFragment` draws a disc at depth 0, a circle at depth 1 and a square below, centred on the marker's own width and the text's x-height. Ordered markers stay visible text.
- Headings get space above (0.8 × size for H1/H2, 0.6 below) and tight line spacing. The last line of an H1 or H2 has `.headingRule`, and `HeadingLayoutFragment` draws a 1 px `EditorPalette.border` rule under it across the column, like Typora. Setext headings are styled line by line (`styleHeadingLines`).
- Bold and italic (`MarkdownTheme.addTrait`) use the font's real variant only if converting actually changed the font: a heavier weight, or another italic face. Some families (AppleGothic, for example) have none, and AppKit may still report the trait. Those get faux bold (`.strokeWidth` -6) and faux italic (the same font with a sheared matrix from `fontDescriptor.withMatrix`; `.obliqueness` is ignored by TextKit 2). Headings in such fonts get the faux bold too. Known limit: bold plus italic in such a font shows only the italic, because the stroke doesn't apply to a sheared font.
- Every `MarkdownEditorView.Coordinator` observes `UserDefaults.didChangeNotification` and restyles when `FontSettings` changed, so open documents update live.
- Tests that touch font settings must use a separate `UserDefaults(suiteName:)` or remove the keys afterwards: the test host is the real app, so `UserDefaults.standard` is the user's own emdi preferences.

## Closing documents and quitting (implemented)

- Saving follows Settings ▸ Editing ▸ "Save automatically while typing" (user default `autosaveWhileTyping`, off by default). When off, closing a modified document or quitting asks Save / Don't Save / Cancel. When on, `DocumentSaving.saveSoon` (called from the coordinator's `textDidChange`) saves the file `autosaveDelay` (0.8 s) after the last keystroke with `NSDocument.save(to:ofType:for:)`, and closing saves without asking. Untitled documents are not written until they are named. SwiftUI's `DocumentGroup` document class (`FileWrapperPlatformDocument`) always autosaves in place and has no API to change that, so `DocumentSaving` (`emdi/App/DocumentClosing.swift`) overrides its `autosavesInPlace` with the Objective-C runtime to return the setting. This happens when the first document window is adopted (`DocumentTabs.adopt`). Saving after the override was checked by hand in the real app, and saving while typing by a test that reads the file back.
- `LastDocumentQuitter.shared`, started by `AppDelegate`, quits emdi when the last document window closes, so a lone Settings window never stays behind. Its `terminate` closure is replaceable for tests.
- Testing caveat: an `NSDocument` only becomes "edited" when its undo group closes at the end of a real event. Calling `insertText` from a test doesn't mark it, and ending the undo group by hand corrupts the undo manager (exception at the next click). The close-and-save flow is best checked by hand.

## Sample document and scrolling tests

- `samples/showcase.md` (with `samples/images/`) uses every supported feature, for checking emdi by hand. The user ticks its task list while testing, so don't commit those edits unless asked.
- `EditorTestHost` (in emdiTests) hosts a real editor offscreen, on the showcase file or any text, with helpers for real clicks (it queues the mouse-up first, since NSTextView's `mouseDown` tracks until release), fragment lookup and the top of the visible area. `EditorInteractionTests` uses it for table clicks, code labels and pointer shapes.
- `EditorScrollingTests` loads that file in an offscreen window (lay out everything above the point you scroll to, as real scrolling does, otherwise the first restyle corrects TextKit's height estimates and the view moves) and checks that the top of the visible area doesn't move when the caret changes block, while typing, or when a checkbox far from the caret is clicked (toggling a box never scrolls to the caret). Tests must not depend on the file's checkbox states.
- An `NSWindow` made in a test needs `isReleasedWhenClosed = false`, otherwise `close()` over-releases it and the test host crashes. xcodebuild then restarts and may still print a passing summary for a partial run.

## Verifying rendering visually

Screen capture isn't available to Claude here. To check how things look, add a temporary `@MainActor` Swift Testing test. It hosts `MarkdownEditorView` in an `NSHostingView` inside an offscreen `NSWindow`, renders it with `bitmapImageRepForCachingDisplay` / `cacheDisplay(in:to:)`, and writes a PNG to the scratchpad. Run it with `-only-testing`, look at the PNG, then delete the test. Hover states can be triggered by calling `mouseMoved(with:)` with a synthesized event.

## Formatting commands (implemented)

- `FormatCommand` (`emdi/Markdown/MarkdownFormatter.swift`) is the single list of commands. It holds each command's title, shortcut and menu grouping, and its `edit(in:selection:) -> TextEdit` pure transform. Add a command there and it appears in both menus.
- `MarkdownTextView` (an `NSTextView` subclass) implements `@objc performFormatCommand(_:)`. It applies the `TextEdit` through `shouldChangeText` / `replaceCharacters` / `didChangeText`, so the edit is undoable and the coordinator restyles. It also prepends the commands to the standard context menu.
- `FormatCommands` (SwiftUI `CommandMenu("Format")`) owns the real keyboard shortcuts. It reaches the key editor through `NSApp.sendAction(..., to: nil, from: FormatCommandSender(command))`. Context-menu key equivalents are display-only.
- ⌥⌘T is taken by View ▸ Show Toolbar, so Table has no shortcut. Inserted blocks keep a blank line above them, because `---` right under a text line would turn it into a setext heading.
- Clear Formatting (⌘\, last item of the inline group) is `MarkdownFormatter.clearFormatting`. It parses with `MarkdownStyler` and removes the `.syntax` spans inside every strong, emphasis, strikethrough, link/image, inline code, heading or code block element that touches the selection (or the caret). It also removes list, task and quote markers on the selected lines. Tables and rules are left alone. The selection is mapped through the removals so it keeps covering the same text. Its tests mark the selection with `«…»`, because `[`…`]` clashes with links and task boxes.
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

