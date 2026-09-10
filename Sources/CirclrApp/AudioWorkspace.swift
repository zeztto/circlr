import AppKit
import SwiftUI
import CirclrCore

extension AppStore {
    var isSharedRhythmAudio:Bool {if case .rhythmAudio=selectedMusic?.content{return true};return false}
    var sharedRhythmAudioPattern:RhythmPattern? {
        guard case .rhythmAudio(let trackID)=selectedMusic?.content,let id=editPatternID else{return nil}
        return project.patterns.first{$0.id==id && $0.trackID==trackID}
    }
    var currentAudioClip:AudioClip? {
        if isSharedRhythmAudio {return sharedRhythmAudioPattern?.audio.first{$0.id==selectedClipID}}
        guard case .audio(_,let id)=selectedMusic?.content else{return nil}
        return currentLane?.audio.first{$0.id==id}
    }
    var audioIsOutsideSharedOriginal:Bool {
        guard editOriginal,case .audio(let laneID,let clipID)=selectedMusic?.content,
              currentAudioClip==nil,let use=selectedUse,
              let section=project.sections.first(where:{$0.id==use.sectionID}),
              let lanes=try? ArrangementCompiler.effectiveLanes(section:section,use:use) else{return false}
        return lanes.first(where:{$0.id==laneID})?.audio.contains{$0.id==clipID} == true
    }
    var audioScopeRecoveryAvailable:Bool {
        audioIsOutsideSharedOriginal && !libraryOpen && !navigationOpen && commandPalette==nil && !keyboardHelp &&
        soundPickerRequest==nil && arrangementPickerRequest==nil && !hierarchySettingsOpen && !connectionsOpen &&
        !automationVisible && midiImportDraft==nil && embeddedPlugin==nil && errorMessage==nil &&
        NSApp.modalWindow==nil && NSApp.keyWindow?.attachedSheet==nil &&
        !(NSApp.keyWindow?.firstResponder is NSTextView)
    }
    @discardableResult func recoverAudioEditScope(identity:NumberEditIdentity)->Bool {
        // Recheck live first responder as focus changes do not necessarily redraw SwiftUI.
        guard audioScopeRecoveryAvailable else{return false}
        return setAudioEditScope(original:false,identity:identity)
    }
    @discardableResult func setAudioEditScope(original:Bool,identity:NumberEditIdentity)->Bool {
        guard case .audio=selectedMusic?.content else{return false}
        return setMusicEditScope(original:original,identity:identity)
    }
    var audioEditorHasFocus:Bool {NSApp.keyWindow?.firstResponder is OrbitAudioView}
    var audioCommandAvailable:Bool {currentAudioClip != nil && !automationVisible && !(NSApp.keyWindow?.firstResponder is NSTextView) && !libraryOpen && !navigationOpen && commandPalette==nil && !keyboardHelp && !hierarchySettingsOpen}
    var audioCutOffset:Double {guard let clip=currentAudioClip else{return 0};return min(clip.duration,max(0,audioSplitOffset ?? clip.duration/2))}
    var audioSplitIssue:String? {
        guard isSharedRhythmAudio else{return nil}
        return sharedAudioIssue(.split(sourceOffset:audioCutOffset))
    }
    func sharedAudioIssue(_ change:AudioEditing.Change)->String? {
        guard let pattern=sharedRhythmAudioPattern,let clip=currentAudioClip else{return "공유 오디오 클립을 선택하세요"}
        let operation:SharedAudioPreflightKey.Operation
        switch change {
        case .split(let offset):operation = .split(offset)
        case .duplicate(let offset):operation = .duplicate(offset)
        default:return nil
        }
        let key=SharedAudioPreflightKey(projectID:project.id,revision:project.musicRevision,generation:mediaImportGeneration,
            patternID:pattern.id,trackID:pattern.trackID,clipID:clip.id,operation:operation)
        sharedAudioPreflightCache.removeAll{$0.key.projectID != key.projectID || $0.key.revision != key.revision || $0.key.generation != key.generation}
        if let cached=sharedAudioPreflightCache.first(where:{$0.key==key}) {return cached.issue}
        let issue:String?
        do {var copy=project;_ = try SharedRhythmAudioEditing.apply(change,patternID:pattern.id,trackID:pattern.trackID,clipID:clip.id,in:&copy);issue=nil}
        catch {issue=error.localizedDescription}
        sharedAudioPreflightCache.append(.init(key:key,issue:issue))
        if sharedAudioPreflightCache.count>2 {sharedAudioPreflightCache.removeFirst(sharedAudioPreflightCache.count-2)}
        return issue
    }
    func splitAudio(){
        if let issue=audioSplitIssue {status=issue;return}
        applyAudioEdit(.split(sourceOffset:audioCutOffset),label:"오디오 분할")
    }
    var audioDuplicateIssue:String? {
        guard let clip=currentAudioClip,let node=selectedMusic,let clock=sectionClock else{return "편집할 오디오 서클을 선택하세요"}
        if isSharedRhythmAudio {return sharedAudioIssue(.duplicate(beatOffset:nil))}
        do {_ = try AudioClipTiming(node:node,context:currentContext,clock:clock).duplicateBeat(clip);return nil}
        catch {return error.localizedDescription}
    }
    func duplicateAudio(){
        if let issue=audioDuplicateIssue {status=issue;return}
        applyAudioEdit(.duplicate(beatOffset:nil),label:"오디오 복제")
    }
    func applyAudioEdit(_ change:AudioEditing.Change,label:String) {
        guard let use=selectedUse,let node=selectedMusic,currentAudioClip != nil else{return}
        if let pattern=sharedRhythmAudioPattern,let clip=currentAudioClip {
            let revision=project.musicRevision,sourceCursor=audioSplitOffset.map{clip.sourceStart+$0}
            var result:ID?
            mutate(label){result=try SharedRhythmAudioEditing.apply(change,patternID:pattern.id,trackID:pattern.trackID,clipID:clip.id,in:&$0)}
            guard project.musicRevision != revision else{return}
            selectedClipID=result ?? sharedRhythmAudioPattern?.audio.first?.id
            if selectedClipID==nil {
                audioSplitOffset=nil
                focusHierarchy(.section(arrangementID:project.activeArrangementID,useID:use.id),detail:false)
                return
            }
            switch change {
            case .fade:break
            case .replace:if let sourceCursor,let current=currentAudioClip {audioSplitOffset=min(current.duration,max(0,sourceCursor-current.sourceStart))}
            default:audioSplitOffset=nil
            }
            return
        }
        let original=editOriginal,revision=project.musicRevision
        let sourceCursor=audioSplitOffset.map{(currentAudioClip?.sourceStart ?? 0)+$0}
        var result:ID?
        mutate(label){result=try AudioEditing.apply(change,nodeID:node.id,useID:use.id,original:original,in:&$0)}
        guard project.musicRevision != revision else{return}
        switch change {
        case .fade:break
        case .replace:
            if let sourceCursor,let clip=currentAudioClip {audioSplitOffset=min(clip.duration,max(0,sourceCursor-clip.sourceStart))}
        default:audioSplitOffset=nil
        }
        if let result,result != node.id {focusHierarchy(.music(arrangementID:project.activeArrangementID,useID:use.id,nodeID:result),detail:true);requestEditorNavigationFocus()}
        else if result==nil {focusHierarchy(.section(arrangementID:project.activeArrangementID,useID:use.id),detail:false)}
    }
    func editAudioClip(_ clip:AudioClip,_ edit:(inout AudioClip)->Void) {
        if isSharedRhythmAudio {
            guard currentAudioClip?.id==clip.id,var value=currentAudioClip else{return}
            edit(&value);applyAudioEdit(.replace(value),label:"공유 리듬 오디오 편집");return
        }
        guard var lane=currentLane,let i=lane.audio.firstIndex(where:{$0.id==clip.id}),let asset=project.assets.first(where:{$0.id==clip.assetID}) else{return}
        var value=lane.audio[i];edit(&value)
        if case .audio(let laneID,let clipID)=selectedMusic?.content,laneID==lane.id,clipID==clip.id {
            applyAudioEdit(.replace(value),label:"오디오 편집")
        } else {
            do {try value.validateEditing(asset:asset);lane.audio[i]=value;if lane != currentLane{setLane(lane)}}catch{fail(error)}
        }
    }
    func handleAudioEditKey(_ event:NSEvent)->Bool {
        if event.modifierFlags.contains(.control){return false}
        if event.modifierFlags.contains(.command) {
            guard event.modifierFlags.intersection([.command,.control,.option,.shift]) == .command else{return false}
            if event.keyCode==17 {splitAudio();return true}
            if event.keyCode==2 {duplicateAudio();return true}
            return false
        }
        if event.keyCode==51 || event.keyCode==117 {applyAudioEdit(.delete,label:"오디오 삭제");return true}
        return false
    }
}

