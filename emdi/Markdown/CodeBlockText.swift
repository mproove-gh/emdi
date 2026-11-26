import Foundation

enum CodeBlockText {
    /// The code inside a code block's source: fence lines removed (fenced blocks)
    /// or the 4-space indentation removed (indented blocks). This is what the copy button copies.
    static func content(of source: String) -> String {
        var lines = source.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        guard let first = lines.first else { return "" }

        if isFence(first) {
            lines.removeFirst()
            if let last = lines.last, isFence(last) { lines.removeLast() }
            return lines.joined(separator: "\n")
        }
        return lines.map { line in
            var line = Substring(line)
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            var removed = 0
            while removed < 4, line.first == " " { line = line.dropFirst(); removed += 1 }
            return String(line)
        }.joined(separator: "\n")
    }

    private static func isFence(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }
}
