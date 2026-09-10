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
    init(store:AppStore) {
        identity=store.numberEditIdentity;page=store.capturedStudioWorkspace.page
        steps=store.midiStepMode;orbits=store.project.usesOrbits
        let currentResponder=NSApp.keyWindow?.firstResponder
        responder=currentResponder
        let fieldEditor=currentResponder as? NSTextView
        let isFieldEditor=fieldEditor?.isFieldEditor == true
        usedFieldEditor=isFieldEditor
        fieldEditorOwner=isFieldEditor ? fieldEditor?.delegate:nil
    }
}

extension AppStore {
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
              soundPickerRequest==nil,arrangementPickerRequest==nil,
              let window=editor.window,window===NSApp.keyWindow,NSApp.modalWindow==nil else {
            editorFocusRequest=nil;return
        }
        func matches(_ view:NSView)->Bool {
            guard !view.isHiddenOrHasHiddenAncestor,view.window===window else{return false}
            switch request.page {
            case .pitchBend:return view is PitchBendPlotView
            case .automation:return view is AutomationPlotView
            case .content:
                switch selectedMusic?.content {
                case .audio,.rhythmAudio:
                    // The current audio workspace uses OrbitAudioView in both canvas layouts.
                    return view is OrbitAudioView || view is AudioLaneView
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
        } else if finalAttempt {editorFocusRequest=nil}
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
        override func viewDidMoveToWindow(){super.viewDidMoveToWindow();schedule()}
        func schedule() {
            guard let id=store?.editorFocusRequest?.id,scheduled != id else{return}
            scheduled=id
            DispatchQueue.main.async { [weak self] in
                guard let self,let store=self.store,store.editorFocusRequest?.id==id,let window=self.window else{return}
                var parent=self.superview
                while let view=parent {
                    if let host=view as? NSHostingView<InlineCircleEditor> {
                        host.layoutSubtreeIfNeeded()
                        guard host.window===window else{return}
                        store.consumeEditorNavigationFocus(in:host,finalAttempt:true);return
                    }
                    parent=view.superview
                }
            }
        }
    }
}
