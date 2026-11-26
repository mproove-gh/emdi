import Foundation

enum ImageSource {
    /// The local file an image destination points to. Relative paths are resolved against the folder
    /// of the document (`documentURL`). Remote images (`http`, `https`, …) are not loaded: emdi only shows
    /// local images, and never makes network requests.
    static func resolve(_ source: String, relativeTo documentURL: URL?) -> URL? {
        var source = source.trimmingCharacters(in: .whitespaces)
        if source.hasPrefix("<"), source.hasSuffix(">") { source = String(source.dropFirst().dropLast()) }
        guard !source.isEmpty else { return nil }

        if let url = URL(string: source), let scheme = url.scheme {
            return scheme == "file" ? url : nil
        }
        let path = source.removingPercentEncoding ?? source
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        if path.hasPrefix("~") { return URL(fileURLWithPath: (path as NSString).expandingTildeInPath) }
        guard let folder = documentURL?.deletingLastPathComponent() else { return nil }
        return folder.appending(path: path).standardizedFileURL
    }

    /// The Markdown for a dropped image file: `![name](path)`. The path is relative to the
    /// document's folder when the document is saved (`../` included), absolute otherwise.
    /// Paths with spaces or parentheses use the `<…>` form, which `resolve` understands.
    static func markdown(forImageAt imageURL: URL, relativeTo documentURL: URL?) -> String {
        let path = relativePath(from: documentURL?.deletingLastPathComponent(), to: imageURL) ?? imageURL.path
        let name = imageURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
        let needsBrackets = path.contains(where: { " ()<>".contains($0) })
        return "![\(name)](\(needsBrackets ? "<\(path)>" : path))"
    }

    static func relativePath(from folder: URL?, to file: URL) -> String? {
        guard let folder else { return nil }
        let base = folder.standardizedFileURL.pathComponents
        let target = file.standardizedFileURL.pathComponents
        // Different volumes share only "/": an absolute path is clearer then.
        guard base.count > 1, target.count > 1, base[1] == target[1] else { return nil }
        var common = 0
        while common < base.count, common < target.count, base[common] == target[common] { common += 1 }
        let ups = Array(repeating: "..", count: base.count - common)
        return (ups + target[common...]).joined(separator: "/")
    }
}
