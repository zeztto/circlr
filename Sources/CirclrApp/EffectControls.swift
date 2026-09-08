import SwiftUI
import AppKit
import CirclrCore

struct EffectControls: View {
    @Binding var effect: Effect
    var allowsAU = false
    var isCurrent: () -> Bool = {true}
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StudioChoice("효과", selection: Binding(get: {effect.kind}, set: {kind in
                guard isCurrent() else {return}; var next=effect; next.kind=kind; effect=next
            }), options: EffectKind.allCases.filter {allowsAU || $0 != .audioUnit}.map {($0,AppStore.effectName($0))})
            EffectParameterFields(effect:$effect) {expected,next in
                guard isCurrent(),effect==expected else{return false}
                if next != effect {effect=next}
                return effect==next
            }.id(effect.kind)
        }.frame(maxWidth:660,alignment:.leading)
    }
}

private extension EffectParameter {
    func presentation(in effect:Effect)->NumberEditPresentation {kind == .gain && effect.amount>=0 ? .gainDecibels:.effectValue(unit:unit)}
    func displayUnit(in effect:Effect)->String {presentation(in:effect) == .gainDecibels ? "dB":unit}
    func displayHint(in effect:Effect)->String {kind == .gain ? (effect.amount<0 ? "기존 음수 게인 · 위상이 반전됩니다":"0 dB는 원래 레벨 · −∞는 무음"):hint}
    func fieldTitle(in effect:Effect)->String {title+" · "+displayUnit(in:effect)}
}

private struct EffectParameterFields:View {
    @Binding var effect:Effect
    let apply:(Effect,Effect)->Bool
    @Environment(\.numberEditing) private var context
    @State private var fieldFocus:NumberFieldFocus
    init(effect:Binding<Effect>,apply:@escaping(Effect,Effect)->Bool) {
        _effect=effect;self.apply=apply
        _fieldFocus=State(initialValue:NumberFieldFocus(EffectParameter.all(for:effect.wrappedValue.kind).map{$0.fieldTitle(in:effect.wrappedValue)}))
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            ForEach(EffectParameter.all(for:effect.kind)) {parameter in
                VStack(alignment:.leading,spacing:4) {
                    HStack(spacing:12) {
                        Text(parameter.title).frame(width:76,alignment:.leading)
                        EffectSlider(effect:effect,parameter:parameter) {expected,value in
                            guard let next=try? parameter.applying(value,to:expected) else{return false}
                            return apply(expected,next)
                        }.frame(minWidth:72,maxWidth:.infinity).frame(height:28)
                        CommittedNumberField(title:parameter.fieldTitle(in:effect),value:Binding(
                            get:{parameter.value(in:effect)},set:{value in
                                let expected=effect
                                if let next=try? parameter.applying(value,to:expected){_=apply(expected,next)}
                            }),range:parameter.range,width:110,presentation:parameter.presentation(in:effect))
                        Text(parameter.displayUnit(in:effect)).foregroundStyle(StudioTheme.secondary).frame(width:28,alignment:.leading)
                    }
                    if !parameter.displayHint(in:effect).isEmpty {Text(parameter.displayHint(in:effect)).font(.system(size:12)).foregroundStyle(StudioTheme.secondary)}
                }
            }
        }.environment(\.numberEditing,NumberEditingContext(snapshot:context.snapshot,current:context.current,focusCanvas:context.focusCanvas,fieldFocus:fieldFocus))
    }
}

/// AppKit sends a single action on mouse-up. Intermediate knob travel never creates music Undo.
private struct EffectSlider: NSViewRepresentable {
    let effect: Effect
    let parameter: EffectParameter
    let apply: (Effect,Double) -> Bool
    func makeCoordinator() -> Coordinator {Coordinator(self)}
    func makeNSView(context: Context) -> Control {
        let slider=Control();slider.minValue=0;slider.maxValue=1;slider.isContinuous=false
        slider.target=context.coordinator;slider.action=#selector(Coordinator.changed(_:))
        slider.began={ [weak coordinator=context.coordinator] in coordinator?.baseline=coordinator?.parent.effect }
        slider.appearance=NSAppearance(named:.darkAqua)
        updateNSView(slider,context:context);return slider
    }
    func updateNSView(_ slider: Control, context: Context) {
        context.coordinator.parent=self
        if !slider.tracking {slider.doubleValue=parameter.sliderPosition(in:effect)}
        slider.setAccessibilityLabel(parameter.title+" 슬라이더 · "+parameter.displayUnit(in:effect))
        let display=parameter.presentation(in:effect) == .gainDecibels ? GainScale.text(parameter.value(in:effect)):parameter.value(in:effect).formatted(.number.precision(.fractionLength(0...3)))
        slider.setAccessibilityValueDescription(display+" "+parameter.displayUnit(in:effect))
        slider.toolTip="좌우 방향키로 조절 · 드래그를 놓으면 적용"
    }
    final class Coordinator: NSObject {
        var parent: EffectSlider
        var baseline: Effect?
        init(_ parent: EffectSlider) {self.parent=parent}
        @objc func changed(_ sender: Control) {
            guard !sender.tracking else {return}
            let expected=baseline ?? parent.effect
            if !parent.apply(expected,parent.parameter.value(at:sender.doubleValue)) {sender.doubleValue=parent.parameter.sliderPosition(in:parent.effect)}
            baseline=nil
        }
    }
    final class Control: NSSlider {
        var began: (() -> Void)?
        var tracking=false
        override var acceptsFirstResponder: Bool {true}
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {true}
        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self);tracking=true;began?();super.mouseDown(with:event);tracking=false
            sendAction(action,to:target)
        }
        override func keyDown(with event: NSEvent) {
            guard !event.modifierFlags.contains(.command),!event.modifierFlags.contains(.control),[123,124,125,126].contains(event.keyCode) else {super.keyDown(with:event);return}
            began?()
            let delta=event.modifierFlags.contains(.option) ? 0.001:event.modifierFlags.contains(.shift) ? 0.1:0.01
            doubleValue=min(maxValue,max(minValue,doubleValue+(event.keyCode==123 || event.keyCode==125 ? -delta:delta)))
            sendAction(action,to:target)
        }
    }
}
