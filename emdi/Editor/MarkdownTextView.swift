import AppKit
import QuickLookUI
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

    private lazy var copyButton: CopyCodeButton = {
        let button = CopyCodeButton(frame: .zero)
        button.target = self
        button.action = #selector(copyHoveredCodeBlock)
        button.toolTip = "Copy Code"
        button.setAccessibilityLabel("Copy Code")
        button.isHidden = true
        addSubview(button)
        return button
    }()

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
        let point = convert(event.locationInWindow, from: nil)
        showCopyButton(at: point)
        if isOverControl(point) { NSCursor.arrow.set() }
    }

    override func cursorUpdate(with event: NSEvent) {
        if isOverControl(convert(event.locationInWindow, from: nil)) {
            NSCursor.arrow.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    /// Checkboxes and the copy button are clicked, not typed in: they get the arrow, not the I-beam.
    func isOverControl(_ point: NSPoint) -> Bool {
        (!copyButton.isHidden && copyButton.frame.contains(point)) || checkbox(at: point) != nil
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
        let containerWidth = textContainer?.size.width ?? bounds.width
        let fonts = EditorFonts()
        let label = MarkdownTheme.copyLabel(fonts: fonts, copied: false)
        if let header = first as? CodeBlockLayoutFragment, header.edges.contains(.header), let line = header.textLineFragments.first {
            // Over the header's drawn Copy label, in the text color.
            let midY = origin.y + header.layoutFragmentFrame.minY + line.typographicBounds.midY
            let rect = CodeBlockLayoutFragment.copyRect(for: label, panelMaxX: origin.x + containerWidth, midY: midY)
            copyButton.frame = rect.insetBy(dx: -5, dy: -3)
        } else {
            // An indented block has no header: the button goes in its top right corner.
            let lineTop = first.layoutFragmentFrame.minY + (first.textLineFragments.first?.typographicBounds.minY ?? 0)
            let rect = CodeBlockLayoutFragment.copyRect(for: label, panelMaxX: origin.x + containerWidth, midY: origin.y + lineTop + 6)
            copyButton.frame = rect.insetBy(dx: -5, dy: -3)
        }
        copyButton.fonts = fonts
        copyButton.copied = false
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

        copyButton.copied = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            self?.copyButton.copied = false
        }
    }

    // MARK: Task checkboxes

    /// Hidden `- [ ] ` prefixes of the task items, set by the coordinator after each parse.
    var taskPrefixRanges: [NSRange] = []
    /// Hidden `> ` prefixes of the quote lines, set by the coordinator after each parse.
    var quotePrefixRanges: [NSRange] = []

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if toggleTask(at: point) { return }
        if event.clickCount == 2, let url = imageURL(at: point) {
            showQuickLook(for: url)
            return
        }
        let plainClick = event.clickCount == 1 && event.modifierFlags.intersection([.shift, .command, .option]).isEmpty
        let cell = plainClick ? tableCell(at: point) : nil
        super.mouseDown(with: event)  // Tracks the mouse until it is released.
        let text = string as NSString
        if let cell, selectedRange().length == 0, NSMaxRange(cell) <= text.length {
            let caret = TableEditing.caret(forClickIn: cell, of: text, at: selectedRange().location)
            if caret != selectedRange().location { setSelectedRange(NSRange(location: caret, length: 0)) }
        }
    }

    /// The table cell drawn under `point`, found from the drawn borders rather than the character
    /// under the pointer: the wide padding of a cell is the kern of its hidden pipes.
    private func tableCell(at point: NSPoint) -> NSRange? {
        guard let layoutManager = textLayoutManager, let content = layoutManager.textContentManager else { return nil }
        let origin = textContainerOrigin
        let containerPoint = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        guard let fragment = layoutManager.textLayoutFragment(for: containerPoint) as? TableRowLayoutFragment,
              let border = fragment.cellBorders.last(where: { $0.x <= containerPoint.x - fragment.layoutFragmentFrame.minX })
        else { return nil }
        let paragraphStart = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        let cellStart = paragraphStart + border.pipeIndex + 1
        return tableCells.first { $0.range.location == cellStart }?.range
    }

    /// The task item whose drawn checkbox is under `point`.
    private func checkbox(at point: NSPoint) -> TaskLayoutFragment? {
        guard let layoutManager = textLayoutManager else { return nil }
        let origin = textContainerOrigin
        let containerPoint = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        guard let fragment = layoutManager.textLayoutFragment(for: containerPoint) as? TaskLayoutFragment else {
            return nil
        }
        let frame = fragment.layoutFragmentFrame
        let hitArea = fragment.checkboxRect.offsetBy(dx: frame.minX, dy: frame.minY).insetBy(dx: -4, dy: -4)
        return hitArea.contains(containerPoint) ? fragment : nil
    }

    /// Toggles `[ ]` ↔ `[x]` when `point` is on a drawn checkbox. Returns whether it was.
    private func toggleTask(at point: NSPoint) -> Bool {
        guard let content = textLayoutManager?.textContentManager, let fragment = checkbox(at: point) else { return false }
        let paragraphStart = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        let prefix = NSRange(location: paragraphStart + fragment.prefixRange.location, length: fragment.prefixRange.length)
        let text = string as NSString
        guard NSMaxRange(prefix) <= text.length else { return false }
        let bracket = text.range(of: "[", range: prefix)
        guard bracket.location != NSNotFound, bracket.location + 1 < NSMaxRange(prefix) else { return false }
        let mark = NSRange(location: bracket.location + 1, length: 1)
        let isChecked = text.substring(with: mark) != " "
        // The caret stays where it was, possibly far away: don't scroll back to it.
        apply(TextEdit(range: mark, replacement: isChecked ? " " : "x", selection: selectedRange()),
              actionName: isChecked ? "Uncheck Task" : "Check Task", scrollsToSelection: false)
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
        // Right after a hidden quote prefix, Backspace removes one quote level (the last `>` and its space).
        if selection.length == 0, let prefix = quotePrefixRanges.first(where: { NSMaxRange($0) == selection.location }) {
            let text = string as NSString
            let last = text.range(of: ">", options: .backwards, range: prefix)
            if last.location != NSNotFound {
                let removed = NSRange(location: last.location, length: NSMaxRange(prefix) - last.location)
                apply(TextEdit(range: removed, replacement: "", selection: NSRange(location: last.location, length: 0)),
                      actionName: "Remove Quote Level")
                return
            }
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
        let location = characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil))
        window?.makeFirstResponder(self)
        insertImages(images, at: location, actionName: images.count == 1 ? "Insert Image" : "Insert Images")
        return true
    }

    /// One `![name](path)` paragraph per image file, at `location`, as one undoable edit.
    private func insertImages(_ images: [URL], at location: Int, actionName: String) {
        let markdown = images.map { ImageSource.markdown(forImageAt: $0, relativeTo: documentURL) }
            .joined(separator: "\n\n") + "\n"
        let end = (markdown as NSString).length - 1
        let edit = MarkdownFormatter.insertBlock(markdown, select: NSRange(location: end, length: 0),
                                                 in: string as NSString, selection: NSRange(location: location, length: 0))
        apply(edit, actionName: actionName)
    }

    // MARK: Pasting images

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        super.readablePasteboardTypes + [.png, .tiff]
    }

    override func paste(_ sender: Any?) {
        if isEditable, pasteImage(from: .general) { return }
        super.paste(sender)
    }

    /// Image files copied in the Finder are referenced where they are, like dropped ones. Image data
    /// (a screenshot, an image copied in a browser) is saved as a PNG in an `images` folder next to the
    /// document, then referenced. Returns false when the pasteboard holds no image, or holds text.
    func pasteImage(from pasteboard: NSPasteboard) -> Bool {
        let files = pasteboard.readObjects(forClasses: [NSURL.self], options: Self.imageReadingOptions) as? [URL] ?? []
        if !files.isEmpty {
            insertImages(files, at: selectedRange().location, actionName: "Paste Image")
            return true
        }
        guard pasteboard.string(forType: .string) == nil, let data = Self.pngData(from: pasteboard) else { return false }
        guard let documentURL else {
            let alert = NSAlert()
            alert.messageText = "Save the document first"
            alert.informativeText = "emdi saves pasted images in an “images” folder next to the document, so the document needs a place on disk."
            if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
            return true
        }
        let folder = documentURL.deletingLastPathComponent().appending(path: "images")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = ImageSource.pastedImageURL(in: folder, date: Date()) { FileManager.default.fileExists(atPath: $0.path) }
            try data.write(to: url, options: .withoutOverwriting)
            insertImages([url], at: selectedRange().location, actionName: "Paste Image")
        } catch {
            let alert = NSAlert(error: error)
            if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
        }
        return true
    }

    private static func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff), let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    // MARK: Quick Look

    /// The image Quick Look shows, set by a double-click on it.
    private var previewURL: URL?

    /// The file of the loaded image drawn under `point`, if any.
    func imageURL(at point: NSPoint) -> URL? {
        guard let layoutManager = textLayoutManager else { return nil }
        let origin = textContainerOrigin
        guard let fragment = layoutManager.textLayoutFragment(for: CGPoint(x: point.x - origin.x, y: point.y - origin.y))
                as? ImageLayoutFragment,
              let image = fragment.blockImage, image.image != nil, let url = image.url,
              let rect = fragment.imageRect else { return nil }
        let frame = fragment.layoutFragmentFrame
        return rect.offsetBy(dx: frame.minX + origin.x, dy: frame.minY + origin.y).contains(point) ? url : nil
    }

    private func showQuickLook(for url: URL) {
        previewURL = url
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible { panel.reloadData() } else { panel.makeKeyAndOrderFront(nil) }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { previewURL != nil }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        previewURL = nil
    }

    // MARK: List editing

    override func insertNewline(_ sender: Any?) {
        if !hasMarkedText(), isEditable,
           let edit = TableEditing.newline(in: string as NSString, cells: tableCells, selection: selectedRange()) {
            if edit.replacement.isEmpty && edit.range.length == 0 {
                setSelectedRange(edit.selection)
                scrollRangeToVisible(edit.selection)
            } else {
                apply(edit, actionName: "Add Row")
            }
            return
        }
        if let edit = listEdit(ListEditing.newline) {
            apply(edit, actionName: "Typing")
        } else {
            super.insertNewline(sender)
        }
    }

    /// Table cells (`.tableCell` spans), set by the coordinator after each parse, for Tab navigation.
    var tableCells: [StyleSpan] = []

    /// Tab / Shift-Tab in a table: move between cells (or add a row), never insert a tab character.
    private func moveInTable(backwards: Bool) -> Bool {
        guard !hasMarkedText(), isEditable,
              let edit = TableEditing.tab(in: string as NSString, cells: tableCells, selection: selectedRange(),
                                          backwards: backwards) else { return false }
        if edit.replacement.isEmpty && edit.range.length == 0 {
            setSelectedRange(edit.selection)
            scrollRangeToVisible(edit.selection)
        } else {
            apply(edit, actionName: "Add Row")
        }
        return true
    }

    override func insertTab(_ sender: Any?) {
        if moveInTable(backwards: false) { return }
        if let edit = listEdit(ListEditing.indent) {
            apply(edit, actionName: "Indent")
        } else {
            super.insertTab(sender)
        }
    }

    override func insertBacktab(_ sender: Any?) {
        if moveInTable(backwards: true) { return }
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
    /// Numbered lists around the edit are then renumbered.
    private func apply(_ edit: TextEdit, actionName: String, scrollsToSelection: Bool = true) {
        isApplyingOwnEdit = true
        defer { isApplyingOwnEdit = false }
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        setSelectedRange(edit.selection)
        if scrollsToSelection { scrollRangeToVisible(edit.selection) }
        undoManager?.setActionName(actionName)
        renumberLists(touching: NSRange(location: edit.range.location, length: (edit.replacement as NSString).length))
    }

    // MARK: Renumbering

    /// Set when a change adds or removes a line break, which can add, remove or merge list items.
    private var pendingRenumber: NSRange?
    private var isRenumbering = false

    /// True while emdi applies its own edits (commands, list and table keys), which may restructure tables.
    private var isApplyingOwnEdit = false

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        // Typing, deleting, cutting or pasting must not break a table: keep its `|` and row breaks.
        if !isApplyingOwnEdit, !isRenumbering, !hasMarkedText(), let replacementString,
           undoManager?.isUndoing != true, undoManager?.isRedoing != true,
           let edit = TableEditing.protectingStructure(in: string as NSString, tables: Array(Set(tableCells.map(\.blockRange))),
                                                       range: affectedCharRange, replacement: replacementString) {
            if edit.range.length == 0 && edit.replacement.isEmpty {
                setSelectedRange(edit.selection)
            } else {
                apply(edit, actionName: "Typing")
            }
            return false
        }
        guard super.shouldChangeText(in: affectedCharRange, replacementString: replacementString) else { return false }
        let text = string as NSString
        let removesLineBreak = NSMaxRange(affectedCharRange) <= text.length
            && text.substring(with: affectedCharRange).contains("\n")
        if !isRenumbering, removesLineBreak || replacementString?.contains("\n") == true {
            pendingRenumber = NSRange(location: affectedCharRange.location,
                                      length: ((replacementString ?? "") as NSString).length)
        }
        return true
    }

    override func didChangeText() {
        super.didChangeText()
        if let range = pendingRenumber {
            pendingRenumber = nil
            renumberLists(touching: range)
        }
    }

    /// Keeps numbered lists counting 1, 2, 3… after items are added, removed or moved.
    /// Skipped while undoing or redoing, so undo restores exactly what was there.
    private func renumberLists(touching range: NSRange) {
        guard !isRenumbering, !hasMarkedText(), undoManager?.isUndoing != true, undoManager?.isRedoing != true,
              let edit = ListEditing.renumber(in: string, touching: range, selection: selectedRange()) else { return }
        isRenumbering = true
        defer { isRenumbering = false }
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        setSelectedRange(edit.selection)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        var formatItems = FormatCommand.inlineGroup.map(menuItem)
        formatItems.append(.separator())
        formatItems.append(submenuItem("Heading", FormatCommand.headingGroup))
        formatItems += FormatCommand.blockGroup.map(menuItem)
        formatItems.append(submenuItem("Insert", FormatCommand.insertGroup))
        if TableStructure.position(in: string, selection: selectedRange()) != nil {
            formatItems.append(tableSubmenuItem())
        }
        formatItems.append(.separator())
        for (index, item) in formatItems.enumerated() {
            menu.insertItem(item, at: index)
        }
        return menu
    }

    /// Row and column commands, shown only when the caret is in a table.
    private func tableSubmenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Table", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Table")
        for (index, section) in FormatCommand.tableSections.enumerated() {
            if index > 0 { submenu.addItem(.separator()) }
            section.map(menuItem).forEach(submenu.addItem)
        }
        item.submenu = submenu
        return item
    }

    /// Greys out commands that can't apply here, like deleting the only column of a table.
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(performFormatCommand(_:)) {
            let command = (menuItem.representedObject as? String).flatMap(FormatCommand.init(rawValue:))
            return isEditable && (command?.isAvailable(in: string, selection: selectedRange()) ?? true)
        }
        return super.validateMenuItem(menuItem)
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

