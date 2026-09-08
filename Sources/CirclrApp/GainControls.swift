import SwiftUI
import AppKit
import CirclrCore

struct GainControls:View {
    let title:String
    let detail:String
    @Binding var gain:Double
    @Binding var muted:Bool
    @Environment(\.numberEditing) private var context
    @State private var error=""
    var body:some View {
        VStack(alignment:.leading,spacing:4) {
            HStack {
                Text(title).font(.system(size:14,weight:.semibold))
                Spacer()
                Toggle("음소거",isOn:$muted).toggleStyle(.button)
                    .accessibilityLabel(title+" 음소거")
            }
            HStack(spacing:14) {
                GainFader(title:title,gain:gain,context:context,reject:{error="편집 대상이 변경되었습니다. 다시 조절하세요"}){expected,value in
                    guard gain==expected else{error="레벨이 변경되었습니다. 다시 조절하세요";return false}
                    if value != gain{gain=value}
                    error="";return gain==value
                }.frame(minWidth:130,maxWidth:.infinity).frame(height:30)
                    .accessibilityLabel(title+" 슬라이더")
                CommittedNumberField(title:title+" dB",value:$gain,range:0...4,width:90,presentation:.gainDecibels)
                Text("dB").foregroundStyle(StudioTheme.secondary)
                Button("0 dB"){gain=1}.help(title+"을 원래 레벨로 복원")
                    .accessibilityLabel(title+" 0 dB로 복원")
            }
            Text(error.isEmpty ? detail:error).font(.system(size:12)).foregroundStyle(error.isEmpty ? StudioTheme.secondary:Color.red).fixedSize(horizontal:false,vertical:true)
        }
    }
}

private struct GainFader:NSViewRepresentable {
    let title:String
    let gain:Double
    let context:NumberEditingContext
    let reject:()->Void
    let apply:(Double,Double)->Bool
    @Environment(\.isEnabled) private var enabled
    func makeCoordinator()->Coordinator{Coordinator(self)}
    func makeNSView(context:Context)->Control {
        let slider=Control();slider.minValue=GainScale.minimumFaderDB;slider.maxValue=GainScale.maximumDB
        slider.isContinuous=false;slider.target=context.coordinator;slider.action=#selector(Coordinator.changed(_:))
        slider.began={[weak coordinator=context.coordinator] in coordinator?.begin()}
        slider.appearance=NSAppearance(named:.darkAqua);updateNSView(slider,context:context);return slider
    }
    func updateNSView(_ slider:Control,context:Context) {
        context.coordinator.parent=self;slider.isEnabled=enabled
        if !slider.tracking{slider.doubleValue=GainScale.faderValue(gain)}
        slider.setAccessibilityLabel(title+" 슬라이더")
        slider.setAccessibilityValueDescription(GainScale.text(gain)+" dB")
        slider.toolTip="드래그를 놓으면 적용 · 방향키 0.5 dB · ⌥ 0.1 dB · ⇧ 3 dB · 맨 왼쪽은 무음"
    }
    final class Coordinator:NSObject {
        var parent:GainFader
        var baseline:Double?
        var identity:NumberEditIdentity?
        init(_ parent:GainFader){self.parent=parent}
        func begin(){baseline=parent.gain;identity=parent.context.beforeTyping()}
        @objc func changed(_ sender:Control) {
            guard !sender.tracking else{return}
            let value=GainScale.gain(atFader:sender.doubleValue,preserving:baseline ?? parent.gain)
            defer{baseline=nil;identity=nil}
            let expected=baseline ?? parent.gain
            let expectedIdentity=baseline == nil ? parent.context.beforeTyping():identity
            guard sender.isEnabled,expectedIdentity==parent.context.current(),parent.apply(expected,value) else{sender.doubleValue=GainScale.faderValue(parent.gain);parent.reject();return}
        }
    }
    final class Control:NSSlider {
        var began:(()->Void)?
        var tracking=false
        override var acceptsFirstResponder:Bool{true}
        override func acceptsFirstMouse(for event:NSEvent?)->Bool{true}
        override func mouseDown(with event:NSEvent) {
            guard isEnabled else{return}
            window?.makeFirstResponder(self);tracking=true;began?();super.mouseDown(with:event);tracking=false;sendAction(action,to:target)
        }
        override func keyDown(with event:NSEvent) {
            guard isEnabled,!event.modifierFlags.contains(.command),!event.modifierFlags.contains(.control),[123,124,125,126].contains(event.keyCode) else{super.keyDown(with:event);return}
            began?()
            let delta=event.modifierFlags.contains(.option) ? 0.1:event.modifierFlags.contains(.shift) ? 3.0:0.5
            doubleValue=min(maxValue,max(minValue,doubleValue+(event.keyCode==123 || event.keyCode==125 ? -delta:delta)))
            sendAction(action,to:target)
        }
    }
}
