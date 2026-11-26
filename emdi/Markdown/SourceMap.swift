import Foundation
import Markdown

/// Converts swift-markdown source locations (1-based line, 1-based UTF-8 byte column)
/// into UTF-16 offsets, which is what NSString, NSRange and NSTextView use.
struct SourceMap {
    private let text: String
    private let utf8LineStarts: [Int]
    private let utf8Count: Int

    init(_ text: String) {
        self.text = text
        var starts = [0]
        var offset = 0
        for byte in text.utf8 {
            offset += 1
            if byte == UInt8(ascii: "\n") { starts.append(offset) }
        }
        utf8LineStarts = starts
        utf8Count = offset
    }

    func utf16Offset(of location: SourceLocation) -> Int {
        let line = min(max(location.line - 1, 0), utf8LineStarts.count - 1)
        let utf8Offset = min(utf8LineStarts[line] + max(location.column - 1, 0), utf8Count)
        let utf8 = text.utf8
        let index = utf8.index(utf8.startIndex, offsetBy: utf8Offset)
        return text.utf16.distance(from: text.utf16.startIndex, to: index)
    }

    func nsRange(of range: SourceRange) -> NSRange {
        let start = utf16Offset(of: range.lowerBound)
        let end = utf16Offset(of: range.upperBound)
        return NSRange(location: start, length: max(end - start, 0))
    }
}
