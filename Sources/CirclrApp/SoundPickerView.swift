import SwiftUI
import CirclrCore

enum SoundPickerTarget {case instrument, musicEffect, signalEffect}
struct SoundPickerRequest: Identifiable {
    let id=UUID()
    let identity:NumberEditIdentity
    let target:SoundPickerTarget
    let destination:String
    let currentName:String
    let currentChoice:SoundChoice?
}

extension AppStore {
    func instrumentName(_ instrument:Instrument)->String {
        switch instrument.kind {
        case .synthesizer:
            let patch=instrument.synth ?? SynthPatch()
            return SynthPreset.matching(patch)?.name ?? patch.voice.label
        case .sampler:return instrument.sample.flatMap{s in project.assets.first{$0.id==s.assetID}?.name} ?? "샘플 악기"
        case .soundBank:
            return soundBankPresets.first{$0.id==SoundSelection.choice(in:instrument)}?.selectionName
                ?? "Sound Bank · #\(instrument.program+1)"+(instrument.drums ? " · 드럼 킷":"")+((instrument.bankLSB ?? 0)==0 ? "":" · 변형 \(instrument.bankLSB!)")
        case .audioUnit:return instrument.plugin?.name ?? "Audio Unit 선택 필요"
        }
    }
    func showInstrumentPicker(trackID:ID) {
        guard selectedTrackID==trackID else{return}
        showSoundPicker(.instrument)
    }
    func showSoundPicker(_ target:SoundPickerTarget) {
        arrangementPickerRequest=nil
        let name:String,destination:String,choice:SoundChoice?
        switch target {
        case .instrument:
            guard let track=selectedTrack else{return}
            name=instrumentName(track.instrument);choice=SoundSelection.choice(in:track.instrument)
            destination=AudioImportPlacement.trackLabel(track.id,in:project)+" · 이 트랙의 모든 섹션"
        case .musicEffect:
            guard let node=musicEditingNode,case .effect(let effect)=node.content else{return}
            name=effect.kind == .audioUnit ? effect.plugin?.name ?? "Audio Unit 선택 필요":Self.effectName(effect.kind)
            choice=effect.kind == .audioUnit ? effect.plugin.map{.audioUnit($0.id)}:nil
            destination=(selectedUse?.name ?? "섹션")+" › "+node.name+(editOriginal ? " · 공유 원본":" · 이번 사용")
        case .signalEffect:
            guard let node=selectedSignal,node.kind == .effect else{return}
            name=node.effect.kind == .audioUnit ? node.effect.plugin?.name ?? "Audio Unit 선택 필요":Self.effectName(node.effect.kind)
            choice=node.effect.kind == .audioUnit ? node.effect.plugin.map{.audioUnit($0.id)}:nil
            destination="전역 사운드 › "+node.name
        }
        libraryOpen=false;navigationOpen=false;commandPalette=nil;keyboardHelp=false
        soundPickerRequest=SoundPickerRequest(identity:numberEditIdentity,target:target,destination:destination,currentName:name,currentChoice:choice)
    }
    func soundCatalog(_ request:SoundPickerRequest)->[SoundCatalogItem] {request.target == .instrument ? instrumentChoices:effectChoices}
    func soundPickerCurrent(_ request:SoundPickerRequest)->Bool {
        soundPickerRequest?.id==request.id && request.identity==numberEditIdentity && !preparing && !midiRecording && !audioRecordingBusy && !audioRecordPending && mediaImportTask==nil
    }
    func closeSoundPicker(){soundPickerRequest=nil;focusCanvas?()}
    func applySound(_ choice:SoundChoice,request:SoundPickerRequest) throws {
        guard soundPickerCurrent(request) else{throw CirclrError("대상이나 음악이 바뀌었거나 다른 작업 중입니다. 닫은 뒤 다시 열어주세요.")}
        let catalog=soundCatalog(request)
        switch request.target {
        case .instrument:
            guard let current=selectedTrack?.instrument else{throw CirclrError("트랙을 다시 선택하세요")}
            let next=try SoundSelection.instrument(choice,current:current,catalog:catalog)
            if next != current {updateTrack("음색·악기 선택"){$0.instrument=next}}
            guard selectedTrack?.instrument==next else{throw CirclrError("악기를 적용하지 못했습니다")}
        case .musicEffect:
            guard case .effect(let current)=musicEditingNode?.content else{throw CirclrError("이펙터 서클을 다시 선택하세요")}
            let next=try SoundSelection.effect(choice,current:current,catalog:catalog)
            if next != current {updateMusic("Audio Unit 선택"){$0.content = .effect(next)};embeddedPlugin=nil}
            guard case .effect(let result)=musicEditingNode?.content,result==next else{throw CirclrError("이펙트를 적용하지 못했습니다")}
        case .signalEffect:
            guard let node=selectedSignal,node.kind == .effect else{throw CirclrError("전역 이펙터를 다시 선택하세요")}
            let next=try SoundSelection.effect(choice,current:node.effect,catalog:catalog)
            if next != node.effect {updateSignal("Audio Unit 선택"){$0.effect=next}}
            guard selectedSignal?.effect==next else{throw CirclrError("이펙트를 적용하지 못했습니다")}
        }
        closeSoundPicker()
    }
}

