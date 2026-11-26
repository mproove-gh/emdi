import AppKit
import SwiftUI

/// The Format menu. Its items send `performFormatCommand(_:)` down the responder chain,
/// so they act on whichever editor window is key.
struct FormatCommands: Commands {
    var body: some Commands {
        CommandMenu("Format") {
            ForEach(FormatCommand.inlineGroup, id: \.self, content: button)
            Divider()
            Menu("Heading") {
                ForEach(FormatCommand.headingGroup, id: \.self, content: button)
            }
            ForEach(FormatCommand.blockGroup, id: \.self, content: button)
            Menu("Insert") {
                ForEach(FormatCommand.insertGroup, id: \.self, content: button)
            }
        }
    }

    @ViewBuilder
    private func button(_ command: FormatCommand) -> some View {
        let button = Button(command.title) {
            NSApp.sendAction(#selector(MarkdownTextView.performFormatCommand(_:)), to: nil,
                             from: FormatCommandSender(command))
        }
        if let shortcut = command.shortcut {
            button.keyboardShortcut(KeyEquivalent(shortcut.key), modifiers: shortcut.modifiers.eventModifiers)
        } else {
            button
        }
    }
}

extension ShortcutModifiers {
    var eventModifiers: EventModifiers {
        var modifiers: EventModifiers = []
        if contains(.command) { modifiers.insert(.command) }
        if contains(.option) { modifiers.insert(.option) }
        if contains(.shift) { modifiers.insert(.shift) }
        if contains(.control) { modifiers.insert(.control) }
        return modifiers
    }
}
