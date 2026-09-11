import AppKit
import SwiftUI
import CirclrCore
import Combine

@MainActor extension AppStore {
    /// A transient presentation mode. Explicit agent edits remain allowed; this is not a document lock.
    @discardableResult func setViewingMode(_ enabled:Bool)->Bool {
        guard enabled != viewingMode else{return true}
        if enabled {
            guard !startupOpen,errorMessage == nil,!outputPreferencesOpen,!libraryOpen,!navigationOpen,
                  soundPickerRequest == nil,arrangementPickerRequest == nil,midiImportDraft == nil else {
                status="열린 설정·가져오기 작업을 마친 뒤 감상 모드를 시작하세요";return false
            }
            // AppKit's marked text must remain visible and owned by its input field.
            if let input=NSApp.keyWindow?.firstResponder as? NSTextView,input.hasMarkedText(){return false}
            var identity=numberEditIdentity
            guard resolveActiveNumericDraft(),nameEditing.resolve() else{return false}
            identity.revision=project.musicRevision
            guard identity==numberEditIdentity else{return false}
            commandPalette=nil
        }
        viewingMode=enabled
        viewingModeDidChange?()
        focusCanvas?()
        return true
    }
}

/// Keyboard focus keeps controls visible. The recording source is the canvas beneath this overlay.
struct ViewingModeControls:View {
    static let activity=Notification.Name("circlr.viewingModeActivity")
    @ObservedObject var store:AppStore
    @State private var lastActivity=Date()
    @State private var idle=false
    @State private var hovering=false
    @FocusState private var focused:Bool
    private let clock=Timer.publish(every:0.5,on:.main,in:.common).autoconnect()
    private var visible:Bool {!idle || hovering || focused || NSWorkspace.shared.isVoiceOverEnabled}
    var body:some View {
        HStack(spacing:12) {
            Button{store.play()}label:{Image(systemName:store.playback.playing || store.preparing ? "stop.fill":"play.fill")}
                .accessibilityLabel("재생 / 정지").focused($focused)
            Button{store.playbackFollow=store.playbackFollow.toggled()}label:{Image(systemName:store.playbackFollow == .following ? "scope":"location")}
                .accessibilityLabel("재생 팔로우 켜기 / 끄기").focused($focused)
            Button{_ = store.setViewingMode(false)}label:{Image(systemName:"eye.slash")}
                .accessibilityLabel("감상 모드 종료").focused($focused)
        }.font(.system(size:18)).padding(12)
            .background(StudioTheme.surface,in:RoundedRectangle(cornerRadius:8))
            .opacity(visible ? 1:0).allowsHitTesting(visible)
            .onHover{hovering=$0;if $0 {lastActivity=Date();idle=false}}
            .onReceive(NotificationCenter.default.publisher(for:Self.activity)){notice in
                guard let owner=notice.object as? AppStore,owner === store else{return}
                lastActivity=Date();idle=false
            }
            .onReceive(clock){now in idle=now.timeIntervalSince(lastActivity)>2.5}
    }
}

@MainActor extension AlbumCanvasView {
    func applyViewingMode() {
        if store.viewingMode {
            if normalTitleVisibility == nil {normalTitleVisibility=window?.titleVisibility}
            window?.titleVisibility = .hidden
            toolTip=nil;hoverAddress=nil;fileDropPreview=nil;labelPlacements=[]
            connecting=nil;connectionToken=nil;cableDrag=nil;orbitDrag=nil
            dragNode=nil;dragPreview=nil;dragPositions=[:];panning=false
            colorTarget=nil
            if NSColorPanel.shared.isVisible {NSColorPanel.shared.orderOut(nil)}
            // Keep mounted editor state and selection; it is hidden from drawing and hit testing.
            editor?.isHidden=true;cableTools?.isHidden=true;portTools?.isHidden=true
        } else {
            if let normalTitleVisibility {window?.titleVisibility=normalTitleVisibility}
            normalTitleVisibility=nil
            editor?.isHidden=false
            placeEditor()
        }
        updateAccessibility();needsDisplay=true
    }

    func installViewingKeyMonitor() {
        viewingKeyMonitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown){[weak self] event in
            guard let self,event.window===self.window,self.store.viewingMode else{return event}
            NotificationCenter.default.post(name:ViewingModeControls.activity,object:self.store)
            let modifiers=event.modifierFlags.intersection([.command,.control,.option,.shift])
            // App/window lifecycle and recording remain available. Everything else is explicitly routed.
            if (modifiers == .command && [12,13].contains(event.keyCode)) ||
               (modifiers == [.command,.shift] && [9,15].contains(event.keyCode)) ||
               (modifiers == [.command,.control] && event.keyCode==3) {return event}
            // Tab and activation reach the icon buttons, including VoiceOver keyboard navigation.
            if event.keyCode==48 || (event.keyCode==36 && self.window?.firstResponder !== self) ||
               modifiers.contains([.control,.option]) {return event}
            self.handleViewingKey(event);return nil
        }
    }

    func handleViewingKey(_ event:NSEvent) {
        let modifiers=event.modifierFlags.intersection([.command,.control,.option,.shift])
        if event.keyCode==53,modifiers.isEmpty {_ = store.setViewingMode(false);return}
        if event.keyCode==49,modifiers.isEmpty {store.play();return}
        if event.keyCode==3,modifiers.isEmpty {store.playbackFollow=store.playbackFollow.toggled();return}
        if [24,69,27,78].contains(event.keyCode),!modifiers.contains(.command),!modifiers.contains(.control) {
            let factor=[24,69].contains(event.keyCode) ? 1.25:0.8
            setCamera(camera.zoomed(to:camera.zoom*factor,around:Point(bounds.midX,bounds.midY)));return
        }
        if modifiers == .option,[123,124,125,126].contains(event.keyCode) {
            let x=event.keyCode==123 ? 40.0:event.keyCode==124 ? -40.0:0
            let y=event.keyCode==126 ? 40.0:event.keyCode==125 ? -40.0:0
            setCamera(HierarchyCamera(pan:Point(camera.pan.x+x,camera.pan.y+y),zoom:camera.zoom))
        }
    }
}
