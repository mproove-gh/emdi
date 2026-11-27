import AppKit

/// The fonts chosen in Settings, stored in user defaults. An empty family means the system font
/// (SF Pro for text, SF Mono for code).
struct FontSettings: Equatable, Sendable {
    static let textFamilyKey = "textFontFamily"
    static let textSizeKey = "textFontSize"
    static let codeFamilyKey = "codeFontFamily"

    static let defaultTextSize: Double = 15
    static let textSizes: ClosedRange<Double> = 11...28

    var textFamily = ""
    var textSize = defaultTextSize
    var codeFamily = ""

    static func current(_ defaults: UserDefaults = .standard) -> FontSettings {
        let size = defaults.object(forKey: textSizeKey) as? Double ?? defaultTextSize
        return FontSettings(textFamily: defaults.string(forKey: textFamilyKey) ?? "",
                            textSize: min(max(size, textSizes.lowerBound), textSizes.upperBound),
                            codeFamily: defaults.string(forKey: codeFamilyKey) ?? "")
    }
}

/// The actual fonts the editor uses, built from `FontSettings`. A family that is no longer
/// installed falls back to the system font.
struct EditorFonts {
    let settings: FontSettings
    let body: NSFont
    /// Code is one point smaller than the text, which balances the wider monospaced glyphs.
    let code: NSFont

    init(_ settings: FontSettings = .current()) {
        self.settings = settings
        let size = CGFloat(settings.textSize)
        body = Self.font(family: settings.textFamily, size: size, weight: 5) ?? .systemFont(ofSize: size)
        code = Self.font(family: settings.codeFamily, size: size - 1, weight: 5)
            ?? .monospacedSystemFont(ofSize: size - 1, weight: .regular)
    }

    var size: CGFloat { CGFloat(settings.textSize) }

    /// Headings scale with the text size (32 / 25 / 21 / 18 / 15 / 14 pt at the default 15 pt).
    func heading(level: Int) -> NSFont {
        let ratios: [CGFloat] = [32, 25, 21, 18, 15, 14].map { $0 / 15 }
        let size = (self.size * ratios[min(max(level, 1), 6) - 1]).rounded()
        let bold = level <= 2
        if let font = Self.font(family: settings.textFamily, size: size, weight: bold ? 9 : 8) {
            return font
        }
        return .systemFont(ofSize: size, weight: bold ? .bold : .semibold)
    }

    /// A font of `family` (nil for the system font or a missing family). `weight` uses
    /// NSFontManager's 0–15 scale: 5 is regular, 8 semibold, 9 bold.
    static func font(family: String, size: CGFloat, weight: Int) -> NSFont? {
        guard !family.isEmpty else { return nil }
        if let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: weight, size: size) {
            return font
        }
        // Some families have no font at the exact weight: take the regular one and ask for bold.
        guard let regular = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size) else {
            return nil
        }
        return weight >= 8 ? NSFontManager.shared.convert(regular, toHaveTrait: .boldFontMask) : regular
    }

    /// Installed families, sorted, for the Settings pickers.
    static var allFamilies: [String] {
        NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Families with at least one fixed-pitch font: the natural choices for code.
    static var monospacedFamilies: [String] {
        let names = NSFontManager.shared.availableFontNames(with: .fixedPitchFontMask) ?? []
        let families = Set(names.compactMap { NSFont(name: $0, size: 12)?.familyName })
        return allFamilies.filter { families.contains($0) }
    }
}
