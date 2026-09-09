import AppKit
import SwiftUI
import CirclrCore
import CirclrAudio

extension AppStore {
    var bounceTailNotice:String? {
        if let error=bounceTailAssessmentError{return error}
        return bounceTailAssessment?.notices.first
    }
    var bounceTailUIAvailable:Bool {
        !trackBounceRecoveryLocked && !libraryOpen && !navigationOpen && commandPalette==nil && !keyboardHelp &&
        soundPickerRequest==nil && arrangementPickerRequest==nil && NSApp.modalWindow==nil && NSApp.keyWindow?.attachedSheet==nil
    }
    func beginBounceTailEditing(identity:NumberEditIdentity) {
        guard bounceTailUIAvailable,nameEditing.resolve(),numberEditIdentity==identity else{return}
        if selectedMusic==nil || audioIsOutsideSharedOriginal {
            guard let use=selectedUse,let output=trackBounceAssessment?.target?.outputNodeID else{return}
            navigateStudio(.music(arrangementID:project.activeArrangementID,useID:use.id,nodeID:output),track:selectedTrackID)
        }
        connectionsOpen=false;hierarchySettingsOpen=false;automationOpen=false;embeddedPlugin=nil;hierarchyTransitionID=nil
        if let address=hierarchySelection {focusHierarchy(address,detail:true)}
        bounceTailEditing=true
    }
    func applyBounceTailSetting(_ seconds:Double?,identity:NumberEditIdentity)->Bool {
        guard bounceTailUIAvailable,nameEditing.resolve() else{return false}
        do {try setBounceTailSeconds(seconds,identity:identity);bounceTailEditing=false;focusCanvas?();return true}
        catch{status=error.localizedDescription;return false}
    }
    func runCurrentTrackBounce(identity:NumberEditIdentity) {
        guard bounceTailUIAvailable,!bounceTailEditing,nameEditing.resolve(),numberEditIdentity==identity,
              trackBounceIssue==nil,bounceTailAssessment != nil else{return}
        bounceTrack()
    }
}

struct BounceTailControl:View {
    @ObservedObject var store:AppStore
    private var label:String {
        guard let tail=store.bounceTailAssessment else{return "여운 확인"}
        let prefix=tail.requestedSeconds != nil ? "직접":tail.estimatedSeconds>tail.effectiveSeconds ? "상한":"자동"
        return prefix+String(format:" %.1f초",tail.effectiveSeconds)
    }
    private var detail:String {
        guard let tail=store.bounceTailAssessment else{return store.bounceTailAssessmentError ?? "바운스 여운을 확인하세요"}
        return (["추가 여운 "+String(format:"%.2f초",tail.effectiveSeconds),"직접 지정 범위 0–120초"]+tail.notices).joined(separator:" · ")
    }
    var body:some View {
        let identity=store.numberEditIdentity
        if store.bounceTailEditing {
            HStack(spacing:2) {
                BounceTailNumberField(value:store.bounceTailSeconds ?? store.bounceTailAssessment?.effectiveSeconds ?? 0,identity:identity,
                    submit:{value,snapshot in store.applyBounceTailSetting(value,identity:snapshot)},
                    cancel:{store.bounceTailEditing=false;store.focusCanvas?()})
                    .frame(width:54,height:26).accessibilityLabel("바운스 여운 초")
                Text("초").font(.system(size:11))
                Button{store.bounceTailEditing=false;store.focusCanvas?()}label:{Image(systemName:"xmark")}
                    .buttonStyle(.plain).help("여운 입력 취소 · Esc").accessibilityLabel("여운 입력 취소")
            }.help("0–120초 · Return 설정 적용 · Esc 취소 · 설정만으로 바운스를 시작하지 않습니다")
        }else{
            Menu {
                Button("자동 추정") {_ = store.applyBounceTailSetting(nil,identity:identity)}
                Button("직접 지정…") {store.beginBounceTailEditing(identity:identity)}
            }label:{Text(label).font(.system(size:11)).lineLimit(1)}
                .menuStyle(.borderlessButton).help(detail).accessibilityLabel("바운스 여운 · "+label+" · "+detail)
                .disabled(!store.bounceTailUIAvailable)
        }
    }
}

private struct BounceTailNumberField:NSViewRepresentable {
    let value:Double
    let identity:NumberEditIdentity
    let submit:(Double,NumberEditIdentity)->Bool
    let cancel:()->Void
    func makeCoordinator()->Coordinator {Coordinator(self)}
    func makeNSView(context:Context)->NSTextField {
        let field=NSTextField(string:String(format:"%.2f",value));field.font = .monospacedDigitSystemFont(ofSize:12,weight:.regular)
        field.alignment = .right;field.delegate=context.coordinator
        DispatchQueue.main.async{field.window?.makeFirstResponder(field)}
        return field
    }
    func updateNSView(_ field:NSTextField,context:Context) {context.coordinator.parent=self}
    final class Coordinator:NSObject,NSTextFieldDelegate {
        var parent:BounceTailNumberField
        let identity:NumberEditIdentity
        init(_ parent:BounceTailNumberField){self.parent=parent;identity=parent.identity}
        func control(_ control:NSControl,textView:NSTextView,doCommandBy selector:Selector)->Bool {
            if textView.hasMarkedText(){return false}
            if selector==#selector(NSResponder.cancelOperation(_:)){parent.cancel();return true}
            if selector==#selector(NSResponder.insertNewline(_:)) || selector==#selector(NSResponder.insertTab(_:)) {
                guard let field=control as? NSTextField else{return true}
                guard let value=Double(field.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)),value.isFinite,(0...120).contains(value) else {
                    field.textColor = .systemRed;field.toolTip="여운은 0–120초로 입력하세요";NSSound.beep();return true
                }
                if !parent.submit(value,identity) {field.textColor = .systemRed}
                return true
            }
            return false
        }
        func controlTextDidChange(_ notification:Notification) {(notification.object as? NSTextField)?.textColor = .labelColor}
    }
}
