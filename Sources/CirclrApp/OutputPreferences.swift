import SwiftUI
import AppKit
import CirclrAudio

/// App-local choice; never part of Project, music revision, or Undo.
@MainActor final class OutputPreferences:ObservableObject {
    private static let key="circlr.playback.outputDeviceUID"
    private let defaults:UserDefaults
    private let query:@Sendable () async throws -> OutputDeviceCatalog
    private var task:Task<Void,Never>?
    private var generation=0
    @Published private(set) var selection:OutputDeviceSelection
    @Published private(set) var catalog:OutputDeviceCatalog?
    @Published private(set) var loading=false
    @Published private(set) var message:String?

    init(defaults:UserDefaults = .standard,query:@escaping @Sendable () async throws -> OutputDeviceCatalog = {try await OutputDeviceCatalogProcess().query()}) {
        self.defaults=defaults;self.query=query
        if let uid=defaults.string(forKey:Self.key),
           (try? OutputDeviceSelection.deviceUID(uid).validate()) != nil {
            selection = .deviceUID(uid)
        }else{selection = .systemDefault}
    }
    var selectedUID:String? {if case .deviceUID(let uid)=selection{return uid};return nil}
    var selectedName:String {
        guard let uid=selectedUID else{return "시스템 기본값"}
        return catalog?.devices.first(where:{$0.uid==uid})?.name ?? "저장된 출력 장치"
    }
    var missing:Bool {
        guard let uid=selectedUID,let catalog else{return false}
        return !catalog.devices.contains(where:{$0.uid==uid})
    }
    var defaultName:String? {
        guard let catalog,let uid=catalog.defaultUID else{return nil}
        return catalog.devices.first(where:{$0.uid==uid})?.name
    }
    func choose(_ uid:String?) {
        if let uid {
            guard catalog?.devices.contains(where:{$0.uid==uid}) == true else{return}
            selection = .deviceUID(uid);defaults.set(uid,forKey:Self.key)
        }else{selection = .systemDefault;defaults.removeObject(forKey:Self.key)}
    }
    func refresh() {
        cancel();generation+=1;let ticket=generation;loading=true;message=nil
        let query=query
        task=Task{[weak self] in
            do {
                let result=try await query();try result.validate();try Task.checkCancellation()
                guard let self,self.generation==ticket else{return}
                self.catalog=result;self.loading=false;self.task=nil
            }catch{
                guard let self,self.generation==ticket else{return}
                self.loading=false;self.task=nil
                if !(error is CancellationError) {
                    // Query errors can originate in helpers; never surface raw UID or payload.
                    self.message = (error as? OutputDeviceCatalogError)?.errorDescription ?? "출력 장치 목록을 확인하지 못했습니다. 다시 조회하세요."
                }
            }
        }
    }
    func cancel(){generation+=1;task?.cancel();task=nil;loading=false}
}

extension AppStore {
    func showOutputPreferences() {
        guard nameEditing.resolve() else{return}
        arrangementPickerRequest=nil;soundPickerRequest=nil;libraryOpen=false;navigationOpen=false;commandPalette=nil;keyboardHelp=false
        NSApp.keyWindow?.makeFirstResponder(nil)
        outputPreferencesOpen=true;outputPreferences.refresh()
    }
    func closeOutputPreferences(returnFocus:Bool=true){outputPreferences.cancel();outputPreferencesOpen=false;if returnFocus{focusCanvas?()}}
}

struct OutputPreferencesView:View {
    @ObservedObject var store:AppStore
    @ObservedObject var preferences:OutputPreferences
    @StateObject private var keyboard=OutputPreferencesFocus()
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                Text("출력 설정").font(.system(size:18,weight:.semibold))
                Spacer()
                OutputPreferenceButton(title:"닫기",order:2,keyboard:keyboard){store.closeOutputPreferences()}.frame(width:60,height:28)
            }
            Text("곡 재생 출력 · 미리듣기·녹음 별도").foregroundStyle(StudioTheme.secondary)
            HStack(spacing:12) {
                Text("출력 장치")
                OutputPreferencePicker(preferences:preferences,keyboard:keyboard).frame(height:28)
            }
            if let name=preferences.defaultName {Text("현재 시스템 기본값: "+name).foregroundStyle(StudioTheme.secondary)}
            if preferences.missing {
                Text("저장된 장치를 찾을 수 없습니다. 선택은 유지되며 다른 장치로 자동 대체하지 않습니다.").foregroundStyle(.orange)
            }
            if let message=preferences.message {Text(message).foregroundStyle(.orange)}
            HStack {
                if preferences.loading {
                    ProgressView().controlSize(.small)
                    Text("출력 장치 조회 중 · 최대 5초")
                }else{
                    Text(preferences.catalog?.devices.isEmpty == true ? "사용 가능한 출력 장치가 없습니다":"선택: "+preferences.selectedName).lineLimit(2)
                }
                Spacer()
                OutputPreferenceButton(title:preferences.loading ? "조회 취소":"다시 조회",order:1,keyboard:keyboard){
                    if preferences.loading{preferences.cancel()}else{preferences.refresh()}
                }.frame(width:90,height:28)
            }
            Divider()
            Text("변경한 설정은 다음 재생부터 적용됩니다. 현재 재생은 바뀌지 않습니다.")
            Text(store.outputDeviceConfirmation).foregroundStyle(StudioTheme.secondary)
            Text("시스템 기본 출력은 변경하지 않습니다.").foregroundStyle(StudioTheme.secondary)
        }
        .padding(22).frame(width:540)
        .background(StudioTheme.surface,in:RoundedRectangle(cornerRadius:10))
        .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(StudioTheme.line))
        .background(OutputPreferencesKeys(keyboard:keyboard,active:{store.outputPreferencesOpen},close:{store.closeOutputPreferences()}).frame(width:0,height:0))
        .onExitCommand{store.closeOutputPreferences()}
    }
}

