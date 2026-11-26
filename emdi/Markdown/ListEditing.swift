import Foundation

/// Editing helpers for list and quote lines: Return continues the list, Tab / Shift-Tab nest it.
/// Pure: each function returns the `TextEdit` to apply, or nil to let the text view behave normally.
enum ListEditing {
    /// Indentation and quote markers, then a bullet or number, its spaces, and an optional task box.
    private static let listLine = try! NSRegularExpression(
        pattern: "^([ \\t]*(?:>[ \\t]?)*[ \\t]*)([-*+]|(\\d{1,9})([.)]))([ \\t]+)(\\[[ xX]\\][ \\t]+)?")
    private static let quoteLine = try! NSRegularExpression(pattern: "^([ \\t]*(?:>[ \\t]?)+)")

    private struct ListPrefix {
        var length: Int
        var lead: String
        var number: Int?
        var delimiter: String
        var bullet: String
        var spacing: String
        var isTask: Bool
        /// Bullet or number plus the spaces after it: how far a nested item must be indented.
        var markerWidth: Int { ((number.map(String.init) ?? bullet) + delimiter + spacing as NSString).length }
    }

    private static func listPrefix(of line: String) -> ListPrefix? {
        let ns = line as NSString
        guard let match = listLine.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ index: Int) -> String? {
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : ns.substring(with: range)
        }
        return ListPrefix(length: match.range.length, lead: group(1) ?? "", number: group(3).flatMap { Int($0) },
                          delimiter: group(4) ?? "", bullet: group(2) ?? "-", spacing: group(5) ?? " ",
                          isTask: group(6) != nil)
    }

    private static func lineContent(in text: NSString, at location: Int) -> NSRange {
        var line = text.lineRange(for: NSRange(location: location, length: 0))
        if line.length > 0, text.character(at: NSMaxRange(line) - 1) == unichar(UInt8(ascii: "\n")) { line.length -= 1 }
        return line
    }

    /// Return at the caret. Continues a list item (next number, an unchecked box for tasks) or a quote.
    /// On an empty item, removes its marker instead, which ends the list.
    static func newline(in text: NSString, selection: NSRange) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        let caret = selection.location
        let line = lineContent(in: text, at: caret)
        let content = text.substring(with: line)
        let column = caret - line.location
        let after = (content as NSString).substring(from: column)

        if let prefix = listPrefix(of: content), column >= prefix.length {
            let body = (content as NSString).substring(from: prefix.length)
            if body.trimmingCharacters(in: .whitespaces).isEmpty {
                return endList(line: line, caret: caret, keeping: quoteLead(of: prefix.lead))
            }
            let marker = prefix.number.map { "\($0 + 1)\(prefix.delimiter)" } ?? prefix.bullet
            let newPrefix = prefix.lead + marker + prefix.spacing + (prefix.isTask ? "[ ] " : "")
            return insertion("\n" + newPrefix, at: caret)
        }

        let ns = content as NSString
        if let match = quoteLine.firstMatch(in: content, range: NSRange(location: 0, length: ns.length)),
           column >= match.range.length {
            let lead = ns.substring(with: match.range(at: 1))
            if ns.substring(from: match.range.length).trimmingCharacters(in: .whitespaces).isEmpty, after.isEmpty {
                return endList(line: line, caret: caret, keeping: "")
            }
            return insertion("\n" + lead, at: caret)
        }
        return nil
    }

    /// Tab on list lines: indent each one by its marker's width, so it nests under the item above.
    static func indent(in text: NSString, selection: NSRange) -> TextEdit? {
        editListLines(in: text, selection: selection) { line, prefix in
            String(repeating: " ", count: prefix.markerWidth) + line
        }
    }

    /// Shift-Tab on list lines: remove up to one marker width of leading spaces (a tab counts as one level).
    static func outdent(in text: NSString, selection: NSRange) -> TextEdit? {
        editListLines(in: text, selection: selection) { line, prefix in
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            let spaces = line.prefix(while: { $0 == " " }).count
            return String(line.dropFirst(min(spaces, prefix.markerWidth)))
        }
    }

    // MARK: Helpers

    private static func quoteLead(of lead: String) -> String {
        lead.contains(">") ? String(lead.prefix(through: lead.lastIndex(of: ">")!)) + " " : ""
    }

    private static func insertion(_ string: String, at caret: Int) -> TextEdit {
        TextEdit(range: NSRange(location: caret, length: 0), replacement: string,
                 selection: NSRange(location: caret + (string as NSString).length, length: 0))
    }

    private static func endList(line: NSRange, caret: Int, keeping lead: String) -> TextEdit {
        TextEdit(range: line, replacement: lead,
                 selection: NSRange(location: line.location + (lead as NSString).length, length: 0))
    }

    /// Applies `transform` to every list line touched by the selection, or returns nil if there is none.
    private static func editListLines(in text: NSString, selection: NSRange,
                                      transform: (String, ListPrefix) -> String) -> TextEdit? {
        var range = text.lineRange(for: selection)
        if range.length > 0, text.character(at: NSMaxRange(range) - 1) == unichar(UInt8(ascii: "\n")) { range.length -= 1 }
        let lines = text.substring(with: range).components(separatedBy: "\n")

        var changed = false
        var caretShift = 0
        let newLines = lines.enumerated().map { index, line -> String in
            guard let prefix = listPrefix(of: line) else { return line }
            changed = true
            let result = transform(line, prefix)
            if index == 0 { caretShift = (result as NSString).length - (line as NSString).length }
            return result
        }
        guard changed else { return nil }

        let replacement = newLines.joined(separator: "\n")
        let newSelection: NSRange
        if lines.count == 1 {
            // Keep the caret (or selection) on the same text.
            newSelection = NSRange(location: max(selection.location + caretShift, range.location), length: selection.length)
        } else {
            newSelection = NSRange(location: range.location, length: (replacement as NSString).length)
        }
        return TextEdit(range: range, replacement: replacement, selection: newSelection)
    }
}
