import AppKit
import SwiftUI
import CirclrCore

extension AppStore {
    var currentAudioClip:AudioClip? {guard case .audio(_,let id)=selectedMusic?.content else{return nil};return currentLane?.audio.first{$0.id==id}}
    var audioEditorHasFocus:Bool {NSApp.keyWindow?.firstResponder is OrbitAudioView}
    var audioCommandAvailable:Bool {currentAudioClip != nil && !automationVisible && !(NSApp.keyWindow?.firstResponder is NSTextView) && !navigationOpen && commandPalette==nil && !keyboardHelp && !hierarchySettingsOpen}
    var audioCutOffset:Double {guard let clip=currentAudioClip else{return 0};return min(clip.duration,max(0,audioSplitOffset ?? clip.duration/2))}
    func splitAudio(){applyAudioEdit(.split(sourceOffset:audioCutOffset),label:"오디오 분할")}
    func duplicateAudio(){applyAudioEdit(.duplicate(beatOffset:nil),label:"오디오 복제")}
    func applyAudioEdit(_ change:AudioEditing.Change,label:String) {
        guard let use=selectedUse,let node=selectedMusic,currentAudioClip != nil else{return}
        let original=editOriginal,revision=project.musicRevision;var result:ID?
        mutate(label){result=try AudioEditing.apply(change,nodeID:node.id,useID:use.id,original:original,in:&$0)}
        guard project.musicRevision != revision else{return}
        if case .fade=change {}else{audioSplitOffset=nil}
        if let result,result != node.id {focusHierarchy(.music(arrangementID:project.activeArrangementID,useID:use.id,nodeID:result),detail:true)}
        else if result==nil {focusHierarchy(.section(arrangementID:project.activeArrangementID,useID:use.id),detail:false)}
    }
    func editAudioClip(_ clip:AudioClip,_ edit:(inout AudioClip)->Void) {
        guard var lane=currentLane,let i=lane.audio.firstIndex(where:{$0.id==clip.id}),let asset=project.assets.first(where:{$0.id==clip.assetID}) else{return}
        var value=lane.audio[i];edit(&value)
        do {try value.validateEditing(asset:asset);lane.audio[i]=value;if lane != currentLane{setLane(lane)}}catch{fail(error)}
    }
    func handleAudioEditKey(_ event:NSEvent)->Bool {
        if event.modifierFlags.contains(.control){return false}
        if event.modifierFlags.contains(.command) {
            if event.keyCode==17 {splitAudio();return true}
            if event.keyCode==2 {duplicateAudio();return true}
            return false
        }
        if event.keyCode==51 || event.keyCode==117 {applyAudioEdit(.delete,label:"오디오 삭제");return true}
        return false
    }
}

struct AudioWorkspaceView:View {
    @ObservedObject var store:AppStore
    let clip:AudioClip
    let asset:Asset
    var liveClip:AudioClip {store.currentLane?.audio.first{$0.id==clip.id} ?? clip}
    var defaultFade:Double {
        let clip=liveClip
        guard clip.preservesTail != true,let node=store.selectedMusic,let clock=store.sectionClock else{return 0}
        return min(clip.duration/2,0.005*AudioClipTiming(node:node,context:store.currentContext,clock:clock).rate(clip))
    }
    var fadeIn:Double {liveClip.fadeIn ?? defaultFade}
    var fadeOut:Double {liveClip.fadeOut ?? defaultFade}
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text(asset.name).foregroundStyle(StudioTheme.secondary).lineLimit(1)
                Spacer()
                if store.selectedMusic?.bounce != nil {Button("원본 복원"){store.restoreBounce()}}
            }
            GeometryReader { geometry in
                HStack(alignment:.top,spacing:24) {
                    OrbitAudioEditor(store:store,clip:clip,asset:asset).frame(width:min(380,geometry.size.width*0.38),height:geometry.size.height)
                    ScrollView {
                        VStack(alignment:.leading,spacing:10) {
                            HStack(spacing:10) {
                                ValueField(title:"분할 위치 초",value:Binding(get:{store.audioCutOffset},set:{store.audioSplitOffset=$0}),range:0...clip.duration)
                                Button("분할"){store.splitAudio()}.help("커서에서 두 서클로 분할 · ⌘T")
                                Button("복제"){store.duplicateAudio()}.help("구간 뒤로 복제 · ⌘D")
                            }
                            Text("파형 클릭으로 분할 위치 선택 · 선택 시작 기준 · 원본 초").font(.system(size:11)).foregroundStyle(StudioTheme.secondary)
                            HStack(spacing:14) {
                                ValueField(title:"시작 박",value:binding(\.beat),range:0...131072)
                                ValueField(title:"원본 시작 초",value:binding(\.sourceStart),range:(clip.renderWindow?.sourceStart ?? 0)...max(clip.renderWindow?.sourceStart ?? 0,(clip.renderWindow.map{$0.sourceStart+$0.duration} ?? asset.duration)-clip.duration))
                            }
                            HStack(spacing:14) {
                                ValueField(title:"길이 초",value:binding(\.duration),range:0.01...max(0.01,(clip.renderWindow.map{$0.sourceStart+$0.duration} ?? asset.duration)-clip.sourceStart))
                                ValueField(title:"볼륨",value:binding(\.gain),range:0...4)
                            }
                            HStack(spacing:14) {
                                ValueField(title:"페이드 인 초",value:Binding(get:{fadeIn},set:{store.applyAudioEdit(.fade(input:$0,output:fadeOut),label:"페이드 인")}),range:0...max(0,clip.duration-fadeOut))
                                ValueField(title:"페이드 아웃 초",value:Binding(get:{fadeOut},set:{store.applyAudioEdit(.fade(input:fadeIn,output:$0),label:"페이드 아웃")}),range:0...max(0,clip.duration-fadeIn))
                            }
                            HStack(spacing:12) {
                                Toggle("템포 추종",isOn:Binding(get:{clip.followsTempo},set:{value in store.editAudioClip(clip){$0.followsTempo=value}}))
                                ValueField(title:"원본 BPM",value:binding(\.sourceBPM),range:1...999)
                                Toggle("음소거",isOn:Binding(get:{store.selectedMusic?.muted ?? false},set:{v in store.updateMusic("오디오 음소거"){$0.muted=v}}))
                                Button("삭제"){store.applyAudioEdit(.delete,label:"오디오 삭제")}
                            }
                        }.padding(.trailing,8)
                    }.frame(maxWidth:.infinity)
                }
            }
        }.onAppear{store.requestWaveform(asset)}
    }
    func binding(_ key:WritableKeyPath<AudioClip,Double>)->Binding<Double> {
        Binding(get:{store.currentAudioClip?[keyPath:key] ?? clip[keyPath:key]},set:{v in store.editAudioClip(clip){$0[keyPath:key]=v}})
    }
}
