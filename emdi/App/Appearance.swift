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

extension AppearanceChoice {
    /// The next choice when the title bar button is clicked: System → Light → Dark → System.
    var next: AppearanceChoice {
        switch self {
        case .system: .light
        case .light: .dark
        case .dark: .system
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

/// A small button at the right of each document window's title bar that cycles the appearance
/// (System, Light, Dark). It writes the same user default as Settings, so both stay in step.
@MainActor
final class AppearanceToggle: NSObject {
    static let shared = AppearanceToggle()
    private static let identifier = NSUserInterfaceItemIdentifier("emdi.appearanceToggle")

    private let buttons = NSHashTable<NSButton>.weakObjects()

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                               queue: .main) { _ in
            MainActor.assumeIsolated { AppearanceToggle.shared.refresh() }
        }
    }

    func install(in window: NSWindow) {
        guard !window.titlebarAccessoryViewControllers.contains(where: { $0.identifier == Self.identifier }) else { return }
        let button = NSButton(image: NSImage(), target: self, action: #selector(cycle))
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 36, height: 28))
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        let controller = NSTitlebarAccessoryViewController()
        controller.identifier = Self.identifier
        controller.view = container
        controller.layoutAttribute = .trailing
        window.addTitlebarAccessoryViewController(controller)

        buttons.add(button)
        update(button)
    }

    @objc private func cycle() {
        let choice = AppearanceChoice.current.next
        UserDefaults.standard.set(choice.rawValue, forKey: AppearanceChoice.defaultsKey)
        choice.apply()
        refresh()
    }

    private func refresh() {
        for button in buttons.allObjects { update(button) }
    }

    private func update(_ button: NSButton) {
        let choice = AppearanceChoice.current
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        button.image = NSImage(systemSymbolName: choice.symbol, accessibilityDescription: "Appearance: \(choice.title)")?
            .withSymbolConfiguration(configuration)
        button.toolTip = "Appearance: \(choice.title). Click for \(choice.next.title)."
    }
}
