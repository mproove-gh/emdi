import Foundation
import Markdown

/// Where a Markdown link leads, for ⌘-click. Pure: the editor decides how to open it.
enum LinkTarget: Equatable {
    /// A web page, mail address or other URL with a scheme: handed to the system.
    case url(URL)
    /// A local file (relative to the document's folder, or absolute).
    case file(URL)
    /// `#anchor`: a heading of this document.
    case anchor(String)

    /// A link or image of the document, with its destination as written.
    struct Link: Equatable {
        var range: NSRange
        var destination: String
    }

    /// Every link and image in `text` (reference links come resolved).
    static func links(in text: String) -> [Link] {
        var collector = LinkCollector(map: SourceMap(text))
        collector.visit(Document(parsing: text))
        return collector.links
    }

    /// The innermost link or image whose source range contains `offset`.
    static func link(at offset: Int, in text: String) -> Link? {
        links(in: text)
            .filter { offset >= $0.range.location && offset < NSMaxRange($0.range) }
            .min { $0.range.length < $1.range.length }
    }

    /// The target of `destination`, or nil when it leads nowhere emdi can go: a relative path in an
    /// unsaved document, or nothing at all.
    static func resolve(_ destination: String, relativeTo documentURL: URL?) -> LinkTarget? {
        let destination = destination.trimmingCharacters(in: .whitespaces)
        guard !destination.isEmpty else { return nil }
        if destination.hasPrefix("#") {
            let anchor = String(destination.dropFirst())
            return anchor.isEmpty ? nil : .anchor(anchor.removingPercentEncoding ?? anchor)
        }
        if let url = URL(string: destination), let scheme = url.scheme, scheme.count > 1 {
            return url.isFileURL ? .file(url) : .url(url)
        }
        if destination.lowercased().hasPrefix("www."), let url = URL(string: "https://" + destination) {
            return .url(url)
        }
        // A path: drop any #fragment or ?query, undo percent-encoding.
        var path = destination
        if let cut = path.firstIndex(where: { $0 == "#" || $0 == "?" }) { path = String(path[..<cut]) }
        path = path.removingPercentEncoding ?? path
        guard !path.isEmpty else { return nil }
        path = (path as NSString).expandingTildeInPath
        if path.hasPrefix("/") { return .file(URL(fileURLWithPath: path).standardizedFileURL) }
        guard let folder = documentURL?.deletingLastPathComponent() else { return nil }
        return .file(folder.appendingPathComponent(path).standardizedFileURL)
    }

    /// GitHub's anchor for a heading: lowercase, punctuation removed, spaces become hyphens.
    static func slug(_ heading: String) -> String {
        let kept = heading.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" || $0 == " "
        }
        return String(String.UnicodeScalarView(kept)).replacingOccurrences(of: " ", with: "-")
    }

    /// The source range of the heading `anchor` points to. A repeated heading is reached as
    /// `name-1`, `name-2`…, like on GitHub.
    static func heading(forAnchor anchor: String, in text: String) -> NSRange? {
        var collector = HeadingCollector(map: SourceMap(text))
        collector.visit(Document(parsing: text))
        var counts: [String: Int] = [:]
        let wanted = anchor.lowercased()
        for (title, range) in collector.headings {
            let base = slug(title)
            let count = counts[base, default: 0]
            counts[base] = count + 1
            if (count == 0 ? base : "\(base)-\(count)") == wanted { return range }
        }
        return nil
    }
}

private struct LinkCollector: MarkupWalker {
    let map: SourceMap
    var links: [LinkTarget.Link] = []

    mutating func visitLink(_ link: Markdown.Link) {
        if let range = link.range, let destination = link.destination {
            links.append(.init(range: map.nsRange(of: range), destination: destination))
        }
        descendInto(link)
    }

    mutating func visitImage(_ image: Image) {
        if let range = image.range, let source = image.source {
            links.append(.init(range: map.nsRange(of: range), destination: source))
        }
        descendInto(image)
    }
}

private struct HeadingCollector: MarkupWalker {
    let map: SourceMap
    var headings: [(String, NSRange)] = []

    mutating func visitHeading(_ heading: Heading) {
        if let range = heading.range { headings.append((heading.plainText, map.nsRange(of: range))) }
    }
}
