import AppKit

/// The appearance chosen in Settings: follow macOS, or always light or always dark.
enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark

    static let defaultsKey = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    static var current: AppearanceChoice {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(AppearanceChoice.init(rawValue:)) ?? .system
    }

    /// Applies to every emdi window, Settings included. The editor colors (`EditorPalette`) are dynamic,
    /// so documents switch at once without restyling.
    @MainActor
    func apply() {
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
