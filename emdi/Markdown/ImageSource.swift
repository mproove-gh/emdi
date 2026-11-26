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
}
