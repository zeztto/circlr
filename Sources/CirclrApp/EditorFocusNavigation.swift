import AppKit
import SwiftUI
import CirclrCore

@MainActor final class EditorFocusRequest {
    let id=UUID()
    let identity:NumberEditIdentity
    let page:StudioWorkspace.Page
    let steps:Bool
    let orbits:Bool
    weak var responder:NSResponder?
    weak var fieldEditorOwner:AnyObject?
    let usedFieldEditor:Bool
    let responderText:String?
    init(store:AppStore) {
        identity=store.numberEditIdentity;page=store.capturedStudioWorkspace.page
        steps=store.midiStepMode;orbits=store.project.usesOrbits
        let currentResponder=NSApp.keyWindow?.firstResponder
        responder=currentResponder
        let fieldEditor=currentResponder as? NSTextView
        responderText=fieldEditor?.string
        let isFieldEditor=fieldEditor?.isFieldEditor == true
        usedFieldEditor=isFieldEditor
        fieldEditorOwner=isFieldEditor ? fieldEditor?.delegate:nil
    }
}

extension AppStore {
    /// An attached native view may satisfy an explicit request, never invent one.
    func fulfillEditorFocusWhenMounted(_ view:NSView) {
        guard let id=editorFocusRequest?.id else{return}
        DispatchQueue.main.async { [weak self,weak view] in
            guard let self,let view,view.window != nil,self.editorFocusRequest?.id==id else{return}
            var parent:NSView?=view
            while let current=parent {
                if let host=current as? NSHostingView<InlineCircleEditor> {
                    self.consumeEditorNavigationFocus(in:host);return
                }
                parent=current.superview
            }
        }
    }
    func requestEditorNavigationFocus() {
        guard selectedMusic != nil,!hierarchySettingsOpen,!connectionsOpen,hierarchyTransitionID==nil,
              midiImportDraft==nil,embeddedPlugin==nil else{editorFocusRequest=nil;return}
        editorFocusRequest=EditorFocusRequest(store:self)
    }
    func consumeEditorNavigationFocus(in editor:NSView,finalAttempt:Bool=false) {
        guard let request=editorFocusRequest else{return}
        guard request.identity==numberEditIdentity,request.page==capturedStudioWorkspace.page,
              request.steps==midiStepMode,request.orbits==project.usesOrbits else{editorFocusRequest=nil;return}
        guard !navigationOpen,commandPalette==nil,!keyboardHelp,!libraryOpen,!outputPreferencesOpen,
              soundPickerRequest==nil,arrangementPickerRequest==nil,NSApp.modalWindow==nil else {
            editorFocusRequest=nil;return
        }
        // Initial saved-workspace restoration can precede the host's window mount.
        // Attachment will retry the same request; no other window receives focus.
        guard let window=editor.window else{return}
        guard let keyWindow=NSApp.keyWindow else{return}
        guard window===keyWindow else{editorFocusRequest=nil;return}
        func matches(_ view:NSView)->Bool {
            guard !view.isHiddenOrHasHiddenAncestor,view.window===window else{return false}
            switch request.page {
            case .pitchBend:return view is PitchBendPlotView
            case .sustain:return view is SustainPlotView
            case .automation:return view is AutomationPlotView
            case .content:
                switch selectedMusic?.content {
                case .audio,.rhythmAudio:
                    // The current audio workspace uses OrbitAudioView in both canvas layouts.
                    return (view as? OrbitAudioView)?.isCurrent == true
                case .midi,.rhythmMIDI:
                    if request.steps {return view is StepGridView}
                    return request.orbits ? view is OrbitMIDIView:view is PianoRollView
                default:return false
                }
            default:return false
            }
        }
        func find(_ view:NSView)->NSView? {
            if matches(view){return view}
            for child in view.subviews {if let target=find(child){return target}}
            return nil
        }
        let responder=window.firstResponder
        if responder===request.responder,let text=responder as? NSTextView {
            // A user can resume typing into the same owner while the camera opens.
            // Inspect only; a delayed focus request must never commit fresh input.
            guard !text.hasMarkedText(),text.string==request.responderText else{editorFocusRequest=nil;return}
            if hasUnresolvedNumericDraft(in:text) {editorFocusRequest=nil;return}
        }
        // AppKit reuses one field editor for search and numeric controls.
        // Pointer equality alone must not authorize stealing a new owner's input.
        if responder===request.responder,request.usedFieldEditor {
            guard let fieldEditor=responder as? NSTextView,fieldEditor.isFieldEditor,
                  let owner=request.fieldEditorOwner,fieldEditor.delegate===owner else {
                editorFocusRequest=nil;return
            }
        }
        guard responder==nil || responder===request.responder || responder===window || responder===window.contentView ||
              responder is AlbumCanvasView || (responder as? NSView).map(matches)==true else {
            editorFocusRequest=nil;return
        }
        if let target=find(editor) {
            editorFocusRequest=nil
            _=window.makeFirstResponder(target)
        } else if finalAttempt {
            // Shared clips replace the inner view while retaining the same host.
            // A still-current request must wait for that clip's mount, never be
            // consumed by the outgoing clip or cancelled in the replacement gap.
            let awaitingAudio:Bool
            switch selectedMusic?.content {
            case .audio,.rhythmAudio:awaitingAudio=request.page == .content && currentAudioClip != nil
            default:awaitingAudio=false
            }
            // The pedal subtree can mount after the enclosing attachment.
            // Keep only the existing request; identity/input guards still run on retry.
            let awaitingSustain=request.page == .sustain && sustainOpen && currentLane != nil
            if !awaitingAudio && !awaitingSustain {editorFocusRequest=nil}
        }
    }
}

