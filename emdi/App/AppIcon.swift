import AppKit
import SwiftUI

/// The app icon the user picked in Settings. White is the bundle's own icon (the asset catalog);
/// Anthracite is `AppIcon-Anthracite.icns` in the app's resources.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case white, anthracite

    static let defaultsKey = "appIcon"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .white: "White"
        case .anthracite: "Anthracite"
        }
    }

    @MainActor
    var image: NSImage? {
        switch self {
        case .white:
            NSImage(named: "AppIcon")
        case .anthracite:
            Bundle.main.url(forResource: "AppIcon-Anthracite", withExtension: "icns").flatMap(NSImage.init(contentsOf:))
        }
    }
}

@MainActor
enum AppIcon {
    static var current: AppIconChoice {
        UserDefaults.standard.string(forKey: AppIconChoice.defaultsKey).flatMap(AppIconChoice.init(rawValue:)) ?? .white
    }

    /// Shows the chosen icon in the Dock now, and sets it as the app bundle's custom Finder icon
    /// so the Dock and Finder show it while emdi is closed too. White removes the custom icon.
    /// Note: a custom icon adds an `Icon\r` file to the bundle, which a rebuild discards;
    /// emdi re-applies the choice at every launch.
    static func apply(_ choice: AppIconChoice) {
        let custom = choice == .white ? nil : choice.image
        NSApp.applicationIconImage = custom
        NSWorkspace.shared.setIcon(custom, forFile: Bundle.main.bundlePath, options: [])
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if AppIcon.current != .white { AppIcon.apply(AppIcon.current) }
    }
}
