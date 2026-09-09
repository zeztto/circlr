import SwiftUI
import AppKit
import CirclrCore

/// UI save/replace actions resolve the focused name; background MCP save keeps committed data only.
final class NameEditingRegistry {
    private var owner:UUID?
    private var resolver:(()->Bool)?
    func activate(_ id:UUID,resolve:@escaping ()->Bool) {owner=id;resolver=resolve}
    func deactivate(_ id:UUID) {if owner==id {owner=nil;resolver=nil}}
    func resolve()->Bool {resolver?() ?? true}
}

/// Names share the live project/session/target guard used by numeric editing.
struct CommittedNameField:View {
    let title:String
    @Binding var value:String
    var fontSize:CGFloat=17
    var weight:NSFont.Weight = .semibold
    var focus:Binding<Bool>?=nil
    var message:(String)->Void={_ in}
    @Environment(\.numberEditing) private var context
    @State private var error=""
    @State private var editing=false
    var body:some View {
        HStack(spacing:4) {
            NativeNameField(title:title,value:$value,fontSize:fontSize,weight:weight,focus:focus,context:context,
                            error:$error,editing:$editing,message:message)
            if !error.isEmpty {
                Image(systemName:"exclamationmark.circle.fill").font(.system(size:11)).foregroundStyle(Color.red)
                    .help(error).accessibilityLabel(error)
            }
        }.frame(height:fontSize+7).padding(.vertical,2)
            .overlay(alignment:.bottom) {Rectangle().fill(error.isEmpty ? (editing ? StudioTheme.accent:Color.clear):Color.red).frame(height:1)}
    }
}

