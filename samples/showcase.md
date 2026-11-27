# emdi showcase

This document exercises **every feature emdi supports**. Open it in emdi, move the caret around, and check that the Markdown syntax hides outside the caret's block and shows, dimmed, inside it.

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.

---

## 1. Headings

# Heading level 1

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Integer nec odio. Praesent libero. Sed cursus ante dapibus diam.

## Heading level 2

Sed nisi. Nulla quis sem at nibh elementum imperdiet. Duis sagittis ipsum. Praesent mauris. Fusce nec tellus sed augue semper porta.

### Heading level 3

Mauris massa. Vestibulum lacinia arcu eget nulla. Class aptent taciti sociosqu ad litora torquent per conubia nostra, per inceptos himenaeos.

#### Heading level 4

Curabitur sodales ligula in libero. Sed dignissim lacinia nunc. Curabitur tortor. Pellentesque nibh. Aenean quam.

##### Heading level 5

In scelerisque sem at dolor. Maecenas mattis. Sed convallis tristique sem. Proin ut ligula vel nunc egestas porttitor.

###### Heading level 6

Morbi lectus risus, iaculis vel, suscipit quis, luctus non, massa. Fusce ac turpis quis ligula lacinia aliquet.

Setext heading, level 1
=======================

Setext heading, level 2
-----------------------

Mauris ipsum. Nulla metus metus, ullamcorper vel, tincidunt sed, euismod in, nibh. Quisque volutpat condimentum velit.

---

## 2. Inline formatting

