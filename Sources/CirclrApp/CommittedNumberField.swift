import SwiftUI
import AppKit
import CirclrCore

struct NumberEditIdentity: Equatable {
    let projectID: ID
    var revision: Int
    let generation: Int
    let arrangementID: ID
    let circle: CircleAddress?
    let trackID: ID?
    let laneID: ID?
    let patternID: ID?
    let notes: Set<ID>
    let clipID: ID?
    let edgeID: ID?
    let transitionID: ID?
    let original: Bool
    let settings: Bool
    let steps: Bool
    let connections: Bool
    let automation: Bool
    let focus: CanvasFocus?
    let activation: UUID
    let automationPoint: ID?
    let automationParameter: AutomationParameter
}

struct NumberEditingContext {
    var snapshot: NumberEditIdentity?
    var current: () -> NumberEditIdentity? = {nil}
    var focusCanvas: () -> Void = {}
    var fieldFocus:NumberFieldFocus?
    var names:NameEditingRegistry?
    // Numeric bindings read the live model. Adopt a newer revision only before typing,
    // while preserving the displayed field's project, session and target identity.
    func beforeTyping() -> NumberEditIdentity? {
        guard var expected=snapshot,let actual=current() else {return snapshot}
        expected.revision=actual.revision
        return expected == actual ? actual:snapshot
    }
}

/// Optional explicit order for related fields beside other numeric controls.
@MainActor final class NumberFieldFocus {
    private final class WeakField {weak var value:NSTextField?;init(_ value:NSTextField){self.value=value}}
    let order:[String]
    private var fields:[String:WeakField]=[:]
    private let revealOnFocus:Bool
    init(_ order:[String],revealOnFocus:Bool=false){self.order=order;self.revealOnFocus=revealOnFocus}
    private func reveal(_ field:NSTextField) {
        guard revealOnFocus else{return}
        field.scrollToVisible(field.bounds.insetBy(dx:0,dy:-22))
    }
    func register(_ field:NSTextField,title:String){fields[title]=WeakField(field)}
    func enter(last:Bool=false,in window:NSWindow?)->Bool {
        guard let window else{return false}
        let titles=last ? Array(order.reversed()):order
        guard let field=titles.compactMap({fields[$0]?.value}).first(where:{$0.window===window && $0.isEnabled}),
              window.makeFirstResponder(field) else{return false}
        reveal(field);field.selectText(nil);return true
    }
    func move(from title:String,forward:Bool,in window:NSWindow?)->Bool {
        guard let index=order.firstIndex(of:title),order.indices.contains(index+(forward ? 1:-1)),
              let next=fields[order[index+(forward ? 1:-1)]]?.value,next.window===window,next.isEnabled,
              window?.makeFirstResponder(next)==true else{return false}
        reveal(next);next.selectText(nil);return true
    }
}
private struct NumberEditingKey: EnvironmentKey {
    static let defaultValue=NumberEditingContext()
}
extension EnvironmentValues {
    var numberEditing: NumberEditingContext {
        get {self[NumberEditingKey.self]}
        set {self[NumberEditingKey.self]=newValue}
    }
}
extension AppStore {
    var numberEditIdentity: NumberEditIdentity {
        NumberEditIdentity(projectID:project.id,revision:project.musicRevision,generation:mediaImportGeneration,
            arrangementID:project.activeArrangementID,circle:hierarchySelection,trackID:selectedTrackID,
            laneID:selectedLaneID,patternID:editPatternID,notes:selectedMIDIIDs,clipID:selectedClipID,
            edgeID:edgeSelection,transitionID:hierarchyTransitionID,original:editOriginal,
            settings:hierarchySettingsOpen,steps:midiStepMode,connections:connectionsOpen,automation:automationOpen,
            focus:focus,activation:editorActivation,automationPoint:selectedAutomationPointID,automationParameter:automationParameter)
    }
}
extension View {
    @MainActor func numberEditing(in store: AppStore) -> some View {
        environment(\.numberEditing,NumberEditingContext(snapshot:store.numberEditIdentity,current:{store.numberEditIdentity},focusCanvas:{store.focusCanvas?()},names:store.nameEditing))
    }
}

/// Every host root supplies a live context; a removed view's binding cannot edit its successor.
struct CommittedNumberField: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = -Double.greatestFiniteMagnitude...Double.greatestFiniteMagnitude
    var integerOnly=false
    var width: CGFloat=72
    var alignment: TextAlignment = .trailing
    var presentation:NumberEditPresentation = .number
    var validate:((Double)throws->Void)?
    @Environment(\.numberEditing) private var context
    @State private var error=""
    @State private var editing=false

    var body: some View {
        NativeNumberField(title:title,value:$value,range:range,integerOnly:integerOnly,alignment:alignment,presentation:presentation,validate:validate,context:context,error:$error,editing:$editing)
            .id(presentation).frame(height:18).padding(.horizontal,8).frame(width:width,height:32)
            .background(StudioTheme.raised,in:RoundedRectangle(cornerRadius:5))
            .overlay(RoundedRectangle(cornerRadius:5).strokeBorder(error.isEmpty ? (editing ? StudioTheme.accent:StudioTheme.line):Color.red,lineWidth:editing || !error.isEmpty ? 1.5:1))
            .overlay(alignment:.topTrailing) {
                if !error.isEmpty {Image(systemName:"exclamationmark.circle.fill").font(.system(size:11)).foregroundStyle(Color.red).background(StudioTheme.surface,in:Circle()).offset(x:4,y:-4).help(error).accessibilityLabel(error)}
            }
    }
}

