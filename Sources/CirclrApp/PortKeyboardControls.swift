import AppKit
import SwiftUI

/// A local key loop, independent of macOS's global "Keyboard navigation" preference.
@MainActor final class PortKeyboardFocus: ObservableObject {
    private final class Entry { weak var control: NSControl?; init(_ control: NSControl) { self.control = control } }
    private var entries: [Int: Entry] = [:]
    private var requestedOrder: Int?
    private var focusScheduled = false
    func register(_ control: NSControl, order: Int) {
        control.tag = order; entries[order] = Entry(control)
        // SwiftUI may request focus before the AppKit control is attached to its window.
        if requestedOrder == order { scheduleFocusRequest() }
    }
    func focus(_ order: Int) {
        requestedOrder = order; fulfillFocusRequest()
    }
    func fulfillFocusRequest() {
        guard let order = requestedOrder, let control = entries[order]?.control, let window = control.window,
              control.bounds.width > 0, control.bounds.height > 0,
              control.isEnabled, !control.isHiddenOrHasHiddenAncestor else { return }
        var ancestor = control.superview
        while let view = ancestor {
            // The zoom can resize/rebuild the inline editor after an early focus succeeds.
            if let canvas = view as? AlbumCanvasView, canvas.animation != nil { return }
            ancestor = view.superview
        }
        Self.reveal(control)
        if window.makeFirstResponder(control) {
            if let field = control as? NSTextField, field.currentEditor() == nil { return }
            requestedOrder = nil
        }
    }
    static func reveal(_ control:NSView) {
        if let table=control as? NSTableView,table.selectedRow>=0,table.selectedRow<table.numberOfRows {
            table.scrollRowToVisible(table.selectedRow)
            let row=table.rect(ofRow:table.selectedRow)
            table.scrollToVisible(row)
            if let viewport=table.enclosingScrollView {
                // Reveal this row through the outer composer scroll, not the entire table viewport.
                viewport.scrollToVisible(table.convert(row,to:viewport))
            }
        }else {control.scrollToVisible(control.bounds)}
    }
    func scheduleFocusRequest() {
        guard requestedOrder != nil, !focusScheduled else { return }
        focusScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }; self.focusScheduled = false; self.fulfillFocusRequest()
        }
    }
    func move(from order: Int, backwards: Bool) {
        let available = entries.keys.sorted().filter { key in
            guard let control = entries[key]?.control else { return false }
            return control.window != nil && control.isEnabled && !control.isHiddenOrHasHiddenAncestor
        }
        guard !available.isEmpty else { return }
        let index = available.firstIndex(of: order) ?? 0
        focus(available[(index+(backwards ? -1 : 1)+available.count)%available.count])
    }
    func handleTab(_ event: NSEvent, control: NSControl) -> Bool {
        guard event.keyCode == 48, event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        move(from: control.tag, backwards: event.modifierFlags.contains(.shift)); return true
    }
}

private func decoratePortControl(_ control: NSControl) {
    control.font = .systemFont(ofSize: 13)
    control.wantsLayer = true; control.layer?.cornerRadius = 5
    control.layer?.backgroundColor = StudioTheme.raisedNS.cgColor
    control.layer?.borderColor = StudioTheme.lineNS.cgColor; control.layer?.borderWidth = 1
}

final class PortPopupControl: NSPopUpButton {
    weak var navigation: PortKeyboardFocus?
    override var acceptsFirstResponder: Bool { isEnabled }
    override var canBecomeKeyView: Bool { isEnabled && !isHiddenOrHasHiddenAncestor }
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder(); layer?.borderColor = StudioTheme.accentNS.cgColor; return result
    }
    override func resignFirstResponder() -> Bool {
        layer?.borderColor = StudioTheme.lineNS.cgColor; return super.resignFirstResponder()
    }
    override func keyDown(with event: NSEvent) {
        if navigation?.handleTab(event, control: self) == true { return }
        if [125, 126].contains(event.keyCode), event.modifierFlags.intersection([.command, .control, .option]).isEmpty, numberOfItems > 0 {
            let next = max(0, min(numberOfItems-1, indexOfSelectedItem+(event.keyCode == 125 ? 1 : -1)))
            if next != indexOfSelectedItem { selectItem(at: next); sendAction(action, to: target) }
            return
        }
        if [36, 49, 76].contains(event.keyCode), event.modifierFlags.intersection([.command, .control, .option]).isEmpty { if !event.isARepeat { performClick(nil) }; return }
        super.keyDown(with: event)
    }
}

