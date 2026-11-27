import AppKit
import SwiftUI

/// The sections of emdi ▸ Settings… (⌘,), listed in the sidebar.
enum SettingsPane: String, CaseIterable, Identifiable {
    case appearance, fonts, editing, appIcon

    /// The pane itself: `List(selection:)` tags each row with its `id`, which must have the selection's type.
    var id: Self { self }

    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .fonts: "Fonts"
        case .editing: "Editing"
        case .appIcon: "App Icon"
        }
    }

    var symbol: String {
        switch self {
        case .appearance: "circle.lefthalf.filled"
        case .fonts: "textformat"
        case .editing: "square.and.pencil"
        case .appIcon: "app.badge"
        }
    }

    var tint: Color {
        switch self {
        case .appearance: .blue
        case .fonts: .indigo
        case .editing: .green
        case .appIcon: .orange
        }
    }
}

/// emdi ▸ Settings… (⌘,): a sidebar of sections on the left, the selected section's settings on the right,
/// like System Settings. Every change applies at once to all open documents.
struct SettingsView: View {
    @State private var selection: SettingsPane?

    init(initialPane: SettingsPane = .appearance) {
        _selection = State(initialValue: initialPane)
    }

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: $selection)
                .navigationSplitViewColumnWidth(190)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch selection ?? .appearance {
                case .appearance: AppearancePane()
                case .fonts: FontsPane()
                case .editing: EditingPane()
                case .appIcon: AppIconPane()
                }
            }
            .navigationTitle((selection ?? .appearance).title)
        }
        .frame(width: 700, height: 460)
        // The same paper as the editor, in light and dark.
        .containerBackground(Color(nsColor: EditorPalette.background), for: .window)
    }
}

extension Color {
    /// The frame around the selected option: the emdi orange of the text cursor and the logo.
    static let emdiSelection = Color(nsColor: EditorPalette.cursor)
}

extension View {
    /// The editor's paper behind a settings pane or the sidebar, instead of the system's own background.
    func settingsBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Color(nsColor: EditorPalette.background))
    }
}

/// The list of sections, each with a colored symbol tile as in System Settings.
struct SettingsSidebar: View {
    @Binding var selection: SettingsPane?

    var body: some View {
        List(SettingsPane.allCases, selection: $selection) { pane in
            Label {
                Text(pane.title)
            } icon: {
                Image(systemName: pane.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6).fill(pane.tint.gradient))
            }
            .padding(.vertical, 2)
        }
        .settingsBackground()
    }
}

// MARK: - Appearance

private struct AppearancePane: View {
    @AppStorage(AppearanceChoice.defaultsKey) private var appearance: AppearanceChoice = .system

