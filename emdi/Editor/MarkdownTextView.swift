import AppKit
import UniformTypeIdentifiers

/// Carries a `FormatCommand` through the responder chain from the SwiftUI Format menu.
final class FormatCommandSender: NSObject {
    let command: FormatCommand

    init(_ command: FormatCommand) {
        self.command = command
    }
}

/// The editor's text view: adds the formatting commands and puts them at the top of the context menu.
final class MarkdownTextView: NSTextView {
    // MARK: Code block copy button

    /// Source ranges of the code blocks, set by the coordinator after each parse.
    var codeBlockRanges: [NSRange] = [] {
        didSet { hideCopyButton() }
    }

    private var hoveredCodeBlock: NSRange?
    private var hoverTrackingArea: NSTrackingArea?

    private lazy var copyButton: NSButton = {
        let button = NSButton(image: Self.copyImage, target: self, action: #selector(copyHoveredCodeBlock))
        button.bezelStyle = .accessoryBarAction
        button.isBordered = true
        button.toolTip = "Copy Code"
        button.setAccessibilityLabel("Copy Code")
        button.frame.size = NSSize(width: 26, height: 22)
        button.isHidden = true
        addSubview(button)
        return button
    }()

    private static let copyImage = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy Code")!
    private static let copiedImage = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")!

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        showCopyButton(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hideCopyButton()
    }

    /// Shows the button at the top right of the code block under `point`, if any.
    private func showCopyButton(at point: NSPoint) {
        guard let layoutManager = textLayoutManager, let content = layoutManager.textContentManager else { return }
        let origin = textContainerOrigin
        let containerPoint = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        guard let fragment = layoutManager.textLayoutFragment(for: containerPoint),
              fragment is CodeBlockLayoutFragment else {
            hideCopyButton()
            return
        }
        let offset = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        guard let block = codeBlockRanges.first(where: { offset >= $0.location && offset <= NSMaxRange($0) }) else {
            hideCopyButton()
            return
        }
        guard block != hoveredCodeBlock || copyButton.isHidden else { return }

        guard let start = content.location(content.documentRange.location, offsetBy: block.location),
              let first = layoutManager.textLayoutFragment(for: start) else { return }
        let lineTop = first.layoutFragmentFrame.minY + (first.textLineFragments.first?.typographicBounds.minY ?? 0)
        let panelTop = lineTop - CodeBlockLayoutFragment.verticalPadding
        let containerWidth = textContainer?.size.width ?? bounds.width
        let size = copyButton.frame.size
        copyButton.setFrameOrigin(NSPoint(x: origin.x + containerWidth - size.width - 6, y: origin.y + panelTop + 4))
        copyButton.image = Self.copyImage
        copyButton.isHidden = false
        hoveredCodeBlock = block
    }

    private func hideCopyButton() {
        hoveredCodeBlock = nil
        copyButton.isHidden = true
    }

    @objc private func copyHoveredCodeBlock() {
        guard let block = hoveredCodeBlock, NSMaxRange(block) <= (string as NSString).length else { return }
        let code = CodeBlockText.content(of: (string as NSString).substring(with: block))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)

        copyButton.image = Self.copiedImage
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            self?.copyButton.image = Self.copyImage
        }
    }

    // MARK: Task checkboxes

    /// Hidden `- [ ] ` prefixes of the task items, set by the coordinator after each parse.
    var taskPrefixRanges: [NSRange] = []

    override func mouseDown(with event: NSEvent) {
        if toggleTask(at: convert(event.locationInWindow, from: nil)) { return }
        super.mouseDown(with: event)
    }

    /// Toggles `[ ]` ↔ `[x]` when `point` is on a drawn checkbox. Returns whether it was.
    private func toggleTask(at point: NSPoint) -> Bool {
        guard let layoutManager = textLayoutManager, let content = layoutManager.textContentManager else { return false }
        let origin = textContainerOrigin
        let containerPoint = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        guard let fragment = layoutManager.textLayoutFragment(for: containerPoint) as? TaskLayoutFragment else {
            return false
        }
        let frame = fragment.layoutFragmentFrame
        let hitArea = fragment.checkboxRect.offsetBy(dx: frame.minX, dy: frame.minY).insetBy(dx: -4, dy: -4)
        guard hitArea.contains(containerPoint) else { return false }

        let paragraphStart = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        let prefix = NSRange(location: paragraphStart + fragment.prefixRange.location, length: fragment.prefixRange.length)
        let text = string as NSString
        guard NSMaxRange(prefix) <= text.length else { return false }
        let bracket = text.range(of: "[", range: prefix)
        guard bracket.location != NSNotFound, bracket.location + 1 < NSMaxRange(prefix) else { return false }
        let mark = NSRange(location: bracket.location + 1, length: 1)
        let isChecked = text.substring(with: mark) != " "
        apply(TextEdit(range: mark, replacement: isChecked ? " " : "x", selection: selectedRange()),
              actionName: isChecked ? "Uncheck Task" : "Check Task")
        return true
    }

    /// Backspace right after a hidden task prefix removes the whole prefix, like deleting the checkbox.
    override func deleteBackward(_ sender: Any?) {
        let selection = selectedRange()
        if selection.length == 0, let prefix = taskPrefixRanges.first(where: { NSMaxRange($0) == selection.location }) {
            apply(TextEdit(range: prefix, replacement: "", selection: NSRange(location: prefix.location, length: 0)),
                  actionName: "Delete Checkbox")
            return
        }
        super.deleteBackward(sender)
    }

    // MARK: Dropping images

    /// The document's file, set by the coordinator, so dropped images get a relative path.
    var documentURL: URL?

    private static let imageReadingOptions: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true,
        .urlReadingContentsConformToTypes: [UTType.image.identifier],
    ]

    private func droppedImageURLs(_ info: any NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: Self.imageReadingOptions) as? [URL] ?? []
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        droppedImageURLs(sender).isEmpty ? super.draggingEntered(sender) : .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let operation = super.draggingUpdated(sender)  // keeps the drop caret moving with the pointer
        return droppedImageURLs(sender).isEmpty ? operation : .copy
    }

    /// Image files become `![name](path)` paragraphs at the drop point; anything else is handled normally.
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let images = droppedImageURLs(sender)
        guard !images.isEmpty, isEditable else { return super.performDragOperation(sender) }
        let markdown = images.map { ImageSource.markdown(forImageAt: $0, relativeTo: documentURL) }
            .joined(separator: "\n\n") + "\n"
        let location = characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil))
        let end = (markdown as NSString).length - 1
        let edit = MarkdownFormatter.insertBlock(markdown, select: NSRange(location: end, length: 0),
                                                 in: string as NSString, selection: NSRange(location: location, length: 0))
        window?.makeFirstResponder(self)
        apply(edit, actionName: images.count == 1 ? "Insert Image" : "Insert Images")
        return true
    }

    // MARK: List editing

    override func insertNewline(_ sender: Any?) {
        if let edit = listEdit(ListEditing.newline) {
            apply(edit, actionName: "Typing")
        } else {
            super.insertNewline(sender)
        }
    }

    override func insertTab(_ sender: Any?) {
        if let edit = listEdit(ListEditing.indent) {
            apply(edit, actionName: "Indent")
        } else {
            super.insertTab(sender)
        }
    }

    override func insertBacktab(_ sender: Any?) {
        if let edit = listEdit(ListEditing.outdent) {
            apply(edit, actionName: "Outdent")
        } else {
            super.insertBacktab(sender)
        }
    }

    /// The list edit for the current selection, unless an input method is composing or the caret is in code.
    private func listEdit(_ make: (NSString, NSRange) -> TextEdit?) -> TextEdit? {
        let selection = selectedRange()
        guard !hasMarkedText(), isEditable,
              // `<=` so a caret at the very end of a block (an unclosed fence at the end of the file) counts.
              !codeBlockRanges.contains(where: { selection.location > $0.location && selection.location <= NSMaxRange($0) })
        else { return nil }
        return make(string as NSString, selection)
    }

    // MARK: Formatting commands

    @objc func performFormatCommand(_ sender: Any?) {
        let command: FormatCommand? = switch sender {
        case let item as NSMenuItem: (item.representedObject as? String).flatMap(FormatCommand.init(rawValue:))
        case let sender as FormatCommandSender: sender.command
        default: nil
        }
        guard let command, isEditable else { return }
        apply(command.edit(in: string, selection: selectedRange()), actionName: command.title)
    }

    /// Goes through `shouldChangeText`/`didChangeText` so the edit is undoable and the delegate restyles.
    private func apply(_ edit: TextEdit, actionName: String) {
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        setSelectedRange(edit.selection)
        scrollRangeToVisible(edit.selection)
        undoManager?.setActionName(actionName)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        var formatItems = FormatCommand.inlineGroup.map(menuItem)
        formatItems.append(.separator())
        formatItems.append(submenuItem("Heading", FormatCommand.headingGroup))
        formatItems += FormatCommand.blockGroup.map(menuItem)
        formatItems.append(submenuItem("Insert", FormatCommand.insertGroup))
        formatItems.append(.separator())
        for (index, item) in formatItems.enumerated() {
            menu.insertItem(item, at: index)
        }
        return menu
    }

    private func submenuItem(_ title: String, _ commands: [FormatCommand]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        commands.map(menuItem).forEach(submenu.addItem)
        item.submenu = submenu
        return item
    }

    private func menuItem(_ command: FormatCommand) -> NSMenuItem {
        let item = NSMenuItem(title: command.title, action: #selector(performFormatCommand(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = command.rawValue
        if let shortcut = command.shortcut {
            // Shown for reference; the shortcuts themselves are handled by the Format menu.
            item.keyEquivalent = String(shortcut.key)
            item.keyEquivalentModifierMask = shortcut.modifiers.eventFlags
        }
        return item
    }
}

extension ShortcutModifiers {
    var eventFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.command) { flags.insert(.command) }
        if contains(.option) { flags.insert(.option) }
        if contains(.shift) { flags.insert(.shift) }
        if contains(.control) { flags.insert(.control) }
        return flags
    }
}