/// Explicit focus order is independent of the macOS keyboard-navigation preference.
@MainActor private final class OutputPreferencesFocus:ObservableObject {
    private final class Entry {weak var view:NSView?;init(_ view:NSView){self.view=view}}
    private var controls:[Int:Entry]=[:]
    func register(_ view:NSView,order:Int){controls[order]=Entry(view)}
    func first(in window:NSWindow){if let view=controls[0]?.view,view.window===window{window.makeFirstResponder(view)}}
    func move(in window:NSWindow,backward:Bool) {
        let views=controls.sorted{$0.key<$1.key}.compactMap{$0.value.view}.filter{$0.window===window && !$0.isHidden}
        guard !views.isEmpty else{return}
        let current=views.firstIndex{window.firstResponder === $0}
        let next=current.map{($0+(backward ? views.count-1:1))%views.count} ?? (backward ? views.count-1:0)
        window.makeFirstResponder(views[next])
    }
}

private struct OutputPreferencesKeys:NSViewRepresentable {
    let keyboard:OutputPreferencesFocus
    let active:()->Bool
    let close:()->Void
    func makeNSView(context:Context)->Control {let view=Control();view.keyboard=keyboard;view.active=active;view.close=close;return view}
    func updateNSView(_ view:Control,context:Context){view.active=active;view.close=close}
    static func dismantleNSView(_ view:Control,coordinator:()){view.removeMonitor()}
    final class Control:NSView {
        var keyboard:OutputPreferencesFocus?
        var active:(()->Bool)?
        var close:(()->Void)?
        private var monitor:Any?
        func removeMonitor(){if let monitor{NSEvent.removeMonitor(monitor)};monitor=nil}
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow();removeMonitor()
            guard let window else{return}
            monitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown){[weak self] event in
                guard let self,let window=self.window,event.window===window,self.active?()==true else{return event}
                let flags=event.modifierFlags.intersection([.command,.control,.option,.shift])
                if event.keyCode==53,flags.isEmpty{self.close?();return nil}
                if event.keyCode==48,flags.isEmpty || flags == .shift{self.keyboard?.move(in:window,backward:flags == .shift);return nil}
                return event
            }
            DispatchQueue.main.async{[weak self,weak window] in
                guard let self,let window,self.window===window,self.active?()==true else{return}
                self.keyboard?.first(in:window)
            }
        }
    }
}

private struct OutputPreferencePicker:NSViewRepresentable {
    @ObservedObject var preferences:OutputPreferences
    let keyboard:OutputPreferencesFocus
    func makeCoordinator()->Coordinator{Coordinator(preferences)}
    func makeNSView(context:Context)->Control {
        let view=Control(frame:.zero,pullsDown:false)
        view.target=context.coordinator;view.action=#selector(Coordinator.changed(_:));view.controlSize = .regular
        view.setAccessibilityLabel("출력 장치");view.setAccessibilityIdentifier("output-preferences-device")
        keyboard.register(view,order:0);return view
    }
    func updateNSView(_ view:Control,context:Context) {
        var items:[(String,String)]=[("","시스템 기본값")]
        if let uid=preferences.selectedUID,preferences.catalog?.devices.contains(where:{$0.uid==uid}) != true {
            items.append((uid,preferences.missing ? "저장된 출력 장치 · 미연결":"저장된 출력 장치 · 확인 전"))
        }
        items += (preferences.catalog?.devices ?? []).map{($0.uid,$0.name)}
        let keys=items.map{$0.0},titles=items.map{$0.1}
        if context.coordinator.keys != keys || view.itemTitles != titles {
            view.removeAllItems()
            for title in titles{view.menu?.addItem(NSMenuItem(title:title,action:nil,keyEquivalent:""))}
            context.coordinator.keys=keys
        }
        if let index=keys.firstIndex(of:preferences.selectedUID ?? ""){view.selectItem(at:index)}
        keyboard.register(view,order:0)
    }
    final class Control:NSPopUpButton {override var acceptsFirstResponder:Bool{true}}
    @MainActor final class Coordinator:NSObject {
        let preferences:OutputPreferences
        var keys:[String]=[]
        init(_ preferences:OutputPreferences){self.preferences=preferences}
        @objc func changed(_ sender:NSPopUpButton){guard keys.indices.contains(sender.indexOfSelectedItem) else{return};let uid=keys[sender.indexOfSelectedItem];preferences.choose(uid.isEmpty ? nil:uid)}
    }
}

private struct OutputPreferenceButton:NSViewRepresentable {
    let title:String
    let order:Int
    let keyboard:OutputPreferencesFocus
    let action:()->Void
    func makeCoordinator()->Coordinator{Coordinator(action)}
    func makeNSView(context:Context)->Control {
        let view=Control(title:title,target:context.coordinator,action:#selector(Coordinator.invokeAction))
        view.bezelStyle = .rounded;keyboard.register(view,order:order);return view
    }
    func updateNSView(_ view:Control,context:Context){view.title=title;context.coordinator.action=action;keyboard.register(view,order:order)}
    final class Control:NSButton {
        override var acceptsFirstResponder:Bool{true}
        override func keyDown(with event:NSEvent) {
            if [UInt16(36),49,76].contains(event.keyCode),event.modifierFlags.intersection([.command,.control,.option]).isEmpty{performClick(nil);return}
            super.keyDown(with:event)
        }
    }
    @MainActor final class Coordinator:NSObject {
        var action:()->Void
        init(_ action:@escaping()->Void){self.action=action}
        @objc func invokeAction(){action()}
    }
}
