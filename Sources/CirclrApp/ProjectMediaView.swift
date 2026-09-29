import SwiftUI
import AppKit
import CirclrCore

struct ProjectMediaView:View {
    @ObservedObject var store:AppStore
    @ObservedObject var workspace:ProjectMediaWorkspace
    let size:CGSize
    @FocusState private var keyboardFocus:String?
    private var keyboardOrder:[String]{["close"] + (workspace.busy ? ["cancel"] : workspace.draining ? []:workspace.issues.map{"asset-"+$0.assetID}+["refresh","copy","diagnostics"])}
    init(store:AppStore,size:CGSize){self.store=store;self.workspace=store.projectMedia;self.size=size}
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Text("곡 미디어와 복구").font(.headline)
                Spacer()
                Button("닫기"){workspace.close()}.keyboardShortcut(.escape,modifiers:[]).focusable().focused($keyboardFocus,equals:"close")
            }
            Text("누락되거나 내용이 바뀐 미디어를 확인하고, 전체 미디어를 포함한 사본을 저장합니다.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            HStack {
                if workspace.busy || workspace.draining {ProgressView().controlSize(.small);Button("작업 취소"){workspace.cancel()}.disabled(workspace.draining).focusable().focused($keyboardFocus,equals:"cancel")}
                Text(workspace.message).font(.callout).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
            }.accessibilityElement(children:.combine)
            ScrollViewReader {proxy in
            ScrollView {
                LazyVStack(alignment:.leading,spacing:12) {
                    ForEach(workspace.issues,id:\.assetID) {issue in
                        VStack(alignment:.leading,spacing:5) {
                            Text(issue.displayName).font(.body.weight(.medium)).lineLimit(2)
                            Text(issue.reason).font(.caption).foregroundStyle(.secondary)
                            Button("원본 찾기…"){workspace.chooseReplacement(issue)}.disabled(workspace.busy || workspace.draining).focusable().focused($keyboardFocus,equals:"asset-"+issue.assetID).id("asset-"+issue.assetID)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                        Divider()
                    }
                }.padding(.vertical,4)
            }.frame(maxHeight:300)
            .onChange(of:keyboardFocus){_,value in if let value,value.hasPrefix("asset-"){proxy.scrollTo(value,anchor:.center)}}
            }
            if size.width<540 {VStack(alignment:.leading,spacing:8){actions}} else {HStack {actions}}
        }.padding(20).frame(width:min(620,max(280,size.width-24)))
            .background(.regularMaterial,in:RoundedRectangle(cornerRadius:14))
            .overlay(RoundedRectangle(cornerRadius:14).stroke(.white.opacity(0.14)))
            .frame(maxHeight:size.height-24)
            .background(OverlayKeyboardKeys(active:{store.projectMediaOpen},move:{backward in keyboardFocus=OverlayKeyboardTraversal.next(in:keyboardOrder,current:keyboardFocus,backward:backward)},cancel:workspace.close).frame(width:0,height:0))
            .background(ProjectMediaActivationKeys(active:{store.projectMediaOpen && keyboardOrder.contains(keyboardFocus ?? "")},activate:activateFocused).frame(width:0,height:0))
            .onAppear{keyboardFocus="close"}
            .onChange(of:keyboardOrder){_,order in if !order.contains(keyboardFocus ?? ""){keyboardFocus="close"}}
    }
    private func activateFocused() {
        guard let focus=keyboardFocus,keyboardOrder.contains(focus) else{return}
        switch focus {
        case "close":workspace.close()
        case "cancel":workspace.cancel()
        case "refresh":workspace.refresh()
        case "copy":workspace.choosePortableCopy()
        case "diagnostics":store.exportProjectDiagnostics()
        default:
            if let issue=workspace.issues.first(where:{"asset-"+$0.assetID==focus}){workspace.chooseReplacement(issue)}
        }
    }
    @ViewBuilder private var actions:some View {
        Button("다시 검사"){workspace.refresh()}.disabled(workspace.busy || workspace.draining).focusable().focused($keyboardFocus,equals:"refresh")
        Button("미디어 포함 사본 저장…"){workspace.choosePortableCopy()}.disabled(workspace.busy || workspace.draining).focusable().focused($keyboardFocus,equals:"copy")
        Button("진단 정보 저장…"){store.exportProjectDiagnostics()}.disabled(workspace.busy || workspace.draining).focusable().focused($keyboardFocus,equals:"diagnostics")
    }
}


/// Explicit activation for SwiftUI focus wrappers, whose focus ring does not
/// necessarily belong to NSButton's native Space/Return responder.
enum ProjectMediaActivationKey {
    static func accepts(keyCode:UInt16,modifiers:NSEvent.ModifierFlags,markedText:Bool)->Bool {
        !markedText && modifiers.intersection([.command,.control,.option,.shift]).isEmpty && [36,76,49].contains(keyCode)
    }
}
private struct ProjectMediaActivationKeys:NSViewRepresentable {
    let active:()->Bool
    let activate:()->Void
    func makeNSView(context:Context)->Control {let view=Control();view.active=active;view.activate=activate;return view}
    func updateNSView(_ view:Control,context:Context){view.active=active;view.activate=activate}
    static func dismantleNSView(_ view:Control,coordinator:()){view.removeMonitor()}
    final class Control:NSView {
        var active:(()->Bool)?
        var activate:(()->Void)?
        private var monitor:Any?
        func removeMonitor(){if let monitor{NSEvent.removeMonitor(monitor)};monitor=nil}
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow();removeMonitor()
            guard window != nil else{return}
            monitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown){[weak self] event in
                guard let self,let window=self.window,event.window===window,NSApp.isActive,window.isKeyWindow,self.active?()==true else{return event}
                let marked=(window.firstResponder as? NSTextView)?.hasMarkedText()==true
                guard ProjectMediaActivationKey.accepts(keyCode:event.keyCode,modifiers:event.modifierFlags,markedText:marked) else{return event}
                if !event.isARepeat{self.activate?()}
                return nil
            }
        }
    }
}
