# emdi

**emdi** is a small, native Markdown editor for the Mac. Open a `.md` file and write: the Markdown renders live as you type, in a single pane, the way Typora does it. There is no preview pane, no sidebar and no mode to switch.

It has two goals, in this order:

1. **As simple as possible.** Open a file, write, close. A few settings, and nothing else to learn.
2. **As light as possible.** It is a 3.7 MB native app with one dependency, and it launches instantly. It has no web view, no JavaScript and no network access.

The file stays plain Markdown. emdi never converts your text to rich text and back: what is saved is exactly what you typed, and the formatting is only how the text is displayed.

## Features

### Live rendering
- The Markdown syntax (`**`, `#`, `` ` ``, `[]()`, …) is hidden everywhere except in the block that holds the caret, where it shows dimmed so you can edit it.
- **Headings** H1–H6, with a rule under H1 and H2. Setext headings are supported too.
- **Inline styles**: bold, italic, strikethrough, inline code, links and autolinks.
- **Lists**: bullets drawn as ●, ○ and ■ depending on depth, numbered lists with their numbers aligned, nested lists and hanging indents.
- **Task lists**: real checkboxes. Click one to tick it; the change is written to the file as `[x]` or `[ ]`.
- **Block quotes**: drawn as grey bars, one per nesting level, without the `>` markers.
- **Callouts**: GitHub-style `> [!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]` and `[!CAUTION]`, each with its icon, color and title.
- **Code blocks** on a rounded panel. A header shows the language and a **Copy** button, and the code is highlighted for about 20 languages: Swift, Python, JavaScript and TypeScript, Java, Kotlin, C, C++, Objective-C, C#, Go, Rust, PHP, Ruby, shell, JSON, YAML, TOML, SQL, CSS, Lua, HTML and XML, and more.
- **Tables** with a rounded frame, a header row and striped rows. Columns align as the table asks (`:--`, `:-:`, `--:`), and wide tables shrink or fade out at the edge.
- **Horizontal rules** drawn as a thin line.
- **Local images** shown inline and scaled to the text width. A missing image shows a placeholder with its path.

### Editing
- A **Format** menu, the right-click menu and keyboard shortcuts for every command:

  | Command | Shortcut |
  | --- | --- |
  | Bold, italic, strikethrough | ⌘B, ⌘I, ⇧⌘X |
  | Inline code | ⌃` |
  | Link | ⌘K |
  | Clear formatting | ⌘\ |
  | Paragraph, heading 1–6 | ⌘0, ⌘1 … ⌘6 |
  | Quote | ⌥⌘Q |
  | Bullet, numbered and task list | ⌥⌘U, ⌥⌘O, ⌥⌘X |
  | Code block | ⌥⌘C |
  | Table, horizontal rule | Format menu |

  Each command toggles: applying it again removes the formatting. Every command can be undone.
- **Lists**:
  - Return continues the list, and Return on an empty item ends it.
  - Tab and Shift-Tab indent and outdent the item.
  - Numbered lists renumber themselves when you add or remove items.
- **Tables**:
  - Tab and Shift-Tab move between cells. Tab in the last cell adds a row.
  - Return moves to the cell below.
  - A Table submenu inserts, deletes and aligns rows and columns.
  - Editing can never break the table's structure.
- **Images**:
  - Drop image files onto the editor.
  - Paste a screenshot with ⌘V: emdi saves it in a `<document name>_images` folder next to the document. Temporary files, such as the captures of screenshot tools, are copied there too.
  - Double-click an image to open it in Quick Look.
- **Links**: ⌘-click a link to open it.
  - Web links open in your browser.
  - Links to other Markdown files open in emdi.
  - Other files open in their own app.
  - `#anchor` links jump to the heading.

### App
- Every document opens as a tab of the same window.
- Light, Dark or System appearance, set in Settings or with a button in the title bar. Both themes are soft paper tones and are checked for readable contrast.
- Choice of text font, text size and code font in Settings.
- Optional saving while you type. Otherwise, emdi asks you to save before closing.
- A setting makes emdi the default app for `.md` files, and another gives them back to the app you used before.
- Two app icons to choose from.

## Requirements and limitations

- **macOS 26 or later, on Apple Silicon only.** emdi does not run on older macOS versions or on Intel Macs.
- The interface is in English only.
- It is a single-document editor: no file browser, export or sync.
- Remote images (`https://…`) are deliberately not loaded, since emdi never accesses the network. They stay as links.
- The whole document is re-rendered on each edit. This is instant for notes and normal documents, but very large files may feel slower.

### Technology

- Swift 6 with strict concurrency.
- SwiftUI for the app shell: `DocumentGroup` gives open, save, versions, recent files and tabs.
- AppKit `NSTextView` with **TextKit 2** for the editor. Custom layout fragments draw the code panels, tables, checkboxes, bullets, quote bars and images.
- [swift-markdown](https://github.com/swiftlang/swift-markdown) (Apple, based on cmark-gfm) for parsing GitHub-Flavored Markdown. It is the only dependency.
- A small built-in tokenizer for code highlighting.
- The project file is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen), and the tests use Swift Testing.

## Built with Claude Code

emdi was built **entirely with [Claude Code](https://claude.com/claude-code)**, Anthropic's AI coding agent. The human behind it described what they wanted, chose between the proposed designs, tested the app by hand and reported bugs. Claude Code wrote all of the code, the tests (about 120 of them) and the documentation, including this README. [`CLAUDE.md`](CLAUDE.md) is the design notebook Claude Code kept along the way.

## Installing

### ⚠️ Before you start: emdi is not signed by Apple

The person who built emdi has **no Apple Developer account**. As a result, the app is only *ad-hoc signed* and is **not notarized**: Apple has not scanned it, and it does not carry a verified developer identity. macOS therefore blocks it the first time you open it.

What this means for you:

- macOS cannot tell you who made the app or whether it was modified after it was built. You are trusting this repository, not Apple.
- If that's not good enough for you, read the code and [build it yourself](#building-from-source). It takes a minute.
- For what it's worth, emdi has no network access, collects nothing and only reads and writes the files you open, plus the images you paste or drop.

The [latest release](https://github.com/mproove-gh/emdi/releases/latest) offers three downloads. Pick one:

| File | How it installs | Best for |
| --- | --- | --- |
| `emdi-1.0.0.pkg` | An installer puts emdi in Applications for you | Most people |
| `emdi-1.0.0.dmg` | You drag emdi onto the Applications folder | Those used to Mac apps |
| `emdi-1.0.0.zip` | You unzip and move emdi yourself | Scripts, or if you prefer zips |

### With the installer (.pkg)

1. Double-click `emdi-1.0.0.pkg`. macOS says it *“could not verify”* the package. Click **Done**, not Move to Trash.
2. Open **System Settings ▸ Privacy & Security**, scroll down to **Security**, and click **Open Anyway** next to the message about the package. Confirm with your password or Touch ID, then click **Open**.
3. Follow the installer: **Continue**, **Install**, then your password. emdi is now in Applications and opens without any further warning.

### With the disk image (.dmg) or the zip

1. Open `emdi-1.0.0.dmg` and drag **emdi** onto the **Applications** folder next to it. With the zip, double-click it and move **emdi.app** to Applications yourself.
2. Open emdi from Applications. macOS says it *“could not verify emdi”*. Click **Done**, not Move to Trash.
3. Open **System Settings ▸ Privacy & Security**, scroll down to **Security**, and click **Open Anyway** next to the message about emdi. Confirm with your password or Touch ID, then click **Open**.

You only do this once. After that, emdi opens normally.

If you are comfortable with the Terminal, this command replaces steps 2 and 3. It removes the quarantine flag that macOS put on the downloaded app:

```bash
xattr -dr com.apple.quarantine /Applications/emdi.app
```

To make emdi open `.md` files when you double-click them, go to **emdi ▸ Settings ▸ Editing ▸ Markdown Files** and click **Make Default**.

### Uninstalling

Quit emdi and move it to the Trash. If emdi was your default app for `.md` files, first click **Restore** in the same Settings section to give them back to your previous app. Your preferences are in `~/Library/Preferences/local.emdi.app.plist`.

## Building from source

You need macOS 26 on Apple Silicon, Xcode, and XcodeGen (`brew install xcodegen`).

```bash
git clone https://github.com/mproove-gh/emdi.git
cd emdi
xcodegen generate
xcodebuild -scheme emdi -configuration Release -derivedDataPath build build
open build/Build/Products/Release/emdi.app
```

`xcodebuild -scheme emdi -derivedDataPath build test` runs the tests. `zsh tools/make-installers.sh` builds the `.pkg`, `.dmg` and `.zip` in `build/`. [`samples/showcase.md`](samples/showcase.md) uses every feature and is a good file to try emdi on.

An app you build yourself is signed on your own Mac, so macOS opens it without the warning.

## License

emdi is released under the [MIT License](LICENSE). Copyright (c) 2026 mproove.
