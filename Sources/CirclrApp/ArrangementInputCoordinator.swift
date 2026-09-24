import AppKit
import SwiftUI
import CirclrCore

@MainActor final class ArrangementInputCoordinator:NSObject,ObservableObject,NSTextFieldDelegate {
    struct NameOperation {let duplicate:Bool;let sourceID:ID;let sourceTitle:String}
    @Published var query=""
    @Published var highlighted:ID?
    @Published var naming:NameOperation?
    @Published var draft=""
    @Published var notice=""
    private weak var store:AppStore?
    private weak var window:NSWindow?
    private weak var field:ArrangementInputField.Control?
    private var monitor:Any?
    private var requestID:UUID?
    private(set) var modeID=UUID()
    private var pending:[(UUID,UUID,NSEvent)]=[]
    private var request:ArrangementPickerRequest? {
        guard let value=store?.arrangementPickerRequest,value.input===self,value.id==requestID else{return nil}
        return value
    }
    var rows:[ArrangementChoice] {request.map{ArrangementSelection.search($0.choices,query:query)} ?? []}
    var active:ID? {rows.contains{$0.id==highlighted} ? highlighted:rows.first?.id}
    var current:Bool {guard let store,let request else{return false};return store.arrangementPickerCurrent(request)}
    var text:String {naming == nil ? query:draft}
    func bind(store:AppStore,request:ArrangementPickerRequest) {
        self.store=store;window=NSApp.keyWindow;requestID=request.id;field=nil
        query="";highlighted=request.currentID;naming=nil;draft="";notice="";modeID=UUID();pending=[]
        if monitor==nil {
            monitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown){[weak self] event in guard let self else{return event};return self.route(event)}
        }
    }
    func stop(){if let monitor{NSEvent.removeMonitor(monitor)};monitor=nil;pending=[];requestID=nil;field=nil}
    deinit {if let monitor{NSEvent.removeMonitor(monitor)}}
    private var activeWindow:Bool {NSApp.isActive && window?.isKeyWindow==true}
    private var marked:Bool {(field?.currentEditor() as? NSTextView)?.hasMarkedText()==true}
    private func route(_ event:NSEvent)->NSEvent? {
        guard let request,event.window===window else{return event}
        guard activeWindow else{pending=[];return nil}
        let flags=event.modifierFlags.intersection([.command,.option,.control,.shift])
        let shortcut=flags == [.command,.shift] && [2,14,45].contains(event.keyCode)
        if !pending.isEmpty,let field,field.active,field.requestID==request.id {
            let owner=request.id
            guard let routedMode=drain(),self.request?.id==owner,modeID==routedMode else{return nil}
        }
        if shortcut,pending.isEmpty {
            guard !marked else{return nil}
            if naming==nil {
                if event.keyCode==2 {beginName(duplicate:true,sourceID:active)}
                else if event.keyCode==45 {beginName(duplicate:false,sourceID:active)}
                else {continueEditing()}
            }
            return nil
        }
        if let field,field.active,field.requestID==request.id {
            // The picker owns Tab traversal. Do not pull focus back from one of
            // its buttons/rows after keyboard navigation leaves the text field.
            if event.keyCode==48,flags.isEmpty || flags == .shift {return event}
            if let responder=window?.firstResponder,responder !== field,
               responder !== field.currentEditor(){return event}
            guard focus(field) else{pending=[];notice="입력창을 활성화하지 못했습니다. 편곡안을 다시 여세요.";return nil}
            return event
        }
        pending.removeAll{$0.0 != request.id || $0.1 != modeID || ProcessInfo.processInfo.systemUptime-$0.2.timestamp>2}
        guard pending.count<256 else{pending=[];notice="입력 대기가 길어졌습니다. 편곡안을 다시 여세요.";return nil}
        pending.append((request.id,modeID,event));return nil
    }
    private func focus(_ field:ArrangementInputField.Control)->Bool {
        guard activeWindow,field.active,field.window===window else{return false}
        if let editor=field.currentEditor(),window?.firstResponder===editor{return true}
        if window?.firstResponder===field{return true}
        guard window?.makeFirstResponder(field)==true else{return false}
        return window?.firstResponder===field || field.currentEditor().map{window?.firstResponder===$0}==true
    }
    func attach(_ field:ArrangementInputField.Control) {
        guard let request,field.requestID==request.id,field.window===window,field.active else{return}
        guard self.field !== field || field.modeID != modeID else{return}
        self.field=field;syncField();_ = focus(field)
        let owner=request.id,mode=modeID
        DispatchQueue.main.async{[weak self,weak field] in
            guard let self,let field,self.request?.id==owner,self.modeID==mode,field.active,field.window===self.window else{return}
            _ = self.drain()
        }
    }
    /// Returns the final mode only if the batch stayed in its request and crossed
    /// no mode boundary other than an explicit search-to-name shortcut.
    private func drain()->UUID? {
        guard let request,let field,field.requestID==request.id,focus(field) else{return nil}
        let owner=request.id
        var mode=modeID
        let events=pending.filter{$0.0==owner && $0.1==mode && ProcessInfo.processInfo.systemUptime-$0.2.timestamp<=2}.map{$0.2}
        pending=[]
        for event in events {
            guard self.request?.id==owner,modeID==mode,field.active,field.window===window,focus(field) else{return nil}
            let wasSearch=naming==nil
            NSApp.sendEvent(event)
            let flags=event.modifierFlags.intersection([.command,.option,.control,.shift])
            // Preserve ordered type-ahead across this explicit search-to-name command only.
            // Submit, Escape, replacement requests and external invalidation discard the suffix.
            if wasSearch,naming != nil,flags == [.command,.shift],[2,45].contains(event.keyCode),self.request?.id==owner {
                mode=modeID
            }
        }
        guard self.request?.id==owner,modeID==mode else{return nil}
        return mode
    }
    private func syncField() {
        guard let field,field.active,field.requestID==requestID else{return}
        field.modeID=modeID;field.placeholderString=naming == nil ? "편곡안 이름 또는 #번호 검색":"편곡안 이름"
        field.setAccessibilityLabel(naming.map{$0.duplicate ? "새 편곡안 이름":"이름 변경 대상 · "+$0.sourceTitle} ?? "편곡안 검색")
        if field.stringValue != text {field.stringValue=text}
        if let editor=field.currentEditor() as? NSTextView,editor.string != text {editor.string=text;editor.setSelectedRange(NSRange(location:(text as NSString).length,length:0))}
    }
    private func changeMode(){modeID=UUID();pending=[];syncField();if let field{_ = focus(field)}}
    func findCurrent(){guard naming==nil,let request else{return};query="";highlighted=request.currentID;syncField();if let field{_ = focus(field)}}
    func move(_ delta:Int){guard naming==nil,!rows.isEmpty else{return};let index=rows.firstIndex{$0.id==active} ?? 0;highlighted=rows[max(0,min(rows.count-1,index+delta))].id}
    func beginName(duplicate:Bool,sourceID:ID?) {
        guard !marked,naming==nil,current,let request,let sourceID,let choice=request.choices.first(where:{$0.id==sourceID}) else{return}
        highlighted=sourceID;notice="";draft=duplicate ? "":choice.name
        naming=NameOperation(duplicate:duplicate,sourceID:sourceID,sourceTitle:choice.title);changeMode()
    }
    func cancel(){guard !marked else{return};if naming != nil{naming=nil;draft="";notice="";changeMode()}else{store?.closeArrangementPicker()}}
    func submit(){guard !marked else{return};if naming != nil{commitName()}else if let active{apply(active)}}
    func commitName(){
        guard !marked,let store,let request,let operation=naming else{return}
        do {try store.editArrangementName(draft,duplicate:operation.duplicate,sourceID:operation.sourceID,request:request)}catch{notice=error.localizedDescription}
    }
    func apply(_ id:ID){guard naming==nil,let store,let request,rows.contains(where:{$0.id==id}) else{return};do{try store.applyArrangement(id,request:request)}catch{notice=error.localizedDescription}}
    func continueEditing(){guard naming==nil,let store,let request else{return};do{try store.continueArrangementEditing(request);if store.arrangementPickerRequest==nil{stop()}}catch{notice=error.localizedDescription}}
    func controlTextDidChange(_ notification:Notification) {
        guard let field=notification.object as? ArrangementInputField.Control,field.active,field.requestID==request?.id,field.modeID==modeID else{return}
        if naming==nil{query=field.stringValue;highlighted=nil}else{draft=field.stringValue}
    }
    func control(_ control:NSControl,textView:NSTextView,doCommandBy selector:Selector)->Bool {
        guard let field=control as? ArrangementInputField.Control,field.active,field.requestID==request?.id,field.modeID==modeID else{return true}
        if textView.hasMarkedText(){return false}
        if selector==#selector(NSResponder.insertNewline(_:)){submit();return true}
        if selector==#selector(NSResponder.cancelOperation(_:)){cancel();return true}
        if naming==nil,selector==#selector(NSResponder.moveUp(_:)){move(-1);return true}
        if naming==nil,selector==#selector(NSResponder.moveDown(_:)){move(1);return true}
        return false
    }
}

struct ArrangementInputField:NSViewRepresentable {
    @ObservedObject var input:ArrangementInputCoordinator
    let requestID:UUID
    func makeNSView(context:Context)->Control {
        let field=Control();field.input=input;field.requestID=requestID;field.delegate=input
        field.font = .systemFont(ofSize:14);field.focusRingType = .none;return field
    }
    func updateNSView(_ field:Control,context:Context){field.input=input;field.requestID=requestID;if field.window != nil {input.attach(field)}}
    static func dismantleNSView(_ field:Control,coordinator:()){field.active=false;field.delegate=nil;field.input=nil}
    final class Control:NSTextField {
        weak var input:ArrangementInputCoordinator?
        var requestID:UUID?
        var modeID:UUID?
        var active=true
        override func viewDidMoveToWindow(){super.viewDidMoveToWindow();if window != nil{input?.attach(self)}}
    }
}