struct PortChoice<Value: Hashable>: NSViewRepresentable {
    let label: String
    @Binding var selection: Value
    let options: [(Value, String)]
    let keyboard: PortKeyboardFocus
    let order: Int
    @Environment(\.isEnabled) private var enabled
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> PortPopupControl {
        let control = PortPopupControl(frame: .zero, pullsDown: false)
        control.isBordered = false; control.contentTintColor = StudioTheme.textNS
        decoratePortControl(control); control.target = context.coordinator; control.action = #selector(Coordinator.choose(_:))
        return control
    }
    func updateNSView(_ control: PortPopupControl, context: Context) {
        context.coordinator.parent = self; control.navigation = keyboard; keyboard.register(control, order: order)
        control.isEnabled = enabled
        let titles = options.map(\.1)
        if control.itemTitles != titles { control.removeAllItems(); control.addItems(withTitles: titles) }
        control.selectItem(at: options.firstIndex { $0.0 == selection } ?? -1)
        control.setAccessibilityLabel(label); control.setAccessibilityHelp("위아래 선택 · Tab 다음 항목 · Shift Tab 이전 항목 · Return 목록")
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PortPopupControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 240, height: 34)
    }
    final class Coordinator: NSObject {
        var parent: PortChoice
        init(_ parent: PortChoice) { self.parent = parent }
        @objc func choose(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            guard parent.options.indices.contains(index) else { return }
            parent.selection = parent.options[index].0
        }
    }
}

final class PortButtonControl: NSButton {
    weak var navigation: PortKeyboardFocus?
    override var acceptsFirstResponder: Bool { isEnabled }
    override var canBecomeKeyView: Bool { isEnabled && !isHiddenOrHasHiddenAncestor }
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder(); layer?.borderColor = StudioTheme.accentNS.cgColor; return result
    }
    override func resignFirstResponder() -> Bool {
        layer?.borderColor = StudioTheme.lineNS.cgColor; return super.resignFirstResponder()
    }
    override func keyDown(with event: NSEvent) {
        if navigation?.handleTab(event, control: self) == true { return }
        if navigation == nil, event.keyCode == 48, event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            if event.modifierFlags.contains(.shift) {window?.selectPreviousKeyView(self)} else {window?.selectNextKeyView(self)}
            return
        }
        if [36, 49, 76].contains(event.keyCode), event.modifierFlags.intersection([.command, .control, .option]).isEmpty { if !event.isARepeat { performClick(nil) }; return }
        super.keyDown(with: event)
    }
}

struct PortActionButton: NSViewRepresentable {
    let title: String
    let keyboard: PortKeyboardFocus
    let order: Int
    var label: String? = nil
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> PortButtonControl {
        let control = PortButtonControl(title: title, target: context.coordinator, action: #selector(Coordinator.run))
        control.isBordered = false; control.contentTintColor = StudioTheme.textNS; decoratePortControl(control)
        return control
    }
    func updateNSView(_ control: PortButtonControl, context: Context) {
        context.coordinator.parent = self; control.title = title; control.isEnabled = enabled
        control.navigation = keyboard; keyboard.register(control, order: order); control.setAccessibilityLabel(label ?? title)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PortButtonControl, context: Context) -> CGSize? {
        CGSize(width: nsView.intrinsicContentSize.width+16, height: 30)
    }
    final class Coordinator: NSObject {
        var parent: PortActionButton
        init(_ parent: PortActionButton) { self.parent = parent }
        @objc func run() { guard parent.enabled else { return }; parent.action() }
    }
}

final class PortSearchControl: NSTextField {
    weak var navigation: PortKeyboardFocus?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); navigation?.scheduleFocusRequest()
    }
    override func layout() { super.layout(); navigation?.scheduleFocusRequest() }
}

struct PortSearchField: NSViewRepresentable {
    @Binding var text: String
    let keyboard: PortKeyboardFocus
    let order: Int
    var label: String = "대상 이름 검색"
    var moveSelection: ((Int) -> Void)?
    var submit: (() -> Void)?
    @Environment(\.isEnabled) private var enabled
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> PortSearchControl {
        let control = PortSearchControl(); control.placeholderString = label
        control.isBordered = false; control.drawsBackground = true; control.backgroundColor = StudioTheme.raisedNS
        control.textColor = StudioTheme.textNS; decoratePortControl(control); control.delegate = context.coordinator
        control.setAccessibilityLabel(label)
        return control
    }
    func updateNSView(_ control: PortSearchControl, context: Context) {
        context.coordinator.parent = self; control.navigation = keyboard; keyboard.register(control, order: order)
        control.isEnabled=enabled
        control.placeholderString=label;control.setAccessibilityLabel(label)
        if control.stringValue != text { control.stringValue = text }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PortSearchControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 240, height: 34)
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PortSearchField
        init(_ parent: PortSearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            if let control = notification.object as? NSTextField { parent.text = control.stringValue }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard parent.enabled,!textView.hasMarkedText() else { return false }
            if selector == #selector(NSResponder.insertTab(_:)) || selector == #selector(NSResponder.insertBacktab(_:)) {
                parent.keyboard.move(from: parent.order, backwards: selector == #selector(NSResponder.insertBacktab(_:))); return true
            }
            if let move=parent.moveSelection,selector == #selector(NSResponder.moveDown(_:)) || selector == #selector(NSResponder.moveUp(_:)) {
                move(selector == #selector(NSResponder.moveDown(_:)) ? 1:-1);return true
            }
            if let submit=parent.submit,selector == #selector(NSResponder.insertNewline(_:)) {submit();return true}
            return false
        }
    }
}