@MainActor final class AudioEditorFocus {
    weak var view:NSView?
    func focus(){guard let view else{return};view.scrollToVisible(view.bounds);view.window?.makeFirstResponder(view)}
}

struct AudioWorkspaceView:View {
    @ObservedObject var store:AppStore
    let clip:AudioClip
    let asset:Asset
    @Binding var viewport:AudioSourceViewport
    @State private var focusTarget=AudioEditorFocus()
    @State private var fieldFocus=NumberFieldFocus([
        "오디오 배치 박","오디오 원본 시작 초","오디오 원본 끝 초","오디오 분할 위치 초",
        "오디오 볼륨 dB","오디오 페이드 인 ms","오디오 페이드 아웃 ms","오디오 원본 BPM"],revealOnFocus:true)
    var liveClip:AudioClip {store.currentAudioClip ?? clip}
    var rate:Double {
        guard let node=store.selectedMusic,let clock=store.sectionClock else{return 1}
        return AudioClipTiming(node:node,context:store.currentContext,clock:clock).rate(liveClip)
    }
    var defaultFade:Double {liveClip.preservesTail == true ? 0:min(liveClip.duration/2,0.005*rate)}
    var fadeIn:Double {liveClip.explicitEnvelope?.fadeIn ?? defaultFade}
    var fadeOut:Double {liveClip.explicitEnvelope?.fadeOut ?? defaultFade}
    var trim:AudioTrimBounds {AudioTrimBounds(clip:liveClip,asset:asset)}
    var selectionOutside:Bool {!viewport.contains(liveClip.sourceStart,assetDuration:asset.duration) || !viewport.contains(liveClip.sourceStart+liveClip.duration,assetDuration:asset.duration)}
    var sourceCursor:Double {liveClip.sourceStart+store.audioCutOffset}
    var cursorOutside:Bool {!viewport.contains(sourceCursor,assetDuration:asset.duration)}
    var body:some View {
        let scopeIdentity=store.numberEditIdentity
        GeometryReader { geometry in
        ScrollView {
        VStack(alignment:.leading,spacing:10) {
            HStack(spacing:12) {
                if store.isSharedRhythmAudio {
                    Text("공유 패턴 · 모든 사용에 반영").font(.system(size:11)).fixedSize()
                } else {
                Toggle(store.editOriginal ? "공유 원본":"이번 사용",isOn:Binding(get:{store.editOriginal},set:{value in
                    if store.setAudioEditScope(original:value,identity:scopeIdentity) {focusTarget.focus()}
                })).fixedSize().accessibilityLabel("오디오 공유 원본 편집")
                    .accessibilityValue(store.editOriginal ? "공유 원본":"이번 사용")
                    .help(store.editOriginal ? "같은 원본을 사용하는 다른 섹션 사용에도 오디오 편집이 반영됩니다":"오디오 편집은 이번 사용에만 반영됩니다. 체크하면 공유 원본을 편집합니다")
                }
                Text(asset.name).foregroundStyle(StudioTheme.secondary).lineLimit(1).help(asset.name)
                Spacer(minLength:0)
            }
                MIDIWorkspaceToolbarLayout {
                    HStack(spacing:10) {
                Button("분할"){act{store.splitAudio()}}
                    .disabled(store.audioCutOffset<=0 || store.audioCutOffset>=liveClip.duration || store.audioSplitIssue != nil)
                    .help(store.isSharedRhythmAudio ? "선택 시작 기준 커서에서 두 공유 클립으로 분할 · ⌘T":"선택 시작 기준 커서에서 두 서클로 분할 · ⌘T")
                Button(store.audioDuplicateIssue==nil ? "복제":"복제 · 공간 없음"){act{store.duplicateAudio()}}.disabled(store.audioDuplicateIssue != nil).help(store.audioDuplicateIssue ?? "구간 뒤로 복제 · ⌘D")
                    }.fixedSize(horizontal:true,vertical:false)
                    HStack(spacing:10) {
                TrackBounceButton(store:store)
                if store.selectedMusic?.bounce != nil {Button("원본 복원"){store.restoreBounce(identity:scopeIdentity)}}
                    }.fixedSize(horizontal:true,vertical:false)
                    HStack(spacing:10) {
                Toggle("템포 추종",isOn:Binding(get:{liveClip.followsTempo},set:{value in store.editAudioClip(liveClip){$0.followsTempo=value}}))
                Toggle(store.isSharedRhythmAudio ? (store.editOriginal ? "공유 원본 서클 음소거":"이번 사용 서클 음소거"):"음소거",isOn:Binding(get:{store.musicEditingNode?.muted ?? false},set:{v in store.updateMusic("오디오 음소거"){$0.muted=v}}))
                    .help(store.isSharedRhythmAudio ? (store.editOriginal ? "공유 원본 서클을 음소거합니다. 같은 원본을 사용하는 다른 섹션에도 반영되며 공유 패턴의 클립 볼륨은 바꾸지 않습니다":"이번 사용의 서클만 음소거합니다. 공유 패턴의 클립 볼륨은 바꾸지 않습니다"):"선택한 서클의 음소거")
                Button("삭제"){act{store.applyAudioEdit(.delete,label:"오디오 삭제")}}
                    }.fixedSize(horizontal:true,vertical:false)
                }
            OrbitAudioEditor(store:store,clip:liveClip,asset:asset,viewport:$viewport,focusTarget:focusTarget)
                .frame(maxWidth:.infinity)
                .frame(height:geometry.size.height < 320 ? 112:(store.project.usesOrbits ? 160:140))
            AudioWorkspaceFieldLayout {
                    field("배치",unit:"박",value:binding(\.beat),range:0...131072,presentation:.beatPosition)
                    field("원본 시작",unit:"초",value:trimBinding(end:false),range:trim.start)
                        .help("원본 시간 기준 · 파형에서 ← → 시작 조절 · ⇧ 0.1초 · 기본 0.01초")
                    field("원본 끝",unit:"초",value:trimBinding(end:true),range:trim.end)
                        .help("원본 시간 기준 · 파형에서 ⌥← → 끝 조절 · ⇧ 0.1초 · 기본 0.01초")
                    field("분할 위치",unit:"초",value:Binding(get:{store.audioCutOffset},set:{store.audioSplitOffset=$0}),range:0...liveClip.duration)
                        .help("선택 시작 기준 · 파형 클릭으로 이동 · ⌘T로 분할")
                    field("볼륨",unit:"dB",value:binding(\.gain),range:0...4,presentation:.gainDecibels)
                    field("페이드 인",unit:"ms",value:fadeBinding(input:true),range:0...max(0,(liveClip.duration-fadeOut)*1000))
                        .help("원본 시간 기준 페이드 · 이전 페이드도 유지")
                    field("페이드 아웃",unit:"ms",value:fadeBinding(input:false),range:0...max(0,(liveClip.duration-fadeIn)*1000))
                        .help("원본 시간 기준 페이드 · 이전 페이드도 유지")
                    field("원본",unit:"BPM",value:binding(\.sourceBPM),range:1...999)
            }
                if store.isSharedRhythmAudio {
                    if let issue=store.audioSplitIssue {Text("분할: "+issue).font(.system(size:11)).foregroundStyle(StudioTheme.secondary).fixedSize(horizontal:false,vertical:true)}
                    if let issue=store.audioDuplicateIssue,issue != store.audioSplitIssue {Text("복제: "+issue).font(.system(size:11)).foregroundStyle(StudioTheme.secondary).fixedSize(horizontal:false,vertical:true)}
                }
                MIDIWorkspaceToolbarLayout {
                    HStack(spacing:10) {
                Button("수치 입력"){_ = fieldFocus.enter(in:focusTarget.view?.window)}
                    .help("파형에서 Tab 첫 수치 · ⇧Tab 마지막 수치 · Return/Esc 파형 복귀")
                Button("전체 파일"){viewport.showAll();focusTarget.focus()}.disabled(viewport.fitted==nil)
                    .help("전체 원본 시간 표시 · 파형에서 0")
                Button("선택 구간"){viewport.fit(liveClip,assetDuration:asset.duration);focusTarget.focus()}
                    .help((selectionOutside ? "화면 밖 선택 구간까지 다시 맞춤":"현재 구간을 확대 · 편집 중 표시 범위 유지")+" · 파형에서 F")
                Button {zoom(0.5)} label:{Image(systemName:"minus")}.accessibilityLabel("오디오 파형 축소").help("파형 축소 · −")
                Button {zoom(2)} label:{Image(systemName:"plus")}.accessibilityLabel("오디오 파형 확대").help("파형 확대 · +")
                    }.fixedSize(horizontal:true,vertical:false)
                    HStack(spacing:10) {
                Text(String(format:"원본 %.3f초 · 재생 %.3f초",liveClip.duration,liveClip.duration/max(1e-9,rate)))
                    .font(.system(size:11)).monospacedDigit().foregroundStyle(StudioTheme.secondary)
                Button("커서 보기"){viewport.reveal(sourceCursor,assetDuration:asset.duration);focusTarget.focus()}
                    .disabled(!cursorOutside).help("화면 밖 분할 커서를 현재 배율로 찾기 · C")
                    }.fixedSize(horizontal:true,vertical:false)
                }
        }.padding(.trailing,6).padding(.bottom,8)
        }
        }
        .environment(\.numberEditing,NumberEditingContext(snapshot:store.numberEditIdentity,current:{store.numberEditIdentity},focusCanvas:{focusTarget.focus()},fieldFocus:fieldFocus))
        .onAppear{store.requestWaveform(asset)}
        .onChange(of:asset.id){_,_ in viewport.showAll();store.requestWaveform(asset)}
    }
    func field(_ title:String,unit:String,value:Binding<Double>,range:ClosedRange<Double>,presentation:NumberEditPresentation = .number)->some View {
        VStack(alignment:.leading,spacing:3) {
            Text(title).foregroundStyle(StudioTheme.secondary).fixedSize(horizontal:false,vertical:true)
            HStack(spacing:6) {
                CommittedNumberField(title:"오디오 "+title+" "+unit,value:value,range:range,width:76,
                    presentation:unit=="초" ? .sourceSeconds:unit=="ms" ? .sourceMilliseconds:presentation)
                Text(unit).foregroundStyle(StudioTheme.secondary).font(.system(size:11)).frame(width:26,alignment:.leading)
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    func act(_ action:()->Void){action();focusTarget.focus()}
    func zoom(_ factor:Double) {
        let range=viewport.range(assetDuration:asset.duration)
        viewport.zoom(by:factor,around:cursorOutside ? (range.lowerBound+range.upperBound)/2:sourceCursor,assetDuration:asset.duration)
        focusTarget.focus()
    }
    func guarded(_ get:@escaping()->Double,_ set:@escaping(Double)->Void)->Binding<Double> {
        let identity=store.numberEditIdentity,clipID=clip.id,assetID=asset.id
        return Binding(get:get,set:{value in
            var current=store.numberEditIdentity;current.revision=identity.revision
            guard current==identity,store.currentAudioClip?.id==clipID,store.currentAudioClip?.assetID==assetID else{return}
            set(value)
        })
    }
    func binding(_ key:WritableKeyPath<AudioClip,Double>)->Binding<Double> {
        guarded({liveClip[keyPath:key]},{value in store.editAudioClip(liveClip){$0[keyPath:key]=value}})
    }
    func trimBinding(end:Bool)->Binding<Double> {
        guarded({liveClip.sourceStart+(end ? liveClip.duration:0)},{value in
            let current=liveClip,bounds=AudioTrimBounds(clip:current,asset:asset)
            store.editAudioClip(current){$0=bounds.trimming(current,to:value,editingEnd:end)}
        })
    }
    func fadeBinding(input:Bool)->Binding<Double> {
        guarded({(input ? fadeIn:fadeOut)*1000},{value in
            store.applyAudioEdit(.fade(input:input ? value/1000:fadeIn,output:input ? fadeOut:value/1000),label:input ? "페이드 인":"페이드 아웃")
        })
    }
}

/// Eager layout keeps every numeric field registered for Tab navigation, including offscreen rows.
private struct AudioWorkspaceFieldLayout:SwiftUI.Layout {
    private let horizontalGap:CGFloat=16
    private let verticalGap:CGFloat=10
    private func metrics(width:CGFloat,subviews:Subviews)->(columns:Int,cell:CGFloat,heights:[CGFloat]) {
        let columns=width < 640 ? 2:4
        let cell=max(0,(width-CGFloat(columns-1)*horizontalGap)/CGFloat(columns))
        var heights:[CGFloat]=[]
        for index in subviews.indices {
            let row=index/columns
            if row==heights.count {heights.append(0)}
            heights[row]=max(heights[row],subviews[index].sizeThatFits(.init(width:cell,height:nil)).height)
        }
        return (columns,cell,heights)
    }
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ())->CGSize {
        let width=proposal.width ?? 600
        let layout=metrics(width:width,subviews:subviews)
        return .init(width:width,height:layout.heights.reduce(0,+)+CGFloat(max(0,layout.heights.count-1))*verticalGap)
    }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        let layout=metrics(width:bounds.width,subviews:subviews)
        var y=bounds.minY
        for index in subviews.indices {
            let row=index/layout.columns,column=index%layout.columns
            if index>0 && column==0 {y+=layout.heights[row-1]+verticalGap}
            subviews[index].place(at:.init(x:bounds.minX+CGFloat(column)*(layout.cell+horizontalGap),y:y),anchor:.topLeading,
                                 proposal:.init(width:layout.cell,height:layout.heights[row]))
        }
    }
}
