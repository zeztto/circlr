import SwiftUI
import AppKit

/// Uses the existing native key-view behavior even when macOS Keyboard navigation is off.
struct StudioModeButton:NSViewRepresentable {
    let title:String
    let label:String
    let selected:Bool
    let help:String
    var keyboard:PortKeyboardFocus? = nil
    var order=0
    let action:()->Void
    @Environment(\.isEnabled) private var enabled
    func makeCoordinator()->Coordinator {Coordinator(self)}
    func makeNSView(context:Context)->PortButtonControl {
        let button=PortButtonControl(title:title,target:context.coordinator,action:#selector(Coordinator.run))
        button.isBordered=false;button.wantsLayer=true;button.layer?.cornerRadius=5
        return button
    }
    func updateNSView(_ button:PortButtonControl,context:Context) {
        context.coordinator.parent=self
        button.navigation=keyboard;keyboard?.register(button,order:order)
        button.title=title;button.isEnabled=enabled
        button.font = .systemFont(ofSize:12,weight:selected ? .semibold:.regular)
        button.contentTintColor=selected ? StudioTheme.accentNS:StudioTheme.secondaryNS
        button.layer?.backgroundColor=selected ? StudioTheme.raisedNS.cgColor:NSColor.clear.cgColor
        button.layer?.borderWidth=1
        button.layer?.borderColor=button.window?.firstResponder===button ? StudioTheme.accentNS.cgColor:StudioTheme.lineNS.cgColor
        button.setAccessibilityLabel(label);button.setAccessibilityValue(selected ? "선택됨":"선택 안 됨")
        button.setAccessibilityHelp(help);button.toolTip=help
    }
    final class Coordinator:NSObject {
        var parent:StudioModeButton
        init(_ parent:StudioModeButton){self.parent=parent}
        @objc func run(){guard parent.enabled else{return};parent.action()}
    }
}