/// Commit before AppKit transfers Tab focus, not in SwiftUI's deferred FocusState callback.
private struct NativeNumberField: NSViewRepresentable {
    let title:String
    @Binding var value:Double
    let range:ClosedRange<Double>
    let integerOnly:Bool
    let alignment:TextAlignment
    let presentation:NumberEditPresentation
    let validate:((Double)throws->Void)?
    let context:NumberEditingContext
    @Binding var error:String
    @Binding var editing:Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator {Coordinator(self)}
    func makeNSView(context:Context) -> Control {
        let field=Control()
        field.isBordered=false;field.drawsBackground=false;field.focusRingType = .none
        field.font = .monospacedDigitSystemFont(ofSize:13,weight:.regular)
        field.delegate=context.coordinator
        field.began={ [weak coordinator=context.coordinator] in coordinator?.begin() }
        field.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        updateNSView(field,context:context);return field
    }
    func updateNSView(_ field:Control,context:Context) {
        let coordinator=context.coordinator;coordinator.parent=self
        coordinator.draft.refresh(value:value,context:self.context.beforeTyping(),editing:coordinator.active || coordinator.draft.isDirty)
        // Reassigning even identical text can destroy AppKit's select-all after Tab.
        if field.stringValue != coordinator.draft.text {field.stringValue=coordinator.draft.text}
        field.alignment = alignment == .center ? .center:.right
        field.isEnabled=isEnabled
        field.textColor = error.isEmpty ? StudioTheme.textNS:.systemRed
        field.setAccessibilityLabel(title)
        let help=(presentation == .beatPosition ? "첫 위치는 1박 · 4분음표 기준 · ":"")+"Return으로 적용 · Esc로 취소"
        field.setAccessibilityHelp(error.isEmpty ? help:error)
        field.toolTip=error.isEmpty ? help:error
        self.context.fieldFocus?.register(field,title:title)
    }
    final class Coordinator:NSObject,NSTextFieldDelegate {
        var parent:NativeNumberField
        var draft:NumberEditSession<NumberEditIdentity?>
        var active=false
        init(_ parent:NativeNumberField) {self.parent=parent;draft=NumberEditSession(presentation:parent.presentation);draft.reset(value:parent.value)}
        func begin() {
            active=true;draft.begin(value:parent.value,context:parent.context.beforeTyping())
            parent.editing=true;parent.error=""
        }
        func controlTextDidChange(_ notification:Notification) {
            guard let field=notification.object as? NSTextField else {return}
            draft.type(field.stringValue,value:parent.value,context:parent.context.beforeTyping())
        }
        func control(_ control:NSControl,textShouldEndEditing fieldEditor:NSText) -> Bool {
            // This callback precedes selection of the next field. Invalid drafts may blur,
            // but are retained with an error and never reach the model.
            _=commit();return true
        }
        func controlTextDidEndEditing(_ notification:Notification) {
            active=false;parent.editing=false
        }
        func control(_ control:NSControl,textView:NSTextView,doCommandBy command:Selector) -> Bool {
            if command == #selector(NSResponder.cancelOperation(_:)) {
                draft.reset(value:parent.value);parent.error=""
                (control as? NSTextField)?.stringValue=draft.text
                finishFocus(control);return true
            }
            if command == #selector(NSResponder.insertNewline(_:)) {
                if commit() {finishFocus(control)}
                return true
            }
            if let chain=parent.context.fieldFocus,command == #selector(NSResponder.insertTab(_:)) || command == #selector(NSResponder.insertBacktab(_:)) {
                guard commit() else{return true}
                if chain.move(from:parent.title,forward:command == #selector(NSResponder.insertTab(_:)),in:control.window){return true}
            }
            return false
        }
        private func finishFocus(_ control:NSControl) {
            // Return/Esc leaves the field; ungrouped Tab follows AppKit's field order.
            // Do not transfer a separate editor/dialog's focus into another window.
            control.window?.makeFirstResponder(nil)
            if control.window?.identifier?.rawValue == "main" {parent.context.focusCanvas()}
        }
        @discardableResult func commit() -> Bool {
            do {
                let next=try draft.resolve(value:parent.value,context:parent.context.current(),range:parent.range,integerOnly:parent.integerOnly)
                if let next {try parent.validate?(next)}
                draft.reset(value:next ?? parent.value);parent.error=""
                if let next {parent.value=next}
                return true
            } catch {parent.error=error.localizedDescription;return false}
        }
    }
    final class Control:NSTextField {
        var began:(()->Void)?
        override func becomeFirstResponder() -> Bool {
            let result=super.becomeFirstResponder()
            if result {
                began?()
                // Native Tab order also reaches fields without an explicit focus registry.
                if enclosingScrollView != nil {scrollToVisible(bounds.insetBy(dx:0,dy:-22))}
            }
            return result
        }
    }
}
