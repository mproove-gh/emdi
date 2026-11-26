import AppKit

/// What the theme needs from the editor: the width available to blocks (images, tables) and an image loader.
struct ThemeContext {
    /// 0 when the width is not known yet: images are then not shown and tables are not fitted.
    var availableWidth: CGFloat
    var image: (String) -> NSImage?

    static var none: ThemeContext { ThemeContext(availableWidth: 0, image: { _ in nil }) }
}

/// Turns style spans into text attributes. Only attributes change: the characters stay the raw Markdown.
@MainActor
enum MarkdownTheme {
    /// Hidden syntax keeps its characters but takes almost no room and is not drawn.
    static let hiddenFont = NSFont.systemFont(ofSize: 0.01)

    static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        style.paragraphSpacing = 6
        return style
    }()

    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: EditorFonts().body, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraphStyle]
    }

    static func apply(_ spans: [StyleSpan], to storage: NSTextStorage, selection: NSRange, context: ThemeContext) {
        let length = storage.length
        let fonts = EditorFonts()
        storage.beginEditing()
        storage.setAttributes([.font: fonts.body, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraphStyle],
                              range: NSRange(location: 0, length: length))

        // Blocks first, then inline styles, syntax last so it wins over everything.
        for span in spans.sorted(by: { order($0.kind) < order($1.kind) }) where NSMaxRange(span.range) <= length {
            let range = span.range
            switch span.kind {
            case .heading(let level):
                storage.addAttribute(.font, value: fonts.heading(level: level), range: range)
            case .codeBlock:
                storage.addAttribute(.font, value: fonts.code, range: range)
                markCodeBlockLines(in: range, of: storage)
            case .blockQuote:
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
            case .thematicBreak:
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
            case .inlineCode:
                storage.addAttributes([.font: fonts.code, .backgroundColor: codeBackground], range: range)
            case .strong:
                addTrait(.boldFontMask, in: range, of: storage)
            case .emphasis:
                addTrait(.italicFontMask, in: range, of: storage)
            case .strikethrough:
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            case .link:
                storage.addAttributes([
                    .foregroundColor: NSColor.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ], range: range)
            case .marker:
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
            case .syntax:
                if StyleSpan.isActive(block: span.blockRange, selection: selection) {
                    storage.addAttributes([
                        .foregroundColor: NSColor.tertiaryLabelColor,
                        .underlineStyle: 0,
                        .strikethroughStyle: 0,
                    ], range: range)
                } else {
                    storage.addAttributes([
                        .font: hiddenFont,
                        .foregroundColor: NSColor.clear,
                        .backgroundColor: NSColor.clear,
                    ], range: range)
                }
            case .taskMarker(let checked):
                // The prefix is hidden; the kern on its last character leaves room for the drawn checkbox.
                storage.addAttributes([.font: hiddenFont, .foregroundColor: NSColor.clear, .taskCheckbox: checked],
                                      range: range)
                storage.addAttribute(.kern, value: TaskLayoutFragment.checkboxWidth,
                                     range: NSRange(location: NSMaxRange(range) - 1, length: 1))
            case .completedTask:
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
            case .tableRow(let role):
                storage.addAttributes([.tableRow: role.rawValue, .paragraphStyle: tableRowParagraphStyle(role)],
                                      range: range)
                if role.contains(.header) { addTrait(.boldFontMask, in: range, of: storage) }
                if role.contains(.delimiter) {
                    storage.addAttributes([.font: hiddenFont, .foregroundColor: NSColor.clear], range: range)
                }
            case .tablePipe:
                storage.addAttributes([.font: hiddenFont, .foregroundColor: NSColor.clear, .tablePipe: CGFloat(0)],
                                      range: range)
            case .codeToken(let kind):
                storage.addAttribute(.foregroundColor, value: codeColor(kind), range: range)
            case .tableCell:
                break  // Laid out by alignTableColumns once every font is final.
            case .blockImage(let source):
                guard context.availableWidth > 0, let image = context.image(source), image.size.width > 0, image.size.height > 0 else { break }
                let scale = min(1, context.availableWidth / image.size.width)
                let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
                // The image is drawn in the space reserved above the line. The source line itself is shown,
                // small and dimmed, only while the caret is in it; otherwise it is hidden.
                let active = StyleSpan.isActive(block: span.blockRange, selection: selection)
                var attributes: [NSAttributedString.Key: Any] = [
                    .blockImage: BlockImage(image: image, size: size),
                    .paragraphStyle: imageParagraphStyle(imageHeight: size.height),
                    .underlineStyle: 0,
                ]
                if active {
                    attributes[.font] = fonts.body.withSize(fonts.size - 3)
                    attributes[.foregroundColor] = NSColor.tertiaryLabelColor
                } else {
                    attributes[.font] = hiddenFont
                    attributes[.foregroundColor] = NSColor.clear
                }
                storage.addAttributes(attributes, range: range)
            }
        }
        layOutTables(spans, in: storage, selection: selection, availableWidth: context.availableWidth, fonts: fonts)
        storage.endEditing()
    }

    private static let codeBackground = NSColor.quaternaryLabelColor.withAlphaComponent(0.12)

    private static func order(_ kind: StyleSpan.Kind) -> Int {
        switch kind {
        case .heading, .codeBlock, .blockQuote, .thematicBreak: 0
        case .inlineCode, .codeToken: 1
        case .strong, .emphasis, .strikethrough, .link, .marker, .completedTask, .tableRow, .tableCell: 2
        case .syntax, .taskMarker, .tablePipe: 3
        case .blockImage: 4
        }
    }

    /// Tags each line with its position in the block, which `CodeBlockLayoutFragment` uses to draw
    /// the full-width panel, and gives the lines padded, gap-free paragraph styles.
    private static func markCodeBlockLines(in range: NSRange, of storage: NSTextStorage) {
        let text = storage.string as NSString
        var lines: [NSRange] = []
        text.enumerateSubstrings(in: text.lineRange(for: range), options: [.byLines, .substringNotRequired]) { _, _, enclosingLine, _ in
            // The enclosing range includes the newline, so empty lines inside the block are tagged too.
            lines.append(enclosingLine)
        }
        for (index, line) in lines.enumerated() {
            var edges: CodeBlockEdges = []
            if index == 0 { edges.insert(.top) }
            if index == lines.count - 1 { edges.insert(.bottom) }
            storage.addAttributes([
                .codeBlockEdges: edges.rawValue,
                .paragraphStyle: codeParagraphStyle(edges),
            ], range: line)
        }
    }

    private static func codeParagraphStyle(_ edges: CodeBlockEdges) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 14
        style.headIndent = 14
        style.tailIndent = -14
        style.lineSpacing = 2
        style.paragraphSpacingBefore = edges.contains(.top) ? CodeBlockLayoutFragment.verticalPadding + 4 : 0
        style.paragraphSpacing = edges.contains(.bottom) ? CodeBlockLayoutFragment.verticalPadding + 8 : 0
        return style
    }

    /// System colors, so the palette follows light and dark mode.
    private static func codeColor(_ kind: CodeTokenKind) -> NSColor {
        switch kind {
        case .keyword: .systemPink
        case .type: .systemTeal
        case .string: .systemOrange
        case .number: .systemPurple
        case .comment: .secondaryLabelColor
        case .attribute: .systemBrown
        case .property: .systemBlue
        }
    }

    private static func imageParagraphStyle(imageHeight: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = imageHeight + ImageLayoutFragment.gap + 6
        style.paragraphSpacing = 10
        return style
    }

    // MARK: Tables

    static let tableCellPadding: CGFloat = 10

    private static func tableRowParagraphStyle(_ role: TableRowRole) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let padding = role.contains(.delimiter) ? 0 : TableRowLayoutFragment.verticalPadding
        style.lineSpacing = 0
        style.paragraphSpacingBefore = padding + (role.contains(.first) ? 8 : 0)
        style.paragraphSpacing = padding + (role.contains(.last) ? 10 : 0)
        return style
    }

    /// Smallest font scale used to fit a wide table in the window.
    static let minimumTableScale: CGFloat = 0.75

    /// Fits each table to the window, then lines up its columns. A table wider than the window is
    /// shrunk (down to `minimumTableScale`). If it still doesn't fit, it is clipped at the window edge,
    /// except while the caret is in it: it is then shown as plain Markdown that wraps, so every cell
    /// can be read and edited.
    private static func layOutTables(_ spans: [StyleSpan], in storage: NSTextStorage, selection: NSRange,
                                     availableWidth: CGFloat, fonts: EditorFonts) {
        let tables = Dictionary(grouping: spans.filter { span in
            switch span.kind {
            case .tableCell, .tableRow, .tablePipe: NSMaxRange(span.range) <= storage.length
            default: false
            }
        }, by: \.blockRange)

        for (table, tableSpans) in tables {
            let cells = tableSpans.filter { if case .tableCell = $0.kind { true } else { false } }
            var natural = naturalWidth(of: cells, in: storage)
            if availableWidth > 0, natural > availableWidth {
                if natural * minimumTableScale > availableWidth,
                   StyleSpan.isActive(block: table, selection: selection) {
                    showTableAsMarkdown(tableSpans, in: storage, font: fonts.body)
                    continue
                }
                let scale = max(availableWidth / natural * 0.98, minimumTableScale)
                scaleFonts(in: table, of: storage, by: scale)
                natural = naturalWidth(of: cells, in: storage)
                if natural > availableWidth { clipRows(tableSpans, in: storage) }
            }
            alignColumns(cells, in: storage)
        }
    }

    /// Width of the table once aligned: the widest cell of each column, plus cell padding.
    private static func naturalWidth(of cells: [StyleSpan], in storage: NSTextStorage) -> CGFloat {
        var widths: [Int: CGFloat] = [:]
        for cell in cells {
            guard case .tableCell(let column, _) = cell.kind else { continue }
            widths[column] = max(widths[column] ?? 0, storage.attributedSubstring(from: cell.range).size().width)
        }
        return widths.values.reduce(0, +) + CGFloat(widths.count) * 2 * tableCellPadding
    }

    private static func scaleFonts(in range: NSRange, of storage: NSTextStorage, by scale: CGFloat) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let font = value as? NSFont, font.pointSize >= 1 else { return }  // leave hidden syntax alone
            storage.addAttribute(.font, value: font.withSize((font.pointSize * scale).rounded(.down)), range: subrange)
        }
    }

    /// Rows that still don't fit are cut at the window edge instead of wrapping, which would break the grid.
    private static func clipRows(_ spans: [StyleSpan], in storage: NSTextStorage) {
        for span in spans {
            guard case .tableRow(let role) = span.kind,
                  let style = tableRowParagraphStyle(role).mutableCopy() as? NSMutableParagraphStyle else { continue }
            style.lineBreakMode = .byClipping
            storage.addAttribute(.paragraphStyle, value: style, range: span.range)
        }
    }

    /// Undoes the grid styling: rows become ordinary paragraphs and the pipes and delimiter row show, dimmed.
    private static func showTableAsMarkdown(_ spans: [StyleSpan], in storage: NSTextStorage, font: NSFont) {
        let visible: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
        for span in spans {
            switch span.kind {
            case .tableRow(let role):
                storage.removeAttribute(.tableRow, range: span.range)
                storage.addAttribute(.paragraphStyle, value: paragraphStyle, range: span.range)
                if role.contains(.delimiter) { storage.addAttributes(visible, range: span.range) }
            case .tablePipe:
                storage.removeAttribute(.tablePipe, range: span.range)
                storage.addAttributes(visible, range: span.range)
            default:
                break
            }
        }
    }

    /// Lines up the columns: every cell is widened, with kern on the pipes around it, to the width
    /// of the widest cell in its column. Alignment decides how the extra space is split.
    private static func alignColumns(_ cells: [StyleSpan], in storage: NSTextStorage) {
        let text = storage.string as NSString
        let pipe = unichar(UInt8(ascii: "|"))
        var widths: [Int: CGFloat] = [:]
        var cellWidths: [CGFloat] = []
        for cell in cells {
            guard case .tableCell(let column, _) = cell.kind else {
                cellWidths.append(0)
                continue
            }
            let width = storage.attributedSubstring(from: cell.range).size().width
            cellWidths.append(width)
            widths[column] = max(widths[column] ?? 0, width)
        }

        // All spacing goes on the hidden pipes: kern on a visible character right before a hidden pipe
        // is not applied by TextKit. A pipe's kern is the trailing space of the cell before it plus the
        // leading space of the cell after it, and its border is drawn after the trailing part.
        var kerns: [Int: CGFloat] = [:]
        var borderOffsets: [Int: CGFloat] = [:]
        for (cell, width) in zip(cells, cellWidths) {
            guard case .tableCell(let column, let alignment) = cell.kind,
                  NSMaxRange(cell.range) <= storage.length else { continue }
            let extra = (widths[column] ?? width) - width
            let leadingShare: CGFloat = switch alignment {
            case .left: 0
            case .center: 0.5
            case .right: 1
            }
            let lineStart = text.lineRange(for: NSRange(location: cell.range.location, length: 0)).location
            let opening = cell.range.location - 1
            let closing = NSMaxRange(cell.range)
            var leading = tableCellPadding + extra * leadingShare
            var trailing = tableCellPadding + extra * (1 - leadingShare)
            let hasOpening = opening >= lineStart && text.character(at: opening) == pipe
            let hasClosing = closing < text.length && text.character(at: closing) == pipe
            if !hasOpening { trailing += leading; leading = 0 }
            if hasOpening { kerns[opening, default: 0] += leading }
            if hasClosing {
                kerns[closing, default: 0] += trailing
                borderOffsets[closing] = trailing
            }
        }
        for (index, kern) in kerns {
            storage.addAttribute(.kern, value: kern, range: NSRange(location: index, length: 1))
        }
        for (index, offset) in borderOffsets {
            storage.addAttribute(.tablePipe, value: offset, range: NSRange(location: index, length: 1))
        }
    }

    private static func addTrait(_ trait: NSFontTraitMask, in range: NSRange, of storage: NSTextStorage) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let font = value as? NSFont else { return }
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: subrange)
        }
    }
}
