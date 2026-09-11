import AppKit
import SwiftUI
import CirclrCore

extension View {
    func rememberEditorScroll(_ position:Binding<EditorScrollPosition>)->some View {
        background(EditorScrollMemory(position:position))
    }
}

private struct EditorScrollMemory:NSViewRepresentable {
    @Binding var position:EditorScrollPosition
    func makeNSView(context:Context)->EditorScrollProbe {EditorScrollProbe()}
    func updateNSView(_ view:EditorScrollProbe,context:Context) {view.update($position)}
}

/// Observes an existing SwiftUI scroll view; it adds no scrolling surface or event interception.
private final class EditorScrollProbe:NSView {
    private var position:Binding<EditorScrollPosition>?
    private weak var scroll:NSScrollView?
    private var observer:NSObjectProtocol?
    private var lastModel:EditorScrollPosition?
    private var desired=EditorScrollPosition()
    private var needsRestore=true,scheduled=false,applying=false,reportPending=false
    private var version=0
    override func hitTest(_ point:NSPoint)->NSView? {nil}
    func update(_ binding:Binding<EditorScrollPosition>) {
        position=binding
        if lastModel != binding.wrappedValue {
            lastModel=binding.wrappedValue;desired=binding.wrappedValue;needsRestore=true;version+=1
        }
        schedule()
    }
    override func viewDidMoveToWindow(){super.viewDidMoveToWindow();schedule()}
    override func viewDidMoveToSuperview(){super.viewDidMoveToSuperview();schedule()}
    override func layout(){super.layout();schedule()}
    override func viewWillMove(toWindow newWindow:NSWindow?) {
        if newWindow==nil {
            if let observer {NotificationCenter.default.removeObserver(observer)}
            observer=nil;scroll=nil;needsRestore=true;version+=1
        }
        super.viewWillMove(toWindow:newWindow)
    }
    deinit {if let observer {NotificationCenter.default.removeObserver(observer)}}
    private func schedule() {
        guard !scheduled else{return};scheduled=true
        DispatchQueue.main.async{[weak self] in guard let self else{return};self.scheduled=false;self.restore()}
    }
    private func restore() {
        guard window != nil,let owner=enclosingScrollView,let document=owner.documentView,
              owner.contentView.bounds.width>0,owner.contentView.bounds.height>0,
              document.bounds.width>0,document.bounds.height>0 else{return}
        if scroll !== owner {
            if let observer {NotificationCenter.default.removeObserver(observer)}
            scroll=owner;needsRestore=true;version+=1
            owner.contentView.postsBoundsChangedNotifications=true
            observer=NotificationCenter.default.addObserver(forName:NSView.boundsDidChangeNotification,object:owner.contentView,queue:.main){[weak self] _ in
                MainActor.assumeIsolated{self?.changed()}
            }
        }
        guard needsRestore else{return}
        let value=clamped(desired,in:owner)
        applying=true;owner.contentView.scroll(to:NSPoint(x:value.x,y:value.y));owner.reflectScrolledClipView(owner.contentView);applying=false
        needsRestore=false;lastModel=value
        if position?.wrappedValue != value {position?.wrappedValue=value}
    }
    private func clamped(_ value:EditorScrollPosition,in owner:NSScrollView)->EditorScrollPosition {
        let size=owner.documentView?.bounds.size ?? .zero,visible=owner.contentView.bounds.size
        return value.clamped(width:size.width,height:size.height,visibleWidth:visible.width,visibleHeight:visible.height)
    }
    private func changed() {
        guard !applying,!needsRestore,!reportPending else{return};reportPending=true
        let currentVersion=version
        DispatchQueue.main.async{[weak self] in
            guard let self else{return};self.reportPending=false
            guard self.window != nil,!self.needsRestore,self.version==currentVersion,let owner=self.scroll else{return}
            let origin=owner.contentView.bounds.origin,value=self.clamped(.init(x:origin.x,y:origin.y),in:owner)
            self.lastModel=value;self.desired=value
            if self.position?.wrappedValue != value {self.position?.wrappedValue=value}
        }
    }
}