/// Reacts to the actual SwiftUI subtree mount/update, without a duration-based focus timer.
struct EditorFocusNavigationAttachment:NSViewRepresentable {
    @ObservedObject var store:AppStore
    func makeNSView(context:Context)->Attachment {Attachment()}
    func updateNSView(_ view:Attachment,context:Context) {view.store=store;view.schedule()}
    final class Attachment:NSView {
        weak var store:AppStore?
        var scheduled:UUID?
        var keyWindowObserver:NSObjectProtocol?
        var keyMonitor:Any?
        deinit {
            if let keyWindowObserver {NotificationCenter.default.removeObserver(keyWindowObserver)}
            if let keyMonitor {NSEvent.removeMonitor(keyMonitor)}
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let keyWindowObserver {NotificationCenter.default.removeObserver(keyWindowObserver);self.keyWindowObserver=nil}
            if let keyMonitor {NSEvent.removeMonitor(keyMonitor);self.keyMonitor=nil}
            if let window {
                // A key can arrive before the async mount callback. Complete the
                // existing request at the dispatch boundary so that this very key
                // reaches the new editor, with the same identity and draft guards.
                // Never queue or replay input after another mode/window takes over.
                keyMonitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
                    guard let self,event.window===self.window,self.window?.isKeyWindow==true,
                          let store=self.store,store.editorFocusRequest != nil else{return event}
                    self.consumePendingFocus(store:store,finalAttempt:false)
                    return event
                }
                keyWindowObserver=NotificationCenter.default.addObserver(forName:NSWindow.didBecomeKeyNotification,object:window,queue:.main) { [weak self] _ in
                    MainActor.assumeIsolated {self?.schedule(retryExisting:true)}
                }
            }
            schedule(retryExisting:window != nil)
        }
        func schedule(retryExisting:Bool=false) {
            guard let id=store?.editorFocusRequest?.id,retryExisting || scheduled != id else{return}
            scheduled=id
            DispatchQueue.main.async { [weak self] in
                guard let self,let store=self.store,store.editorFocusRequest?.id==id,self.window != nil else{return}
                self.consumePendingFocus(store:store,finalAttempt:true)
            }
        }
        private func consumePendingFocus(store:AppStore,finalAttempt:Bool) {
            guard let id=store.editorFocusRequest?.id,let window else{return}
            var parent=self.superview
            while let view=parent {
                if let host=view as? NSHostingView<InlineCircleEditor> {
                    host.layoutSubtreeIfNeeded()
                    guard host.window===window,store.editorFocusRequest?.id==id else{return}
                    store.consumeEditorNavigationFocus(in:host,finalAttempt:finalAttempt);return
                }
                parent=view.superview
            }
        }
    }
}
