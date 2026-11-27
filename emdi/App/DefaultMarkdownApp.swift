import AppKit
import UniformTypeIdentifiers

/// Making emdi the app that opens Markdown files from the Finder (Settings ▸ Editing), and
/// handing them back to the app that opened them before.
@MainActor
enum DefaultMarkdownApp {
    /// User default holding, per type identifier, the path of the app that opened that type
    /// before emdi was made the default.
    static let previousAppsKey = "previousMarkdownApps"

    /// The types the Finder may use for .md / .markdown files: the system's own type for the
    /// extension and emdi's imported Markdown type, when they differ.
    static var types: [UTType] {
        var types: [UTType] = []
        for type in [UTType(filenameExtension: "md"), UTType(filenameExtension: "markdown"),
                     UTType("net.daringfireball.markdown")].compactMap({ $0 }) where !types.contains(type) {
            types.append(type)
        }
        return types
    }

    private static var emdiURL: URL { Bundle.main.bundleURL.standardizedFileURL }

    /// True when every Markdown type opens with this copy of emdi.
    static var isEmdi: Bool {
        types.allSatisfy { NSWorkspace.shared.urlForApplication(toOpen: $0)?.standardizedFileURL == emdiURL }
    }

    /// Records the current handlers, then makes emdi the default. macOS may ask the user to
    /// confirm the change.
    static func makeEmdiDefault(defaults: UserDefaults = .standard) async throws {
        let current = Dictionary(uniqueKeysWithValues: types.map {
            ($0.identifier, NSWorkspace.shared.urlForApplication(toOpen: $0))
        })
        let stored = defaults.dictionary(forKey: previousAppsKey) as? [String: String] ?? [:]
        defaults.set(recording(current, over: stored, emdi: emdiURL), forKey: previousAppsKey)
        for type in types {
            try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type)
        }
    }

    /// The handlers to remember: each type's current app, unless it is emdi itself (any copy),
    /// in which case what was remembered before is kept.
    nonisolated static func recording(_ current: [String: URL?], over stored: [String: String],
                                      emdi: URL) -> [String: String] {
        var result = stored
        for (type, url) in current {
            guard let url = url?.standardizedFileURL, url != emdi.standardizedFileURL,
                  url.lastPathComponent != emdi.lastPathComponent else { continue }
            result[type] = url.path
        }
        return result
    }

    /// The app emdi replaced, if it is still installed.
    static func previousApp(defaults: UserDefaults = .standard) -> URL? {
        let stored = defaults.dictionary(forKey: previousAppsKey) as? [String: String] ?? [:]
        for type in types {
            if let path = stored[type.identifier], FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    /// Other installed apps that can open Markdown files, by name.
    static var otherApps: [URL] {
        guard let md = types.first else { return [] }
        var seen = Set<String>()
        return NSWorkspace.shared.urlsForApplications(toOpen: md)
            .filter { $0.standardizedFileURL != emdiURL && $0.lastPathComponent != emdiURL.lastPathComponent }
            .filter { seen.insert($0.lastPathComponent).inserted }
            .sorted { displayName(of: $0).localizedCaseInsensitiveCompare(displayName(of: $1)) == .orderedAscending }
    }

    static func displayName(of app: URL) -> String {
        FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
    }

    /// Gives every Markdown type to `app`: the remembered app for its type when `app` is nil.
    static func handBack(to app: URL? = nil, defaults: UserDefaults = .standard) async throws {
        let stored = defaults.dictionary(forKey: previousAppsKey) as? [String: String] ?? [:]
        guard let fallback = app ?? previousApp(defaults: defaults) else { return }
        for type in types {
            var target = fallback
            if app == nil, let path = stored[type.identifier], FileManager.default.fileExists(atPath: path) {
                target = URL(fileURLWithPath: path)
            }
            try await NSWorkspace.shared.setDefaultApplication(at: target, toOpen: type)
        }
        defaults.removeObject(forKey: previousAppsKey)
    }
}