private struct NativeNameField:NSViewRepresentable {
    let title:String
    @Binding var value:String
    let fontSize:CGFloat
    let weight:NSFont.Weight
    let focus:Binding<Bool>?
    let context:NumberEditingContext
    @Binding var error:String
    @Binding var editing:Bool
    let message:(String)->Void
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator()->Coordinator {Coordinator(self)}
    func makeNSView(context:Context)->Control {
        let field=Control(),coordinator=context.coordinator
        coordinator.field=field
        field.isBordered=false;field.drawsBackground=false;field.focusRingType = .none
        field.usesSingleLineMode=true;field.cell?.wraps=false;field.cell?.isScrollable=true
        field.delegate=coordinator;field.began={ [weak coordinator] in coordinator?.begin() }
        field.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        updateNSView(field,context:context);return field
    }
    func updateNSView(_ field:Control,context:Context) {
        let coordinator=context.coordinator,changed=coordinator.targetChanged(to:self.context.beforeTyping())
        if changed {coordinator.parent.context.names?.deactivate(coordinator.id)}
        coordinator.parent=self
        if changed {
            let discarded=coordinator.draft.isDirty
            coordinator.draft.reset(value:value);coordinator.owner=nil;coordinator.active=false
            field.abortEditing()
            DispatchQueue.main.async { [weak coordinator] in
                guard let coordinator,coordinator.mounted else{return}
                coordinator.parent.editing=false;coordinator.parent.focus?.wrappedValue=false;coordinator.parent.error=""
                if discarded {coordinator.parent.message("대상이 바뀌어 이름 입력을 취소했습니다")}
            }
        }
        if (field.currentEditor() as? NSTextView)?.hasMarkedText() != true {
            coordinator.draft.refresh(value:value,context:self.context.beforeTyping(),editing:coordinator.active || coordinator.draft.isDirty)
            if field.stringValue != coordinator.draft.text {field.stringValue=coordinator.draft.text}
        }
        field.font = .systemFont(ofSize:fontSize,weight:weight);field.textColor=error.isEmpty ? StudioTheme.textNS:.systemRed
        field.isEnabled=isEnabled;field.placeholderString=title
        field.setAccessibilityLabel(title)
        field.setAccessibilityHelp(error.isEmpty ? "Return·Tab으로 적용 · Esc로 취소":error)
        field.toolTip=error.isEmpty ? value+"\nReturn·Tab으로 적용 · Esc로 취소":error
        if focus?.wrappedValue==true,!coordinator.active {
            DispatchQueue.main.async { [weak coordinator,weak field] in
                guard let coordinator,coordinator.mounted,coordinator.parent.focus?.wrappedValue==true,
                      let field,field.isEnabled,let window=field.window,!coordinator.active else{return}
                if window.makeFirstResponder(field) {field.selectText(nil)}
            }
        }
    }
    static func dismantleNSView(_ field:Control,coordinator:Coordinator) {
        coordinator.mounted=false
        coordinator.parent.context.names?.deactivate(coordinator.id)
        let discarded=coordinator.draft.isDirty,message=coordinator.parent.message
        coordinator.draft.reset(value:coordinator.parent.value);field.delegate=nil;field.began=nil
        if discarded {DispatchQueue.main.async{message("편집 화면이 바뀌어 이름 입력을 취소했습니다")}}
    }
    final class Coordinator:NSObject,NSTextFieldDelegate {
        var parent:NativeNameField
        var draft=NameEditSession<NumberEditIdentity?>()
        var owner:NumberEditIdentity?
        var active=false,mounted=true
        weak var field:Control?
        let id=UUID()
        init(_ parent:NativeNameField) {self.parent=parent;draft.reset(value:parent.value)}
        func targetChanged(to next:NumberEditIdentity?)->Bool {
            guard draft.hasBaseline else{return false}
            var expected=owner
            if let revision=next?.revision {expected?.revision=revision}
            return expected != next
        }
        func begin() {
            active=true
            if !draft.isDirty {owner=parent.context.beforeTyping();draft.begin(value:parent.value,context:owner);parent.error=""}
            register()
            parent.editing=true;parent.focus?.wrappedValue=true
        }
        func register() {parent.context.names?.activate(id) { [weak self] in self?.commit() ?? true }}
        func controlTextDidChange(_ notification:Notification) {
            guard mounted,let field=notification.object as? NSTextField else{return}
            register()
            if !draft.hasBaseline {owner=parent.context.beforeTyping()}
            draft.type(field.stringValue,value:parent.value,context:owner);parent.error=""
        }
        func control(_ control:NSControl,textShouldEndEditing fieldEditor:NSText)->Bool {
            if let editor=fieldEditor as? NSTextView,editor.hasMarkedText() {return false}
            _=commit();return true
        }
        func controlTextDidEndEditing(_ notification:Notification) {
            guard mounted else{return}
            active=false;parent.editing=false;parent.focus?.wrappedValue=false
            if !draft.isDirty {parent.context.names?.deactivate(id)}
        }
        func control(_ control:NSControl,textView:NSTextView,doCommandBy command:Selector)->Bool {
            if textView.hasMarkedText() {return false}
            if command == #selector(NSResponder.cancelOperation(_:)) {
                draft.reset(value:parent.value);parent.error="";field?.stringValue=draft.text
                parent.context.names?.deactivate(id)
                finishFocus(control);return true
            }
            if command == #selector(NSResponder.insertNewline(_:)) {
                if commit() {finishFocus(control)}
                return true
            }
            if command == #selector(NSResponder.insertTab(_:)) || command == #selector(NSResponder.insertBacktab(_:)) {
                return !commit()
            }
            return false
        }
        func finishFocus(_ control:NSControl) {
            parent.focus?.wrappedValue=false
            control.window?.makeFirstResponder(nil)
            if control.window?.identifier?.rawValue=="main" {parent.context.focusCanvas()}
        }
        @discardableResult func commit()->Bool {
            guard mounted else{return false}
            do {
                let composing=(field?.currentEditor() as? NSTextView)?.hasMarkedText() ?? false
                let resolved=try draft.resolve(value:parent.value,context:parent.context.current(),isComposing:composing)
                switch resolved {
                case .composing:return false
                case .unchanged:draft.reset(value:parent.value)
                case .apply(let name):
                    let pending=draft
                    draft.reset(value:name);parent.value=name
                    guard parent.value==name else {
                        draft=pending
                        throw CirclrError("이름을 적용하지 못했습니다. 현재 작업을 마친 뒤 다시 시도하세요")
                    }
                }
                parent.error=""
                parent.context.names?.deactivate(id)
                if field?.stringValue != draft.text {field?.stringValue=draft.text}
                return true
            }catch{parent.error=error.localizedDescription;parent.message(error.localizedDescription);return false}
        }
    }
    final class Control:NSTextField {
        var began:(()->Void)?
        override func becomeFirstResponder()->Bool {
            let result=super.becomeFirstResponder();if result {began?()};return result
        }
    }
}
