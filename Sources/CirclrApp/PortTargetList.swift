import AppKit
import SwiftUI
import CirclrCore

typealias PortTargetItem=ConnectionTargetChoice

/// Visible search results, sharing the connection editor's local keyboard loop.
struct PortTargetList:NSViewRepresentable {
    let items:[PortTargetItem]
    @Binding var selection:CirclePortEndpoint?
    let keyboard:PortKeyboardFocus
    let order:Int
    let activate:()->Void
    @Environment(\.isEnabled) private var enabled
    func makeCoordinator()->Coordinator {Coordinator(self)}
    func makeNSView(context:Context)->NSScrollView {
        let scroll=NSScrollView()
        // Isolate table redraws from the adjacent SwiftUI/AppKit controls.
        scroll.wantsLayer=true;scroll.clipsToBounds=true;scroll.layer?.masksToBounds=true
        scroll.contentView.wantsLayer=true;scroll.contentView.clipsToBounds=true;scroll.contentView.layer?.masksToBounds=true
        scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true
        scroll.drawsBackground=true;scroll.backgroundColor=StudioTheme.raisedNS
        let table=Control()
        table.wantsLayer=true
        let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("target"))
        column.resizingMask = .autoresizingMask;table.addTableColumn(column)
        table.headerView=nil;table.rowHeight=62;table.intercellSpacing=NSSize(width:0,height:2)
        table.backgroundColor=StudioTheme.raisedNS;table.allowsEmptySelection=true
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.dataSource=context.coordinator;table.delegate=context.coordinator
        table.setAccessibilityLabel("대상 포트 검색 결과")
        scroll.documentView=table
        return scroll
    }
    func updateNSView(_ scroll:NSScrollView,context:Context) {
        guard let table=scroll.documentView as? Control else{return}
        let coordinator=context.coordinator;coordinator.parent=self
        table.isEnabled=enabled;table.navigation=keyboard;table.activate=activate
        keyboard.register(table,order:order)
        coordinator.updating=true
        let changed=coordinator.items != items
        if changed {coordinator.items=items;table.reloadData()}
        let selected=selection.flatMap{id in items.firstIndex{$0.endpoint==id}} ?? -1
        let moved=table.selectedRow != selected
        if table.selectedRow != selected {
            if selected>=0 {table.selectRowIndexes(IndexSet(integer:selected),byExtendingSelection:false)}
            else {table.deselectAll(nil)}
        }
        if selected>=0 && (changed || moved) {table.scrollRowToVisible(selected)}
        coordinator.updating=false
    }
    final class Control:NSTableView {
        weak var navigation:PortKeyboardFocus?
        var activate:(()->Void)?
        override var acceptsFirstResponder:Bool {isEnabled}
        override func keyDown(with event:NSEvent) {
            guard isEnabled else{return}
            if navigation?.handleTab(event,control:self)==true{return}
            if [36,76].contains(event.keyCode),event.modifierFlags.intersection([.command,.control,.option]).isEmpty {
                if !event.isARepeat,selectedRow>=0 {activate?()};return
            }
            super.keyDown(with:event)
        }
    }
    final class Coordinator:NSObject,NSTableViewDataSource,NSTableViewDelegate {
        var parent:PortTargetList
        var items:[PortTargetItem]=[]
        var updating=false
        init(_ parent:PortTargetList){self.parent=parent}
        func numberOfRows(in tableView:NSTableView)->Int {items.count}
        func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
            guard items.indices.contains(row) else{return nil}
            let item=items[row],cell=NSTableCellView()
            let name=NSTextField(labelWithString:item.title),port=NSTextField(labelWithString:item.detail)
            name.font = .systemFont(ofSize:13,weight:.medium);name.textColor=StudioTheme.textNS
            port.font = .systemFont(ofSize:11);port.textColor=StudioTheme.secondaryNS
            for field in [name,port] {field.lineBreakMode = .byTruncatingTail;field.translatesAutoresizingMaskIntoConstraints=false;cell.addSubview(field)}
            name.maximumNumberOfLines=2;name.usesSingleLineMode=false;name.cell?.wraps=true
            NSLayoutConstraint.activate([
                name.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:8),name.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-8),name.topAnchor.constraint(equalTo:cell.topAnchor,constant:5),
                name.heightAnchor.constraint(equalToConstant:32),
                port.leadingAnchor.constraint(equalTo:name.leadingAnchor),port.trailingAnchor.constraint(equalTo:name.trailingAnchor),port.topAnchor.constraint(equalTo:name.bottomAnchor,constant:3)
            ])
            cell.textField=name;cell.toolTip=item.title+" · "+item.detail
            cell.setAccessibilityLabel(item.title+" · "+item.detail)
            return cell
        }
        func tableViewSelectionDidChange(_ notification:Notification) {
            guard !updating,parent.enabled,let table=notification.object as? NSTableView else{return}
            parent.selection=items.indices.contains(table.selectedRow) ? items[table.selectedRow].endpoint:nil
        }
    }
}
