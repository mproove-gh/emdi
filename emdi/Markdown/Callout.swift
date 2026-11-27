import Foundation

/// The kinds of GitHub-style callouts: a block quote whose first line is `[!NOTE]`, `[!TIP]`, …
enum CalloutKind: String, CaseIterable, Sendable {
    case note, tip, important, warning, caution

    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    private static let opening = try! NSRegularExpression(pattern: "^[ \\t]*>[ \\t]?(\\[!([A-Za-z]+)\\])[ \\t]*")

    /// The callout opened by the first line of a quote, and the range of its `[!KIND]` marker
    /// (with the spaces after it) in `text`.
    static func opening(of line: NSRange, in text: NSString) -> (kind: CalloutKind, marker: NSRange)? {
        guard let match = opening.firstMatch(in: text as String, range: line),
              let kind = CalloutKind(rawValue: text.substring(with: match.range(at: 2)).lowercased()) else { return nil }
        let start = match.range(at: 1).location
        return (kind, NSRange(location: start, length: NSMaxRange(match.range) - start))
    }
}
