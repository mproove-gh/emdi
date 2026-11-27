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

    /// The folder that holds a document's pasted images: next to it, named after it with an
    /// `_images` suffix (`notes.md` → `notes_images`).
    static func imagesFolder(for documentURL: URL) -> URL {
        let name = documentURL.deletingPathExtension().lastPathComponent
        return documentURL.deletingLastPathComponent().appending(path: name + "_images", directoryHint: .isDirectory)
    }

    /// True for a file another app keeps only for a while: anything in the user's Library (where
    /// screenshot tools such as CleanShot put their captures) or in a temporary folder. Such a
    /// file is copied next to the document instead of being referenced where it is.
    static func isTransient(_ file: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let path = file.standardizedFileURL.resolvingSymlinksInPath().path
        let library = home.standardizedFileURL.resolvingSymlinksInPath().appending(path: "Library").path
        let temporary = ["/tmp", "/private/tmp", "/var/folders", "/private/var/folders",
                         FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path]
        return ([library] + temporary).contains { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
    }

    /// Where a copy of `file` goes in `folder`: the same name, with `-2`, `-3`, … added when taken.
    static func copyURL(for file: URL, in folder: URL, exists: (URL) -> Bool) -> URL {
        let base = file.deletingPathExtension().lastPathComponent
        let ext = file.pathExtension
        func named(_ name: String) -> URL { folder.appending(path: ext.isEmpty ? name : "\(name).\(ext)") }
        var url = named(base)
        var index = 2
        while exists(url) {
            url = named("\(base)-\(index)")
            index += 1
        }
        return url
    }

    /// Where a pasted image is saved: `image-YYYYMMDD-HHMMSS.png` in `folder`, with `-2`, `-3`, …
    /// added when that name is taken.
    static func pastedImageURL(in folder: URL, date: Date, exists: (URL) -> Bool) -> URL {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let stamp = String(format: "%04d%02d%02d-%02d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0,
                           c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        var url = folder.appending(path: "image-\(stamp).png")
        var index = 2
        while exists(url) {
            url = folder.appending(path: "image-\(stamp)-\(index).png")
            index += 1
        }
        return url
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