/// The Copy button of the hovered code block. It draws exactly like the header's own Copy label,
/// over it, in the text color instead of the quieter one, and says "Copied" for a moment after a click.
final class CopyCodeButton: NSButton {
    var fonts = EditorFonts() { didSet { needsDisplay = true } }
    var copied = false {
        didSet {
            // "Copied" is wider than "Copy": grow to the left, keeping the right edge.
            let label = MarkdownTheme.copyLabel(fonts: fonts, copied: copied).size()
            let width = label.height + 4 + label.width + 10
            frame = NSRect(x: frame.maxX - width, y: frame.minY, width: width, height: frame.height)
            needsDisplay = true
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        title = ""
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        EditorPalette.codeBlockBackground.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        let label = NSMutableAttributedString(attributedString: MarkdownTheme.copyLabel(fonts: fonts, copied: copied))
        label.addAttribute(.foregroundColor, value: EditorPalette.text, range: NSRange(location: 0, length: label.length))
        let size = label.size()
        let width = size.height + 4 + size.width
        // Same place as the drawn label: the frame is that label's rect grown by 5 × 3 points.
        CodeBlockLayoutFragment.drawCopy(label, in: CGRect(x: 5, y: 3, width: width, height: size.height))
    }

    override var isFlipped: Bool { true }
}

extension MarkdownTextView: @preconcurrency QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURL == nil ? 0 : 1 }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewURL as NSURL?
    }
}
