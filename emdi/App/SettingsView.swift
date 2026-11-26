import AppKit
import SwiftUI

/// emdi ▸ Settings… (⌘,). Every change applies at once to all open documents.
struct SettingsView: View {
    @AppStorage(FontSettings.textFamilyKey) private var textFamily = ""
    @AppStorage(FontSettings.textSizeKey) private var textSize = FontSettings.defaultTextSize
    @AppStorage(FontSettings.codeFamilyKey) private var codeFamily = ""
    @AppStorage(AppIconChoice.defaultsKey) private var iconChoice: AppIconChoice = .white

    private static let families = EditorFonts.allFamilies
    private static let monospacedFamilies = EditorFonts.monospacedFamilies

    var body: some View {
        Form {
            Section("Fonts") {
                Picker("Text", selection: $textFamily) {
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

                Picker("Code", selection: $codeFamily) {
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

                preview

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

            Section("App Icon") {
                HStack(spacing: 16) {
                    ForEach(AppIconChoice.allCases) { option in
                        iconButton(option)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: iconChoice) { _, newValue in
            AppIcon.apply(newValue)
        }
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

    private func iconButton(_ option: AppIconChoice) -> some View {
        Button {
            iconChoice = option
        } label: {
            VStack(spacing: 6) {
                if let image = option.image {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: 64, height: 64)
                }
                Text(option.title)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(iconChoice == option ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(iconChoice == option ? .isSelected : [])
    }
}
