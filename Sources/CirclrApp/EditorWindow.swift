import AppKit
import SwiftUI

/// One nonmodal, reusable editor. The canvas never becomes its container.
struct EditorWindowBridge:NSViewRepresentable {
    @ObservedObject var store:AppStore
    func makeCoordinator()->Coordinator {Coordinator(store:store)}
    func makeNSView(context:Context)->NSView {NSView(frame:.zero)}
    func updateNSView(_ view:NSView,context:Context) {
        // SwiftUI's update pass must finish before an AppKit window changes focus.
        if let window=view.window {context.coordinator.mainWindow=window}
        context.coordinator.schedule()
    }
    static func dismantleNSView(_ view:NSView,coordinator:Coordinator) {coordinator.closing=true;coordinator.editor?.close()}
    @MainActor final class Coordinator:NSObject,NSWindowDelegate {
        weak var store:AppStore?
        weak var mainWindow:NSWindow?
        var editor:NSWindow?
        var hostedFocus:CanvasFocus?
        var activation:UUID?
        var pending=false
        var closing=false
        init(store:AppStore){self.store=store}
        func schedule() {
            guard !pending else{return};pending=true
            DispatchQueue.main.async {[weak self] in self?.pending=false;self?.synchronize()}
        }
        func synchronize() {
            guard let store else{return}
            guard let focus=store.focus else {
                if hostedFocus != nil {
                    closing=true;editor?.close();closing=false;hostedFocus=nil
                    mainWindow?.makeKeyAndOrderFront(nil)
                }
                return
            }
            guard store.focusExists(focus) else {store.closeFocus();return}
            let changed=hostedFocus != focus
            if editor==nil {
                let window=MusicEditorWindow(contentRect:NSRect(x:0,y:0,width:1180,height:820),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
                window.store=store
                window.minSize=NSSize(width:1000,height:700)
                window.isReleasedWhenClosed=false;window.delegate=self
                window.appearance=NSAppearance(named:.darkAqua)
                window.backgroundColor=StudioTheme.surfaceNS
                window.titlebarAppearsTransparent=true
                window.setFrameAutosaveName("circlr.unified-editor")
                window.center();editor=window
            }
            if changed || editor?.contentView == nil {
                let view=NSHostingView(rootView:CircleWorkspace(store:store,focus:focus).id(String(describing:focus)))
                view.sizingOptions=[]
                editor?.contentView=view;hostedFocus=focus
            }
            editor?.title=store.focusTitle(focus)+" — 써클러"
            if activation != store.editorActivation {
                activation=store.editorActivation
                if editor?.isMiniaturized == true {editor?.deminiaturize(nil)}
                editor?.makeKeyAndOrderFront(nil)
            }
        }
        func windowWillClose(_ notification:Notification) {
            guard !closing else{return}
            hostedFocus=nil;store?.closeFocus();mainWindow?.makeKeyAndOrderFront(nil)
        }
    }
}

@MainActor final class MusicEditorWindow:NSWindow {
    weak var store:AppStore?
    override func cancelOperation(_ sender:Any?) {performClose(sender)}
    override func keyDown(with event:NSEvent) {
        if event.keyCode==53 {performClose(nil)}
        else if event.keyCode==49 {store?.play()}
        else {super.keyDown(with:event)}
    }
}
