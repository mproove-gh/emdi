import AppKit

extension NSAttributedString.Key {
    /// Set on every line of a code block. The value is a `CodeBlockEdges` raw value.
    static let codeBlockEdges = NSAttributedString.Key("emdi.codeBlockEdges")
    /// Set on the hidden opening fence of a code block that names a language. The value is the styled
    /// label (an `NSAttributedString`) that `CodeBlockLayoutFragment` draws there.
    static let codeLanguage = NSAttributedString.Key("emdi.codeLanguage")
    /// Set on the hidden `- [ ] ` prefix of a task item. The value is a Bool, true when checked.
    static let taskCheckbox = NSAttributedString.Key("emdi.taskCheckbox")
    /// Set on the hidden `-`, `*` or `+` of a bullet list item. The value is the item's nesting depth (Int).
    static let listBullet = NSAttributedString.Key("emdi.listBullet")
    /// Set on each line of a block quote. The value is a `QuoteBars`.
    static let quoteBars = NSAttributedString.Key("emdi.quoteBars")
    /// Set on each line of a callout. The value is a `CalloutKind` raw value.
    static let callout = NSAttributedString.Key("emdi.callout")
    /// Set on the first line of a callout while its `[!KIND]` marker is hidden. The value is the styled
    /// name drawn after the icon (empty when the line has its own title).
    static let calloutTitle = NSAttributedString.Key("emdi.calloutTitle")
    /// Set on each table line. The value is a `TableRowRole` raw value.
    static let tableRow = NSAttributedString.Key("emdi.tableRow")
    /// Set on each hidden `|` of a table. The value is a CGFloat: how far after the pipe its border is drawn.
    static let tablePipe = NSAttributedString.Key("emdi.tablePipe")
    /// Set on the last line of an H1 or H2, drawn with a rule under it by `HeadingLayoutFragment`.
    /// The value is a CGFloat: the gap between the text and the rule.
    static let headingRule = NSAttributedString.Key("emdi.headingRule")
    /// Set on a hidden `---` line, drawn as a rule by `HorizontalRuleLayoutFragment`.
    static let horizontalRule = NSAttributedString.Key("emdi.horizontalRule")
    /// Set on a paragraph that holds only an image. The value is a `BlockImage`.
    static let blockImage = NSAttributedString.Key("emdi.blockImage")
}

/// Chooses a layout fragment for each paragraph from the attributes `MarkdownTheme` set on it:
/// code block lines, images, table rows and task items get custom drawing, everything else the default fragment.
/// Separate from the `@MainActor` coordinator because TextKit calls it nonisolated.
final class MarkdownLayoutDelegate: NSObject, NSTextLayoutManagerDelegate {
    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager,
                           textLayoutFragmentFor location: any NSTextLocation,
                           in textElement: NSTextElement) -> NSTextLayoutFragment {
        let fragment = makeFragment(for: textElement)
        if let fragment = fragment as? MarkdownLayoutFragment, let paragraph = textElement as? NSTextParagraph,
           paragraph.attributedString.length > 0 {
            let string = paragraph.attributedString
            fragment.quoteBars = string.attribute(.quoteBars, at: 0, effectiveRange: nil) as? QuoteBars
            fragment.callout = (string.attribute(.callout, at: 0, effectiveRange: nil) as? String).flatMap(CalloutKind.init)
            fragment.calloutTitle = string.attribute(.calloutTitle, at: 0, effectiveRange: nil) as? NSAttributedString
        }
        return fragment
    }

    private func makeFragment(for textElement: NSTextElement) -> NSTextLayoutFragment {
        let range = textElement.elementRange
        guard let paragraph = textElement as? NSTextParagraph, paragraph.attributedString.length > 0 else {
            return NSTextLayoutFragment(textElement: textElement, range: range)
        }
        let string = paragraph.attributedString
        let whole = NSRange(location: 0, length: string.length)

        if let edges = string.attribute(.codeBlockEdges, at: 0, effectiveRange: nil) as? Int {
            let fragment = CodeBlockLayoutFragment(textElement: textElement, range: range)
            fragment.edges = CodeBlockEdges(rawValue: edges)
            fragment.languageLabel = string.attribute(.codeLanguage, at: 0, effectiveRange: nil) as? NSAttributedString
            return fragment
        }

        if let gap = string.attribute(.headingRule, at: 0, effectiveRange: nil) as? CGFloat {
            let fragment = HeadingLayoutFragment(textElement: textElement, range: range)
            fragment.ruleGap = gap
            return fragment
        }

        if string.attribute(.horizontalRule, at: 0, effectiveRange: nil) != nil {
            return HorizontalRuleLayoutFragment(textElement: textElement, range: range)
        }

        if let image = string.attribute(.blockImage, at: 0, effectiveRange: nil) as? BlockImage {
            let fragment = ImageLayoutFragment(textElement: textElement, range: range)
            fragment.blockImage = image
            return fragment
        }

        if let role = string.attribute(.tableRow, at: 0, effectiveRange: nil) as? Int {
            let fragment = TableRowLayoutFragment(textElement: textElement, range: range)
            fragment.role = TableRowRole(rawValue: role)
            fragment.isClipped = (string.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?
                .lineBreakMode == .byClipping
            string.enumerateAttribute(.tablePipe, in: whole, options: .longestEffectiveRangeNotRequired) { value, pipes, _ in
                guard let offset = value as? CGFloat else { return }
                for index in pipes.location..<NSMaxRange(pipes) {
                    fragment.pipes.append((index: index, borderOffset: offset))
                }
            }
            return fragment
        }

        var task: (range: NSRange, checked: Bool)?
        string.enumerateAttribute(.taskCheckbox, in: whole) { value, prefix, stop in
            guard let checked = value as? Bool else { return }
            task = (prefix, checked)
            stop.pointee = true
        }
        if let task {
            let fragment = TaskLayoutFragment(textElement: textElement, range: range)
            fragment.prefixRange = task.range
            fragment.isChecked = task.checked
            return fragment
        }

        var bullet: (index: Int, depth: Int)?
        string.enumerateAttribute(.listBullet, in: whole) { value, marker, stop in
            guard let depth = value as? Int else { return }
            bullet = (marker.location, depth)
            stop.pointee = true
        }
        if let bullet {
            let fragment = ListItemLayoutFragment(textElement: textElement, range: range)
            fragment.bulletIndex = bullet.index
            fragment.depth = bullet.depth
            return fragment
        }

        return MarkdownLayoutFragment(textElement: textElement, range: range)
    }
}
