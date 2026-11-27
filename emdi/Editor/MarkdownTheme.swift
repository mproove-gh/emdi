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

    /// Body text spacing, relative to the text size: about 1.6 line height (as in Typora and most
    /// reading apps). The gap between paragraphs is this spacing plus the short blank line between them.
    static func paragraphStyle(for fonts: EditorFonts) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = (fonts.size * 0.38).rounded()
        style.paragraphSpacing = (fonts.size * 0.4).rounded()
        return style
    }

    /// A blank line between blocks is a separator, not a line of text: it is drawn short. The one
    /// holding the caret keeps a full line so typing there looks normal.
    private static func blankLineStyle(for fonts: EditorFonts) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let height = (fonts.size * 0.35).rounded()
        style.minimumLineHeight = height
        style.maximumLineHeight = height
        return style
    }

    /// Headings: space above them, little between their lines, and room below H1 and H2 for their rule.
    /// `first` / `last` say whether the line opens or closes the heading (a setext heading has two lines).
    private static func headingStyle(level: Int, fonts: EditorFonts, first: Bool, last: Bool) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = (fonts.size * 0.15).rounded()
        if first { style.paragraphSpacingBefore = (fonts.size * (level <= 2 ? 0.8 : 0.6)).rounded() }
        if last { style.paragraphSpacing = (fonts.size * (level <= 2 ? 0.8 : 0.35)).rounded() }
        return style
    }

    static var baseAttributes: [NSAttributedString.Key: Any] {
        let fonts = EditorFonts()
        return [.font: fonts.body, .foregroundColor: EditorPalette.text, .paragraphStyle: paragraphStyle(for: fonts)]
    }

    /// Styles `target`. The attributes are computed on a scratch copy, then only the paragraphs whose
    /// attributes changed are written back: TextKit 2 discards the measured layout of every paragraph it
    /// is told changed, and re-estimating the heights of the whole document made the content jump
    /// while scrolled (on each caret move between blocks, and while typing).
    static func apply(_ spans: [StyleSpan], to target: NSTextStorage, selection: NSRange, context: ThemeContext) {
        let storage = NSTextStorage(string: target.string)
        style(spans, in: storage, selection: selection, context: context)
        copyChangedParagraphs(from: storage, to: target)
    }

    private static func copyChangedParagraphs(from source: NSTextStorage, to target: NSTextStorage) {
        let text = target.string as NSString
        var changed: [NSRange] = []
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length),
                                 options: [.byParagraphs, .substringNotRequired]) { _, _, paragraph, _ in
            if !target.attributedSubstring(from: paragraph).isEqual(to: source.attributedSubstring(from: paragraph)) {
                changed.append(paragraph)
            }
        }
        guard !changed.isEmpty else { return }
        target.beginEditing()
        for paragraph in changed {
            source.enumerateAttributes(in: paragraph) { attributes, run, _ in
                target.setAttributes(attributes, range: run)
            }
        }
        target.endEditing()
    }

    private static func style(_ spans: [StyleSpan], in storage: NSTextStorage, selection: NSRange, context: ThemeContext) {
        let length = storage.length
        let fonts = EditorFonts()
        storage.beginEditing()
        storage.setAttributes([.font: fonts.body, .foregroundColor: EditorPalette.text,
                               .paragraphStyle: paragraphStyle(for: fonts)],
                              range: NSRange(location: 0, length: length))

        // Blocks first, then inline styles, syntax last so it wins over everything.
        for span in spans.sorted(by: { order($0.kind) < order($1.kind) }) where NSMaxRange(span.range) <= length {
            let range = span.range
            switch span.kind {
            case .heading(let level):
                storage.addAttribute(.font, value: fonts.heading(level: level), range: range)
                if level == 6 { storage.addAttribute(.foregroundColor, value: EditorPalette.secondaryText, range: range) }
                emboldenIfNeeded(range, of: storage)
                styleHeadingLines(in: range, level: level, of: storage, fonts: fonts)
            case .blankLine:
                if !StyleSpan.isActive(block: span.blockRange, selection: selection) {
                    storage.addAttribute(.paragraphStyle, value: blankLineStyle(for: fonts), range: range)
                }
            case .codeBlock:
                storage.addAttribute(.font, value: fonts.code, range: range)
                markCodeBlockLines(in: range, of: storage, fonts: fonts,
                                   fenceHidden: !StyleSpan.isActive(block: span.blockRange, selection: selection))
            case .blockQuote:
                storage.addAttribute(.foregroundColor, value: EditorPalette.secondaryText, range: range)
            case .thematicBreak:
                // Drawn as a thin line (`HorizontalRuleLayoutFragment`); the dashes show only while the
                // caret is on them. The line keeps a normal text height either way.
                let style = NSMutableParagraphStyle()
                style.minimumLineHeight = (fonts.size * 1.4).rounded()
                style.paragraphSpacing = (fonts.size * 0.2).rounded()
                storage.addAttribute(.paragraphStyle, value: style, range: range)
                if StyleSpan.isActive(block: span.blockRange, selection: selection) {
                    storage.addAttribute(.foregroundColor, value: EditorPalette.syntax, range: range)
                } else {
                    storage.addAttributes([.font: hiddenFont, .foregroundColor: NSColor.clear, .horizontalRule: true],
                                          range: range)
                }
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
                    .foregroundColor: EditorPalette.link,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ], range: range)
            case .marker:
                storage.addAttribute(.foregroundColor, value: EditorPalette.secondaryText, range: range)
            case .listItem, .listContinuation:
                break  // Laid out by layOutListItems once every font is final.
            case .syntax:
                if StyleSpan.isActive(block: span.blockRange, selection: selection) {
                    storage.addAttributes([
                        .foregroundColor: EditorPalette.syntax,
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
            case .callout(let kind):
                // Normal text color, not the quote's quieter one; the tint and bar come from the fragment.
                storage.addAttribute(.foregroundColor, value: EditorPalette.text, range: range)
                storage.addAttribute(.callout, value: kind.rawValue,
                                     range: (storage.string as NSString).paragraphRange(for: range))
            case .calloutMarker(let kind):
                let text = storage.string as NSString
                let paragraph = text.paragraphRange(for: range)
                let style = paragraphStyle(for: fonts).mutableCopy() as! NSMutableParagraphStyle
                style.minimumLineHeight = (fonts.body.ascender - fonts.body.descender + fonts.body.leading).rounded(.up)
                style.paragraphSpacingBefore = (fonts.size * 0.5).rounded()
                storage.addAttribute(.paragraphStyle, value: style, range: paragraph)
                // A title written after the marker replaces the kind's name.
                let titleEnd = span.blockRange.location + span.blockRange.length
                let customTitle = NSRange(location: NSMaxRange(range), length: max(0, titleEnd - NSMaxRange(range)))
                let titleFont = NSFontManager.shared.convert(fonts.body, toHaveTrait: .boldFontMask)
                if customTitle.length > 0 {
                    storage.addAttributes([.font: titleFont, .foregroundColor: EditorPalette.callout(kind)], range: customTitle)
                }
                if StyleSpan.isActive(block: span.blockRange, selection: selection) {
                    storage.addAttribute(.foregroundColor, value: EditorPalette.syntax, range: range)
                } else {
                    let label = NSAttributedString(string: customTitle.length > 0 ? "" : kind.title, attributes: [
                        .font: titleFont, .foregroundColor: EditorPalette.callout(kind),
                    ])
                    storage.addAttributes([.font: hiddenFont, .foregroundColor: NSColor.clear], range: range)
                    storage.addAttribute(.calloutTitle, value: label, range: paragraph)
                    // Room for the icon before a custom title.
                    storage.addAttribute(.kern, value: (fonts.size * MarkdownLayoutFragment.calloutIconRoom).rounded(),
                                         range: NSRange(location: NSMaxRange(range) - 1, length: 1))
                }
            case .quoteMarker(let depth, let blank):
                // Hidden; the quote is drawn as bars and indented by indentQuotes.
                storage.addAttributes([.font: hiddenFont, .foregroundColor: NSColor.clear], range: range)
                let paragraph = (storage.string as NSString).paragraphRange(for: range)
                storage.addAttribute(.quoteBars, value: QuoteBars(depth: depth, step: (fonts.size * quoteStep).rounded()),
                                     range: paragraph)
                if blank, !StyleSpan.isActive(block: span.blockRange, selection: selection) {
                    storage.addAttribute(.paragraphStyle, value: blankLineStyle(for: fonts), range: paragraph)
                }
            case .taskMarker(let checked):
                // The prefix is hidden; the kern on its last character leaves room for the drawn checkbox.
                storage.addAttributes([.font: hiddenFont, .foregroundColor: NSColor.clear, .taskCheckbox: checked],
                                      range: range)
                storage.addAttribute(.kern, value: TaskLayoutFragment.checkboxWidth,
                                     range: NSRange(location: NSMaxRange(range) - 1, length: 1))
            case .completedTask:
                storage.addAttribute(.foregroundColor, value: EditorPalette.secondaryText, range: range)
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
                    attributes[.foregroundColor] = EditorPalette.syntax
                } else {
                    attributes[.font] = hiddenFont
                    attributes[.foregroundColor] = NSColor.clear
                }
                storage.addAttributes(attributes, range: range)
            }
        }
        layOutListItems(spans, in: storage, fonts: fonts)
        indentQuotes(in: storage)
        layOutTables(spans, in: storage, selection: selection, availableWidth: context.availableWidth, fonts: fonts)
        storage.endEditing()
    }

    private static let codeBackground = EditorPalette.inlineCodeBackground

    /// Lays out list items as in Typora. Each nesting level is indented by `listLevelIndent`, whatever
    /// the indentation in the source, and wrapped lines hang under the item's text. A `-`, `*` or `+`
    /// stays in the text but is drawn as a bullet that depends on the depth (`ListItemLayoutFragment`).
    /// Items sit closer together than paragraphs: the gap after a list comes from its blank line.
    private static func layOutListItems(_ spans: [StyleSpan], in storage: NSTextStorage, fonts: EditorFonts) {
        let text = storage.string as NSString
        func width(_ range: NSRange) -> CGFloat {
            range.length > 0 ? storage.attributedSubstring(from: range).size().width : 0
        }
        func level(_ depth: Int) -> CGFloat {
            (fonts.size * (listBaseIndent + CGFloat(depth) * listLevelIndent)).rounded()
        }

        // Markers are right-aligned in a column as wide as the list's widest marker, so the text of
        // every item starts at the same place and numbers line up on their dot (9. and 10.).
        var columns: [Int: CGFloat] = [:]
        for span in spans {
            guard case .listItem(let depth, let bullet, let list) = span.kind, span.range.length > 0 else { continue }
            if bullet {
                // Room between the bullet and the text, as kern on the hidden marker character.
                let character = NSRange(location: span.range.location, length: 1)
                storage.addAttributes([
                    .foregroundColor: NSColor.clear,
                    .listBullet: depth,
                    .kern: max(0, (fonts.size * listBulletWidth).rounded() - width(character)),
                ], range: character)
            }
            columns[list] = max(columns[list] ?? (fonts.size * listMarkerColumn).rounded(), width(span.range))
        }

        for span in spans {
            switch span.kind {
            case .listItem(let depth, _, let list) where span.range.length > 0:
                let marker = span.range
                let line = text.lineRange(for: NSRange(location: marker.location, length: 0))
                let leadingWidth = width(NSRange(location: line.location, length: marker.location - line.location))
                let markerWidth = width(marker)
                let column = columns[list] ?? markerWidth
                let indent = max(0, level(depth) + column - markerWidth - leadingWidth)
                let style = paragraphStyle(for: fonts).mutableCopy() as! NSMutableParagraphStyle
                style.paragraphSpacing = (fonts.size * 0.12).rounded()
                style.firstLineHeadIndent = indent
                style.headIndent = indent + leadingWidth + markerWidth
                storage.addAttribute(.paragraphStyle, value: style, range: text.paragraphRange(for: marker))
            case .listContinuation(let depth, let list):
                // Under the item's text.
                let textStart = level(depth) + (columns[list] ?? (fonts.size * listMarkerColumn).rounded())
                text.enumerateSubstrings(in: span.range, options: [.byLines, .substringNotRequired]) { _, line, _, _ in
                    let paragraph = text.paragraphRange(for: line)
                    let leadingWidth = width(NSRange(location: paragraph.location, length: line.location - paragraph.location))
                    let style = paragraphStyle(for: fonts).mutableCopy() as! NSMutableParagraphStyle
                    style.firstLineHeadIndent = max(0, textStart - leadingWidth)
                    style.headIndent = textStart
                    storage.addAttribute(.paragraphStyle, value: style, range: paragraph)
                }
            default:
                break
            }
        }
    }

    /// Shifts every quote line right by its bars, on top of the indentation it already has (lists).
    private static func indentQuotes(in storage: NSTextStorage) {
        let text = storage.string as NSString
        storage.enumerateAttribute(.quoteBars, in: NSRange(location: 0, length: storage.length)) { value, run, _ in
            guard let bars = value as? QuoteBars else { return }
            text.enumerateSubstrings(in: run, options: [.byParagraphs, .substringNotRequired]) { _, _, paragraph, _ in
                guard paragraph.length > 0,
                      let current = storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
                else { return }
                let style = current.mutableCopy() as! NSMutableParagraphStyle
                style.firstLineHeadIndent += bars.indent
                style.headIndent += bars.indent
                if storage.attribute(.callout, at: paragraph.location, effectiveRange: nil) != nil {
                    style.tailIndent = -bars.step / 2  // The tint runs to the edge; keep the text off it.
                    // The tint covers the last line's paragraph spacing: keep some room under the text.
                    let next = NSMaxRange(paragraph)
                    if next >= storage.length || storage.attribute(.callout, at: next, effectiveRange: nil) == nil {
                        style.paragraphSpacing = max(style.paragraphSpacing, (bars.step * 0.45).rounded())
                    }
                }
                storage.addAttribute(.paragraphStyle, value: style, range: paragraph)
            }
        }
    }

    /// Width of one quote level (bar and gap), in multiples of the text size.
    private static let quoteStep: CGFloat = 1.2

    /// List geometry, in multiples of the text size.
    private static let listBaseIndent: CGFloat = 0.2
    private static let listLevelIndent: CGFloat = 1.8
    private static let listMarkerColumn: CGFloat = 1.6
    private static let listBulletWidth: CGFloat = 1.2

    /// Gives each line of a heading its spacing, and marks the last line of an H1 or H2 for the thin
    /// rule `HeadingLayoutFragment` draws under it.
    private static func styleHeadingLines(in range: NSRange, level: Int, of storage: NSTextStorage, fonts: EditorFonts) {
        let text = storage.string as NSString
        var lines: [NSRange] = []
        text.enumerateSubstrings(in: range, options: [.byLines, .substringNotRequired]) { _, line, _, _ in
            lines.append(line)
        }
        for (index, line) in lines.enumerated() {
            let paragraph = text.paragraphRange(for: line)
            let isLast = index == lines.count - 1
            storage.addAttribute(.paragraphStyle, value: headingStyle(level: level, fonts: fonts, first: index == 0, last: isLast),
                                 range: paragraph)
            if isLast, level <= 2 {
                storage.addAttribute(.headingRule, value: (fonts.size * 0.3).rounded(), range: paragraph)
            }
        }
    }

    private static func order(_ kind: StyleSpan.Kind) -> Int {
        switch kind {
        case .heading, .codeBlock, .blockQuote, .thematicBreak, .blankLine: 0
        case .inlineCode, .codeToken: 1
        case .strong, .emphasis, .strikethrough, .link, .marker, .completedTask, .tableRow, .tableCell, .listItem, .listContinuation, .callout: 2
        case .syntax, .taskMarker, .tablePipe, .quoteMarker, .calloutMarker: 3
        case .blockImage: 4
        }
    }

    /// Tags each line with its position in the block, which `CodeBlockLayoutFragment` uses to draw
    /// the full-width panel, and gives the lines padded, gap-free paragraph styles.
    /// The opening fence of a block that names a language keeps a full line's height, hidden or not,
    /// and shows the language there while it is hidden.
    private static func markCodeBlockLines(in range: NSRange, of storage: NSTextStorage, fonts: EditorFonts,
                                           fenceHidden: Bool) {
        let text = storage.string as NSString
        let language = CodeBlockText.language(of: text.substring(with: range))
        var lines: [NSRange] = []
        text.enumerateSubstrings(in: text.lineRange(for: range), options: [.byLines, .substringNotRequired]) { _, _, enclosingLine, _ in
            // The enclosing range includes the newline, so empty lines inside the block are tagged too.
            lines.append(enclosingLine)
        }
        for (index, line) in lines.enumerated() {
            var edges: CodeBlockEdges = []
            if index == 0 { edges.insert(.top) }
            if index == lines.count - 1 { edges.insert(.bottom) }
            var style = codeParagraphStyle(edges)
            if index == 0, let language {
                let fenceStyle = style.mutableCopy() as! NSMutableParagraphStyle
                fenceStyle.minimumLineHeight = codeLineHeight(fonts)
                style = fenceStyle
                if fenceHidden {
                    storage.addAttribute(.codeLanguage, value: languageLabel(language, fonts: fonts), range: line)
                }
            }
            storage.addAttributes([
                .codeBlockEdges: edges.rawValue,
                .paragraphStyle: style,
            ], range: line)
        }
    }

    private static func codeLineHeight(_ fonts: EditorFonts) -> CGFloat {
        (fonts.code.ascender - fonts.code.descender + fonts.code.leading).rounded(.up)
    }

    private static func languageLabel(_ language: String, fonts: EditorFonts) -> NSAttributedString {
        NSAttributedString(string: language, attributes: [
            .font: NSFont.systemFont(ofSize: (fonts.size * 0.75).rounded(), weight: .medium),
            .foregroundColor: EditorPalette.secondaryText,
        ])
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

    private static func codeColor(_ kind: CodeTokenKind) -> NSColor {
        switch kind {
        case .keyword: EditorPalette.codeKeyword
        case .type: EditorPalette.codeType
        case .string: EditorPalette.codeString
        case .number: EditorPalette.codeNumber
        case .comment: EditorPalette.codeComment
        case .attribute: EditorPalette.codeAttribute
        case .property: EditorPalette.codeProperty
        }
    }

    private static func imageParagraphStyle(imageHeight: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = imageHeight + ImageLayoutFragment.gap + 6
        style.paragraphSpacing = 10
        return style
    }

    // MARK: Tables

    static let tableCellPadding: CGFloat = 12

    private static func tableRowParagraphStyle(_ role: TableRowRole) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let padding = role.contains(.delimiter) ? 0 : TableRowLayoutFragment.verticalPadding
        style.lineSpacing = 0
        style.paragraphSpacingBefore = padding + (role.contains(.first) ? 8 : 0)
        style.paragraphSpacing = padding + (role.contains(.last) ? 10 : 0)
        return style
    }

    /// A table narrower than this share of the text column keeps its natural width.
    static let narrowTableRatio: CGFloat = 2.0 / 3.0

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
                if natural > availableWidth {
                    clipRows(tableSpans, in: storage)
                    alignColumns(cells, in: storage, fillWidth: 0)
                    continue
                }
            }
            // Tables span the whole text column, like in Typora (1 pt is left for the right border),
            // unless they are narrow: stretching a two-column table across the page only spreads it out.
            let fills = natural >= availableWidth * narrowTableRatio
            alignColumns(cells, in: storage, fillWidth: fills ? max(availableWidth - 1, 0) : 0)
        }
    }

    /// The cell's text without the spaces around it, which are hidden: padding comes from kern.
    private static func contentRange(of cell: NSRange, in text: NSString) -> NSRange {
        var start = cell.location
        var end = NSMaxRange(cell)
        func isSpace(_ index: Int) -> Bool {
            let character = text.character(at: index)
            return character == unichar(UInt8(ascii: " ")) || character == unichar(UInt8(ascii: "\t"))
        }
        while start < end, isSpace(start) { start += 1 }
        while end > start, isSpace(end - 1) { end -= 1 }
        return NSRange(location: start, length: end - start)
    }

    private static func contentWidth(of cell: NSRange, in storage: NSTextStorage) -> CGFloat {
        let content = contentRange(of: cell, in: storage.string as NSString)
        return content.length > 0 ? storage.attributedSubstring(from: content).size().width : 0
    }

    /// Width of each column once aligned: its widest cell text, without padding.
    private static func columnWidths(of cells: [StyleSpan], in storage: NSTextStorage) -> [Int: CGFloat] {
        var widths: [Int: CGFloat] = [:]
        for cell in cells {
            guard case .tableCell(let column, _) = cell.kind else { continue }
            widths[column] = max(widths[column] ?? 0, contentWidth(of: cell.range, in: storage))
        }
        return widths
    }

    /// Width of the table once aligned: the widest cell of each column, plus cell padding.
    private static func naturalWidth(of cells: [StyleSpan], in storage: NSTextStorage) -> CGFloat {
        let widths = columnWidths(of: cells, in: storage)
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
        let visible: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: EditorPalette.syntax]
        for span in spans {
            switch span.kind {
            case .tableRow(let role):
                storage.removeAttribute(.tableRow, range: span.range)
                storage.addAttribute(.paragraphStyle, value: paragraphStyle(for: EditorFonts()), range: span.range)
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
    /// of the widest cell in its column. Alignment decides how the extra space is split. When
    /// `fillWidth` is larger than the table, the columns grow in proportion to their width until the
    /// table fills it. The spaces around each cell's text are hidden, so only the text is measured
    /// and right or centered alignment is exact whatever the source padding.
    private static func alignColumns(_ cells: [StyleSpan], in storage: NSTextStorage, fillWidth: CGFloat) {
        let text = storage.string as NSString
        let pipe = unichar(UInt8(ascii: "|"))
        var cellWidths: [CGFloat] = []
        for cell in cells {
            cellWidths.append(contentWidth(of: cell.range, in: storage))
            let content = contentRange(of: cell.range, in: text)
            let padding = [NSRange(location: cell.range.location, length: content.location - cell.range.location),
                           NSRange(location: NSMaxRange(content), length: NSMaxRange(cell.range) - NSMaxRange(content))]
            for range in padding where range.length > 0 {
                storage.addAttributes([.font: hiddenFont, .foregroundColor: NSColor.clear], range: range)
            }
        }
        var widths = columnWidths(of: cells, in: storage)
        let natural = widths.values.reduce(0, +) + CGFloat(widths.count) * 2 * tableCellPadding
        if fillWidth > natural, !widths.isEmpty {
            let weights = widths.mapValues { $0 + 2 * tableCellPadding }
            let total = weights.values.reduce(0, +)
            for (column, weight) in weights {
                widths[column, default: 0] += ((fillWidth - natural) * weight / total).rounded(.down)
            }
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

    /// Makes text bold or italic. Fonts without a bold or italic variant (AppleGothic, for example) get
    /// a synthesized one instead (thicker strokes, slanted glyphs), so emphasis always shows.
    private static func addTrait(_ trait: NSFontTraitMask, in range: NSRange, of storage: NSTextStorage) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let font = value as? NSFont, font.pointSize >= 1 else { return }  // leave hidden syntax alone
            let manager = NSFontManager.shared
            let converted = manager.convert(font, toHaveTrait: trait)
            // Trust the conversion only if it really changed the font (a heavier weight, another face):
            // for faces with no variant, AppKit may report the trait without changing anything.
            let isReal = trait == .boldFontMask
                ? manager.weight(of: converted) > manager.weight(of: font)
                : converted.fontName != font.fontName && manager.traits(of: converted).contains(.italicFontMask)
            if isReal {
                storage.addAttribute(.font, value: converted, range: subrange)
            } else if trait == .italicFontMask {
                storage.addAttribute(.font, value: slanted(font), range: subrange)
            } else {
                // No bold variant: a negative stroke width fills and outlines the glyphs (faux bold).
                storage.addAttribute(.strokeWidth, value: -6, range: subrange)
            }
        }
    }

    /// Faux bold for headings in a font with no bold variant (see `addTrait`).
    private static func emboldenIfNeeded(_ range: NSRange, of storage: NSTextStorage) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let font = value as? NSFont, font.pointSize >= 1,
                  !NSFontManager.shared.traits(of: font).contains(.boldFontMask),
                  NSFontManager.shared.weight(of: font) < 8 else { return }
            storage.addAttribute(.strokeWidth, value: -6, range: subrange)
        }
    }

    /// Faux italic for fonts with no italic variant: the same font with its glyphs sheared about 11°.
    private static func slanted(_ font: NSFont) -> NSFont {
        let size = font.pointSize
        let matrix = AffineTransform(m11: size, m12: 0, m21: size * 0.2, m22: size, tX: 0, tY: 0)
        return NSFont(descriptor: font.fontDescriptor.withMatrix(matrix), size: size) ?? font
    }

}
