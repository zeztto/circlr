import SwiftUI
import AppKit
import CirclrCore

struct EffectControls: View {
    @Binding var effect: Effect
    var allowsAU = false
    var isCurrent: () -> Bool = {true}
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StudioChoice("효과", selection: Binding(get: {effect.kind}, set: {kind in
                guard isCurrent() else {return}; var next=effect; next.kind=kind; effect=next
            }), options: EffectKind.allCases.filter {allowsAU || $0 != .audioUnit}.map {($0,AppStore.effectName($0))})
            ForEach(EffectParameter.all(for: effect.kind)) {parameter in
                EffectParameterRow(effect: effect, parameter: parameter) {expected,next in
                    guard isCurrent(),effect == expected else {return false}
                    if next != effect {effect=next}
                    return effect == next
                }
            }
        }.id(effect.kind).frame(maxWidth: 660, alignment: .leading)
    }
}

private struct EffectParameterRow: View {
    let effect: Effect
    let parameter: EffectParameter
    let apply: (Effect,Effect) -> Bool
    @State private var text = ""
    @State private var baseline: Effect?
    @State private var error = ""
    @FocusState private var editing: Bool
    private var current: Double {parameter.value(in: effect)}
    private func format(_ value: Double) -> String {
        var text=String(format:"%.3f",locale:Locale(identifier:"en_US_POSIX"),value)
        while text.last == "0" {text.removeLast()}
        if text.last == "." {text.removeLast()}
        return text == "-0" ? "0":text
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 14) {
                Text(parameter.title).frame(width: 76, alignment: .leading)
                EffectSlider(effect: effect, parameter: parameter) {expected,value in
                    commit(value, expected: expected)
                }.frame(minWidth: 100, maxWidth: .infinity).frame(height: 28)
                TextField(parameter.title, text: $text)
                    .textFieldStyle(StudioFieldStyle()).multilineTextAlignment(.trailing).monospacedDigit()
                    .frame(width: 98).focused($editing).foregroundStyle(error.isEmpty ? StudioTheme.text : Color.red)
                    .accessibilityLabel(parameter.title+" · "+parameter.unit)
                    .help("Return으로 적용 · Esc로 취소")
                    .onSubmit {if commitText() {editing=false}}
                    .onExitCommand {reset();editing=false}
                Text(parameter.unit).foregroundStyle(StudioTheme.secondary).frame(width: 28, alignment: .leading)
            }
            if !error.isEmpty {Text(error).foregroundStyle(Color.red).accessibilityLabel(error)}
            else if !parameter.hint.isEmpty {Text(parameter.hint).foregroundStyle(StudioTheme.secondary)}
        }.font(.system(size: 13))
            .onAppear {reset()}
            .onChange(of: effect) {_,_ in
                if !editing {reset()}
                else if let baseline,text == format(parameter.value(in:baseline)),error.isEmpty {
                    // Tab focuses the next field before the previous field commits its value.
                    self.baseline=effect;text=format(current)
                }
            }
            .onChange(of: editing) {_,focused in if focused {baseline=effect;error=""} else {_=commitText()} }
    }
    private func reset() {text=format(current);baseline=nil;error=""}
    @discardableResult private func commitText() -> Bool {
        guard let expected=baseline else {return true}
        if text == format(parameter.value(in:expected)) {reset();return true}
        guard let value=Double(text.trimmingCharacters(in:.whitespacesAndNewlines)) else {error="숫자를 입력하세요";return false}
        guard commit(value,expected:expected) else {return false}
        baseline=nil;return true
    }
    @discardableResult private func commit(_ value: Double, expected: Effect) -> Bool {
        do {
            let next=try parameter.applying(value,to:expected)
            guard apply(expected,next) else {error="효과가 변경되었습니다. 다시 선택해 입력하세요";return false}
            text=format(parameter.value(in:next));error="";return true
        } catch {self.error=error.localizedDescription;return false}
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
        slider.setAccessibilityLabel(parameter.title+" 슬라이더 · "+parameter.unit)
        slider.setAccessibilityValueDescription(parameter.value(in:effect).formatted(.number.precision(.fractionLength(0...3)))+" "+parameter.unit)
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