struct SoundPickerButton:View {
    let title:String
    let current:String
    let action:()->Void
    var body:some View {
        Button(action:action) {
            HStack(spacing:12) {
                VStack(alignment:.leading,spacing:5) {
                    Text(current).font(.system(size:14,weight:.medium)).lineLimit(2)
                    Text(title).font(.system(size:12)).foregroundStyle(StudioTheme.secondary)
                }.frame(maxWidth:.infinity,alignment:.leading)
                Image(systemName:"magnifyingglass").foregroundStyle(StudioTheme.accent)
            }.padding(12).contentShape(Rectangle()).background(StudioTheme.raised,in:RoundedRectangle(cornerRadius:6))
        }.buttonStyle(.plain).frame(maxWidth:660).accessibilityLabel(title+" · "+current).help(current+" · "+title)
    }
}

struct SoundPickerView:View {
    @ObservedObject var store:AppStore
    let request:SoundPickerRequest
    let size:CGSize
    @State private var query=""
    @State private var category:SoundCategory?
    @State private var bankDrums:Bool?
    @State private var highlighted:SoundChoice?
    @State private var searchFocus=UUID()
    @State private var notice=""
    @FocusState private var keyboardFocus:String?
    private var catalog:[SoundCatalogItem] {store.soundCatalog(request)}
    private var rows:[SoundCatalogItem] {SoundSelection.search(catalog,query:query,category:category,bankDrums:bankDrums)}
    private var active:SoundChoice? {rows.contains{$0.id==highlighted} ? highlighted:rows.first?.id}
    private var current:Bool {store.soundPickerCurrent(request)}
    private var missing:Bool {
        switch request.currentChoice {
        case .audioUnit,.soundBank:return !catalog.contains{$0.id==request.currentChoice}
        default:return false
        }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack {
                Text(request.target == .instrument ? "음색·악기 찾기":"Audio Unit 이펙트 찾기").font(.system(size:18,weight:.semibold))
                Spacer();Button("닫기 · Esc"){store.closeSoundPicker()}.frame(minHeight:32).foregroundStyle(StudioTheme.secondary)
                    .focusable().focused($keyboardFocus,equals:"close")
            }.padding(18)
            Text(request.destination).font(.system(size:12)).foregroundStyle(StudioTheme.secondary).lineLimit(2)
                .fixedSize(horizontal:false,vertical:true)
                .help(request.destination).padding(.horizontal,18).padding(.bottom,12)
            HStack(spacing:10) {
                Image(systemName:"magnifyingglass").foregroundStyle(StudioTheme.secondary)
                CommandSearchField(text:$query,onMove:move,onSubmit:applySelected,onCancel:{store.closeSoundPicker()},placeholder:"음색 · 계열 · 제조사 · #1–128 검색").id(searchFocus).frame(minHeight:32)
                    .focused($keyboardFocus,equals:"search")
            }.padding(.horizontal,18).padding(.bottom,14)
            if request.target == .instrument {
                HStack(spacing:8) {
                    filter("전체",value:nil)
                    ForEach([SoundCategory.synth,.soundBank,.instrument]){value in filter(value.label,value:value)}
                }.padding(.horizontal,18).padding(.bottom,12)
            }
            if category == .soundBank {
                HStack(spacing:8) {
                    bankFilter("전체 뱅크",drums:nil);bankFilter("멜로디",drums:false);bankFilter("드럼 킷",drums:true)
                    Spacer();Text("피아노·베이스 등 계열 또는 #번호로 검색").font(.system(size:12)).foregroundStyle(StudioTheme.secondary)
                }.padding(.horizontal,18).padding(.bottom,12)
            }
            HStack(alignment:.top,spacing:8) {
                Text("현재 · "+request.currentName+(missing ? " · 현재 목록에 없음":"")).lineLimit(2).fixedSize(horizontal:false,vertical:true).help(request.currentName)
                Spacer(minLength:8)
                    Button("현재 음색 찾기"){query="";category=nil;bankDrums=nil;highlighted=request.currentChoice;searchFocus=UUID();keyboardFocus="search"}
                    .disabled(!catalog.contains{$0.id==request.currentChoice})
                    .focusable().focused($keyboardFocus,equals:"current")
                Text("\(rows.count)개 결과").monospacedDigit().fixedSize()
            }.font(.system(size:12)).foregroundStyle(StudioTheme.secondary).padding(.horizontal,18).padding(.bottom,12)
            if !current || !notice.isEmpty {
                Text(!current ? "대상이나 음악이 바뀌었거나 다른 작업 중입니다. 닫은 뒤 다시 열어주세요.":notice)
                    .font(.system(size:12)).foregroundStyle(StudioTheme.accent).fixedSize(horizontal:false,vertical:true).padding(.horizontal,18).padding(.bottom,12)
            }
            ScrollViewReader {proxy in
                ScrollView {
                    if rows.isEmpty {Text(emptyMessage)
                        .font(.system(size:13)).foregroundStyle(StudioTheme.secondary).padding(30)}
                    LazyVStack(spacing:1) {ForEach(Array(rows.enumerated()),id:\.element.id){index,entry in row(entry,index:index)}}
                }.onChange(of:active){_,id in if let id{proxy.scrollTo(id,anchor:.center)}}
                    .onChange(of:query){_,value in highlighted=value.isEmpty ? request.currentChoice:rows.first?.id;notice=""}
                    .onChange(of:keyboardFocus){_,focus in
                        guard let focus,focus.hasPrefix("row-"),let index=Int(focus.dropFirst(4)),rows.indices.contains(index) else{return}
                        proxy.scrollTo(rows[index].id,anchor:.center)
                    }
            }
            Divider().overlay(StudioTheme.line)
            Text(size.height<500 ? "↑↓ 선택 · Return 적용 · Esc 닫기":"↑↓ 선택 · Return 음색 적용 · Esc 취소 · 같은 음색을 선택하면 현재 설정 유지")
                .font(.system(size:12)).foregroundStyle(StudioTheme.secondary).padding(size.height<500 ? 10:18)
        }.frame(width:size.width,height:size.height).background(StudioTheme.surface,in:RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(StudioTheme.line))
            .background(OverlayKeyboardKeys(active:{store.soundPickerRequest?.id==request.id},move:moveKeyboardFocus,cancel:{store.closeSoundPicker()}).frame(width:0,height:0))
            .onAppear{if case .soundBank=request.currentChoice{category = .soundBank};highlighted=request.currentChoice}
    }
    private var emptyMessage:String {
        if category == .soundBank && store.soundBankPresets.isEmpty {return store.soundBankNotice.isEmpty ? "macOS Sound Bank에서 선택 가능한 음색을 찾지 못했습니다. 기존 설정은 유지됩니다.":store.soundBankNotice+". 기존 설정은 유지됩니다."}
        return catalog.isEmpty ? "설치된 AU 이펙트가 없습니다. 설치 후 앱을 다시 열어주세요.":"일치하는 음색이 없습니다. 검색어나 종류를 바꿔보세요."
    }
    private func bankFilter(_ title:String,drums:Bool?)->some View {
        Button{bankDrums=drums;highlighted=nil;notice="";searchFocus=UUID();keyboardFocus="search"}label:{
            Text(title).font(.system(size:12,weight:bankDrums==drums ? .semibold:.medium))
                .foregroundStyle(bankDrums==drums ? StudioTheme.accent:StudioTheme.text).padding(.horizontal,9).padding(.vertical,7)
                .background(bankDrums==drums ? StudioTheme.raised:Color.clear,in:RoundedRectangle(cornerRadius:5))
        }.buttonStyle(.plain).accessibilityAddTraits(bankDrums==drums ? .isSelected:[])
            .focusable().focused($keyboardFocus,equals:"bank-\(title)")
    }
    private func row(_ entry:SoundCatalogItem,index:Int)->some View {
        Button{apply(entry.id)}label:{
            HStack(spacing:12) {
                VStack(alignment:.leading,spacing:6) {
                    Text(entry.title).font(.system(size:14,weight:.medium)).lineLimit(2)
                    Text(entry.detail).font(.system(size:12)).foregroundStyle(StudioTheme.secondary).lineLimit(2)
                }.frame(maxWidth:.infinity,alignment:.leading)
                if entry.id==request.currentChoice {Text("현재").font(.system(size:12)).foregroundStyle(StudioTheme.accent)}
            }.padding(.horizontal,18).padding(.vertical,12).contentShape(Rectangle()).background(active==entry.id ? StudioTheme.raised:Color.clear)
        }.buttonStyle(.plain).id(entry.id).disabled(!current)
            .accessibilityLabel(entry.title+" · "+entry.detail).help(entry.title+" · "+entry.detail)
            .accessibilityAddTraits(active==entry.id ? .isSelected:[])
            .focusable().focused($keyboardFocus,equals:"row-\(index)")
    }
    private func filter(_ title:String,value:SoundCategory?)->some View {
        Button{category=value;bankDrums=nil;highlighted=nil;notice="";searchFocus=UUID();keyboardFocus="search"}label:{
            Text(title).font(.system(size:12,weight:category==value ? .semibold:.medium))
                .foregroundStyle(category==value ? StudioTheme.accent:StudioTheme.text).padding(.horizontal,9).padding(.vertical,7)
                .background(category==value ? StudioTheme.raised:Color.clear,in:RoundedRectangle(cornerRadius:5))
        }.buttonStyle(.plain).accessibilityAddTraits(category==value ? .isSelected:[])
            .focusable().focused($keyboardFocus,equals:"category-\(title)")
    }
    private var keyboardOrder:[String] {
        var order=["search","close"]
        if catalog.contains(where:{$0.id==request.currentChoice}) {order.append("current")}
        if request.target == .instrument {order += ["category-전체"]+[SoundCategory.synth,.soundBank,.instrument].map{"category-\($0.label)"}}
        if category == .soundBank {order += ["bank-전체 뱅크","bank-멜로디","bank-드럼 킷"]}
        if current {order += rows.indices.map{"row-\($0)"}}
        return order
    }
    private func moveKeyboardFocus(_ backward:Bool) {
        keyboardFocus=OverlayKeyboardTraversal.next(in:keyboardOrder,current:keyboardFocus,backward:backward)
    }
    private func move(_ delta:Int) {
        guard !rows.isEmpty else{return};let index=rows.firstIndex{$0.id==active} ?? 0
        highlighted=rows[max(0,min(rows.count-1,index+delta))].id
    }
    private func applySelected(){if let active{apply(active)}}
    private func apply(_ choice:SoundChoice) {
        guard rows.contains(where:{$0.id==choice}) else{return}
        do{try store.applySound(choice,request:request)}catch{notice=error.localizedDescription}
    }
}