Lorem ipsum dolor sit amet, **bold text with asterisks** and __bold text with underscores__. Then *italic with asterisks* and _italic with underscores_, followed by ***bold and italic together***. Some ~~struck-through words~~ sit next to `inline code` and a [link to the Markdown guide](https://commonmark.org/help/).

Nested styles: **bold with *italic inside* and `code` inside**, *italic with a [link](https://example.com) inside*, and ~~struck with **bold** inside~~. A link with a title: [CommonMark spec](https://spec.commonmark.org "The CommonMark specification"). An autolink: <https://github.com/swiftlang/swift-markdown>.

Non-ASCII text must style correctly too: **café crème**, *naïve façade*, ~~Ærøskøbing~~, `größe = 42`, [日本語のリンク](https://example.jp), and emoji 🚀 **in bold 🎉** or *in italic ✨*.

Escaped characters stay literal: \*not italic\*, \*\*not bold\*\*, \`not code\`, \# not a heading, 1\. not a list.

Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae; Morbi lacinia molestie dui. Praesent blandit dolor. Sed non quam. In vel mi sit amet augue congue elementum. Morbi in ipsum sit amet pede facilisis laoreet. Donec lacus nunc, viverra nec, blandit vel, egestas et, augue.

A paragraph with a hard line break at the end of this line  
continues here on a new line, while this one
is a soft break and joins the previous line.

---

## 3. Lists

### Bullet lists

- Lorem ipsum dolor sit amet
- Consectetur adipiscing elit, with **bold** and `code`
- Sed do eiusmod tempor incididunt
  - Nested item one
  - Nested item two
    - Deeply nested item
    - Another deeply nested item
  - Back to the second level
- Ut labore et dolore magna aliqua

* An asterisk bullet list
* Second item

+ A plus bullet list
+ Second item

### Numbered lists

1. First step: lorem ipsum dolor sit amet
2. Second step: consectetur adipiscing elit
3. Third step, with a sub-list:
   1. Sub-step one
   2. Sub-step two
   3. Sub-step three
4. Fourth step
5. Fifth step
6. Sixth step
7. Seventh step
8. Eighth step
9. Ninth step
10. Tenth step, the number grew by one digit

A list that starts at 5, with a parenthesis delimiter:

5) Quinque
6) Sex
7) Septem

A list with multi-paragraph items:

1. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.

   Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.

2. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.

### Task lists

- [x] Live rendering of headings and inline styles
- [x] Formatting commands in the context and Format menus
- [x] Tables with aligned columns
- [ ] An unchecked task, click the box to toggle it
- [ ] A task with **bold**, *italic* and `code` in it
  - [x] A nested, completed sub-task
  - [ ] A nested, open sub-task
- [ ] A very long task to check wrapping: lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.

1. [ ] A numbered task
2. [x] Another numbered task, done

---

## 4. Block quotes

> Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation.
>
> A second paragraph in the same quote, with **bold**, *italic* and a [link](https://example.com).

> A quote with a nested quote:
>
> > Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore.
> >
> > > And a third level, for good measure.
>
> Back to the first level.

> A quote holding a list:
>
> - First quoted item
> - Second quoted item
>
> And a heading:
>
> ### Quoted heading

### Callouts

GitHub-style callouts: a quote whose first line is `[!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]` or `[!CAUTION]`.

> [!NOTE]
> Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore.

> [!TIP]
> Put the caret on the first line to see the `[!TIP]` marker.

> [!IMPORTANT]
> Ut enim ad minim veniam, quis nostrud exercitation:
>
> - ullamco laboris nisi
> - ut aliquip ex ea commodo

> [!WARNING] Mind the custom title
> A title written after the marker replaces the kind's name.

> [!CAUTION]
> Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore.

---

## 5. Code blocks

Lorem ipsum dolor sit amet, here is some Swift. Hover over a block to see its copy button.

```swift
import Foundation

/// A small example type.
@MainActor
struct Greeter: Sendable {
    let name: String
    var count = 0

    func greet(times: Int = 1) -> String {
        // Repeat the greeting.
        let line = "Hello, \(name)!"
        return Array(repeating: line, count: times).joined(separator: "\n")
    }
}

let greeter = Greeter(name: "emdi")
print(greeter.greet(times: 3))
```

```python
from dataclasses import dataclass

@dataclass
class Point:
    x: float
    y: float

    def norm(self) -> float:
        """Return the Euclidean norm."""
        return (self.x ** 2 + self.y ** 2) ** 0.5

# Print a few points
for i in range(3):
    print(Point(i, i * 2).norm(), f"index={i}")
```

```javascript
const items = [1, 2, 3];
// Double every item
const doubled = items.map((n) => n * 2);
console.log(`Result: ${doubled.join(", ")}`);
export default function sum(a, b) { return a + b; }
```

```bash
#!/bin/zsh
# Build and run emdi
xcodegen generate
xcodebuild -scheme emdi -derivedDataPath build build
if [ $? -eq 0 ]; then
  echo "Built at $HOME/build"
  open build/Build/Products/Debug/emdi.app
fi
```

```json
{
  "name": "emdi",
  "version": 1.0,
  "features": ["tables", "tasks", "images"],
  "sandboxed": false,
  "dependencies": null
}
```

```yaml
name: emdi
options:
  deploymentTarget:
    macOS: "26.0"
settings:
  ARCHS: arm64   # Apple Silicon only
```

```sql
-- Recent documents
SELECT name, modified_at
FROM documents
WHERE modified_at > '2026-01-01'
ORDER BY modified_at DESC
LIMIT 10;
```

```html
<!DOCTYPE html>
<html lang="en">
  <!-- A comment -->
  <body class="page">
    <p id="intro">Hello, <strong>world</strong>!</p>
  </body>
</html>
```

```css
.editor {
  font-family: "SF Mono", monospace;
  color: #1d1d1f;
  padding: 12px;
}
```

```rust
fn main() {
    let words = vec!["lorem", "ipsum"];
    for w in &words {
        println!("{}", w); // print each word
    }
}
```

```go
package main

import "fmt"

func main() {
	fmt.Println("Hello from Go")
}
```

A block with no language gets no colors:

```
Plain preformatted text.
    Indentation is kept.

The empty line above is part of the block.
```

A block in an unknown language:

```klingon
nuqneH! This language has no highlighter.
```

An indented code block:

    let indented = true
    print("Four spaces make a code block")

---

## 6. Tables

A simple table:

| Feature        | Status      | Notes                          |
| -------------- | ----------- | ------------------------------ |
| Headings       | Done        | Levels 1 to 6                  |
| Inline styles  | Done        | Bold, italic, strike, code     |
| Tables         | Done        | With **styles** and `code`     |
| Images         | Done        | Local files only               |

A table with column alignment:

| Left aligned | Centered | Right aligned |
| :----------- | :------: | ------------: |
| Lorem        | ipsum    | 1.00          |
| Dolor sit    | amet     | 42.50         |
| Consectetur  | adipiscing elit | 1 234.99 |
| Ünïcödé      | café     | 7             |

A narrow table:

| A | B |
|---|---|
| 1 | 2 |
| 3 | 4 |

A wide table, which shrinks or switches to plain Markdown while the caret is in it:

| Identifier | Name | Description | Category | Owner | Created | Updated | Priority | Status | Comment |
| ---------- | ---- | ----------- | -------- | ----- | ------- | ------- | -------- | ------ | ------- |
| EMD-001 | Live rendering | Hide syntax outside the caret's block | Editor | Me | 2026-01-10 | 2026-03-02 | High | Done | Lorem ipsum dolor sit amet |
| EMD-002 | Tables | Align columns using kern on hidden pipes | Editor | Me | 2026-02-14 | 2026-04-20 | Medium | Done | Consectetur adipiscing elit |
| EMD-003 | Images | Show local images alone in their paragraph | Rendering | Me | 2026-03-01 | 2026-05-11 | Low | Done | Sed do eiusmod tempor |

---

## 7. Images

A large local image, alone in its paragraph, scaled down to the text width:

![The emdi icon, large](images/emdi-icon-large.png)

A small local image, never scaled up:

![The emdi icon, small](images/emdi-icon-small.png)

An image inside a line of text keeps link styling: here it is ![inline icon](images/emdi-icon-small.png) in the middle of a sentence.

A missing image shows a placeholder:

![This file does not exist](images/missing.png)

A remote image is never loaded, since emdi makes no network access:

![Remote image](https://example.com/image.png)

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nunc feugiat mi a tellus consequat imperdiet. Vestibulum sapien. Proin quam. Etiam ultrices. Suspendisse in justo eu magna luctus suscipit.

---

## 8. Horizontal rules

Three dashes:

---

Three asterisks:

***

Three underscores:

___

Sed lectus. Integer euismod lacus luctus magna. Quisque cursus, metus vitae pharetra auctor, sem massa mattis sem, at interdum magna augue eget diam.

---

## 9. Long text

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Curabitur pretium tincidunt lacus. Nulla gravida orci a odio. Nullam varius, turpis et commodo pharetra, est eros bibendum elit, nec luctus magna felis sollicitudin mauris. Integer in mauris eu nibh euismod gravida. Duis ac tellus et risus vulputate vehicula. Donec lobortis risus a elit. Etiam tempor. Ut ullamcorper, ligula eu tempor congue, eros est euismod turpis, id tincidunt sapien risus a quam.

Maecenas fermentum consequat mi. Donec fermentum. Pellentesque malesuada nulla a mi. Duis sapien sem, aliquet nec, commodo eget, consequat quis, neque. Aliquam faucibus, elit ut dictum aliquet, felis nisl adipiscing sapien, sed malesuada diam lacus eget erat. Cras mollis scelerisque nunc. Nullam arcu. Aliquam consequat. Curabitur augue lorem, dapibus quis, laoreet et, pretium ac, nisi.

Aenean magna nisl, mollis quis, molestie eu, feugiat in, orci. In hac habitasse platea dictumst. Fusce convallis, mauris imperdiet gravida bibendum, nisl turpis suscipit mauris, sed placerat ipsum urna sed risus. In convallis tellus a mauris. Curabitur non elit ut libero tristique sodales. Mauris a lacus. Donec mattis semper leo. In hac habitasse platea dictumst.

Vivamus facilisis diam at odio. Mauris dictum, nisi eget consequat elementum, lacus ligula molestie metus, non feugiat orci magna ac sem. Donec turpis. Donec vitae metus. Morbi tristique neque eu mauris. Quisque gravida ipsum non sapien. Proin turpis lacus, scelerisque vitae, elementum at, lobortis ac, quam. Aliquam dictum eleifend risus.

---

## 10. Things to try

- [ ] Select a word and press ⌘B, ⌘I or ⌘K
- [ ] Press ⌘1 to ⌘6 on a paragraph to turn it into a heading
- [ ] Select some formatted text and press ⌘\ to clear its formatting
- [ ] Press Return at the end of a list item, then Return again on the empty item
- [ ] Press Tab and Shift-Tab in a list
- [ ] Insert a line in the middle of the numbered list and watch it renumber
- [ ] Press Tab in a table to move from cell to cell, and in the last cell to add a row
- [ ] Right-click in a table and use the Table submenu
- [ ] Drop an image file from the Finder onto the editor
- [ ] Paste a screenshot (⌘V): it is saved in images/ next to this file
- [ ] Double-click an image to open it in Quick Look
- [ ] Switch between light and dark mode, and change fonts in Settings