    var body: some View {
        Form {
            Section {
                HStack(spacing: 20) {
                    ForEach(AppearanceChoice.allCases) { choice in
                        Button {
                            appearance = choice
                        } label: {
                            VStack(spacing: 8) {
                                ThemeThumbnail(choice: choice)
                                    .overlay(RoundedRectangle(cornerRadius: 9)
                                        .strokeBorder(appearance == choice ? Color.emdiSelection : .clear, lineWidth: 3)
                                        .padding(-4))
                                Text(choice.title)
                                    .foregroundStyle(appearance == choice ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(choice.title) theme")
                        .accessibilityAddTraits(appearance == choice ? .isSelected : [])
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                // Rebuilt on each choice: the Form row otherwise kept showing the frame on a previous choice.
                .id(appearance)
            } header: {
                Text("Theme")
            } footer: {
                Text("System follows the macOS appearance and switches automatically between light and dark.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .settingsBackground()
        .onChange(of: appearance) { _, newValue in
            newValue.apply()
        }
    }
}

/// A miniature emdi document drawn with the theme's own colors. System shows light and dark side by side.
private struct ThemeThumbnail: View {
    let choice: AppearanceChoice

    var body: some View {
        Group {
            switch choice {
            case .light: page(dark: false)
            case .dark: page(dark: true)
            case .system:
                page(dark: false)
                    .overlay(page(dark: true).mask(HStack(spacing: 0) { Color.clear; Color.black }))
            }
        }
        .frame(width: 136, height: 88)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
    }

    private func page(dark: Bool) -> some View {
        func color(_ color: NSColor) -> Color { Color(nsColor: EditorPalette.resolve(color, dark: dark)) }
        return ZStack(alignment: .topLeading) {
            color(EditorPalette.background)
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(color(EditorPalette.text)).frame(width: 58, height: 6)
                Capsule().fill(color(EditorPalette.secondaryText)).frame(width: 96, height: 3)
                Capsule().fill(color(EditorPalette.secondaryText)).frame(width: 80, height: 3)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Capsule().fill(color(EditorPalette.codeKeyword)).frame(width: 14, height: 3)
                        Capsule().fill(color(EditorPalette.codeString)).frame(width: 30, height: 3)
                    }
                    Capsule().fill(color(EditorPalette.codeType)).frame(width: 36, height: 3)
                }
                .padding(6)
                .frame(width: 108, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 3).fill(color(EditorPalette.codeBlockBackground)))
                HStack(spacing: 2) {
                    Capsule().fill(color(EditorPalette.secondaryText)).frame(width: 44, height: 3)
                    Rectangle().fill(color(EditorPalette.cursor)).frame(width: 1.5, height: 8)
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Fonts

private struct FontsPane: View {
    @AppStorage(FontSettings.textFamilyKey) private var textFamily = ""
    @AppStorage(FontSettings.textSizeKey) private var textSize = FontSettings.defaultTextSize
    @AppStorage(FontSettings.codeFamilyKey) private var codeFamily = ""

    private static let families = EditorFonts.allFamilies
    private static let monospacedFamilies = EditorFonts.monospacedFamilies

    var body: some View {
        Form {
            Section("Text") {
                Picker("Font", selection: $textFamily) {
                    Text("System (SF Pro)").tag("")
                    Divider()
                    ForEach(Self.families, id: \.self) { Text($0).tag($0) }
                }
                LabeledContent("Size") {
                    HStack(spacing: 6) {
                        Text("\(Int(textSize)) pt").monospacedDigit()
                        Stepper("Size", value: $textSize, in: FontSettings.textSizes, step: 1).labelsHidden()
                    }
                }
            }

            Section {
                Picker("Font", selection: $codeFamily) {
                    Text("System Monospaced (SF Mono)").tag("")
                    Section("Monospaced") {
                        ForEach(Self.monospacedFamilies, id: \.self) { Text($0).tag($0) }
                    }
                    Section("Other fonts") {
                        ForEach(Self.families.filter { !Self.monospacedFamilies.contains($0) }, id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                }
            } header: {
                Text("Code")
            } footer: {
                Text("Used for inline code and code blocks, one point smaller than the text.")
                    .foregroundStyle(.secondary)
            }

            Section("Preview") {
                preview
            }

            HStack {
                Spacer()
                Button("Restore Defaults") {
                    textFamily = ""
                    textSize = FontSettings.defaultTextSize
                    codeFamily = ""
                }
                .disabled(textFamily.isEmpty && textSize == FontSettings.defaultTextSize && codeFamily.isEmpty)
            }
        }
        .formStyle(.grouped)
        .settingsBackground()
    }

    /// A few lines set in the chosen fonts.
    private var preview: some View {
        let fonts = EditorFonts(FontSettings(textFamily: textFamily, textSize: textSize, codeFamily: codeFamily))
        return VStack(alignment: .leading, spacing: 6) {
            Text("Heading").font(Font(fonts.heading(level: 2) as CTFont))
            Text("The quick brown fox jumps over the lazy dog.").font(Font(fonts.body as CTFont))
            Text("let greeting = \"Hello, emdi\"")
                .font(Font(fonts.code as CTFont))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Font preview")
    }
}

// MARK: - Editing

private struct EditingPane: View {
    @AppStorage(DocumentSaving.autosaveKey) private var autosave = false

    var body: some View {
        Form {
            Section {
                Toggle("Save automatically while typing", isOn: $autosave)
            } header: {
                Text("Saving")
            } footer: {
                Text(autosave
                     ? "Each change is written to the file about a second after you stop typing, and closing a document saves it without asking. Untitled documents are saved once you give them a name."
                     : "Changes are saved when you choose File ▸ Save (⌘S). Closing a document with unsaved changes asks whether to save them.")
                    .foregroundStyle(.secondary)
            }

            DefaultAppSection()
        }
        .formStyle(.grouped)
        .settingsBackground()
    }
}

/// Whether the Finder opens Markdown files with emdi, and a button to make it so.
private struct DefaultAppSection: View {
    @State private var isDefault = DefaultMarkdownApp.isEmdi
    @State private var failure: String?

    var body: some View {
        Section {
            LabeledContent("Open Markdown files with emdi") {
                if isDefault {
                    Label("Default", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Make Default") {
                        Task {
                            do {
                                try await DefaultMarkdownApp.makeEmdiDefault()
                                failure = nil
                            } catch {
                                failure = error.localizedDescription
                            }
                            isDefault = DefaultMarkdownApp.isEmdi
                        }
                    }
                }
            }
        } header: {
            Text("Markdown Files")
        } footer: {
            Text(failure ?? "Double-clicking a .md file in the Finder then opens it in emdi. This copy of emdi is the one registered: if you move the app, make it the default again.")
                .foregroundStyle(failure == nil ? .secondary : Color.red)
        }
        .onAppear { isDefault = DefaultMarkdownApp.isEmdi }
    }
}

// MARK: - App icon

private struct AppIconPane: View {
    @AppStorage(AppIconChoice.defaultsKey) private var iconChoice: AppIconChoice = .white

    var body: some View {
        Form {
            Section {
                HStack(spacing: 24) {
                    ForEach(AppIconChoice.allCases) { option in
                        Button {
                            iconChoice = option
                        } label: {
                            VStack(spacing: 8) {
                                if let image = option.image {
                                    Image(nsImage: image)
                                        .resizable()
                                        .frame(width: 88, height: 88)
                                }
                                Text(option.title)
                                    .foregroundStyle(iconChoice == option ? .primary : .secondary)
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(iconChoice == option ? Color.emdiSelection : .clear, lineWidth: 3))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(iconChoice == option ? .isSelected : [])
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .id(iconChoice)  // See AppearancePane.
            } header: {
                Text("Icon")
            } footer: {
                Text("Changes the icon in the Dock and the Finder.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .settingsBackground()
        .onChange(of: iconChoice) { _, newValue in
            AppIcon.apply(newValue)
        }
    }
}
