import AppKit

extension NSAttributedString.Key {
    /// Set on every line of a code block. The value is a `CodeBlockEdges` raw value.
    static let codeBlockEdges = NSAttributedString.Key("emdi.codeBlockEdges")
    /// Set on the hidden opening fence of a code block that names a language. The value is the styled
    /// label (an `NSAttributedString`) that `CodeBlockLayoutFragment` draws there.
    static let codeLanguage = NSAttributedString.Key("emdi.codeLanguage")
    /// Set on the hidden `- [ ] ` prefix of a task item. The value is a Bool, true when checked.
    static let taskCheckbox = NSAttributedString.Key("emdi.taskCheckbox")
    /// Set on each table line. The value is a `TableRowRole` raw value.
    static let tableRow = NSAttributedString.Key("emdi.tableRow")
    /// Set on each hidden `|` of a table. The value is a CGFloat: how far after the pipe its border is drawn.
    static let tablePipe = NSAttributedString.Key("emdi.tablePipe")
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

        return NSTextLayoutFragment(textElement: textElement, range: range)
    }
}
