import SwiftUI
import CirclrCore

/// The canvas edits current musical properties directly, without a whole-settings draft.
struct MusicContextEditor: View {
    @ObservedObject var store: AppStore
    let address: CircleAddress
    let projectID: ID
    let generation: Int
    let original: Bool
    private var snapshot: MusicContextSnapshot? {try? MusicContextEditing.snapshot(at:address,original:original,in:store.project)}
    private var current: MusicContext {snapshot?.context ?? store.project.global}
    private func title(_ field:MusicContextField) -> String {
        switch field {case .tempo:return "템포";case .meter:return "박자";case .scale:return "스케일";case .beatGrid:return "박 분할·강세";case .rhythm:return "리듬 패턴"}
    }
    private func sourceName(_ source:SettingSource) -> String {
        switch source {case .inherit:return "기본값";case .global:return "앨범";case .local:return "개별"}
    }
    @discardableResult private func apply(_ change:MusicContextChange) -> Bool {
        guard store.project.id==projectID,store.mediaImportGeneration==generation,store.hierarchySelection==address,
              original == (store.selectedMusic != nil && store.editOriginal) else {store.status="편집 대상이 바뀌었습니다. 설정을 다시 여세요";return false}
        do {
            var candidate=store.project
            try MusicContextEditing.apply(change,at:address,original:original,in:&candidate)
            if candidate==store.project {return true}
            let revision=store.project.musicRevision
            store.mutate(title(change.field)+" 설정"){$0=candidate}
            return store.project.musicRevision==revision+1
        } catch {store.fail(error);return false}
    }
    private func binding<T:Equatable>(_ key:KeyPath<MusicContext,T>,_ change:@escaping(T)->MusicContextChange) -> Binding<T> {
        Binding(get:{current[keyPath:key]},set:{value in if value != current[keyPath:key] {_=apply(change(value))}})
    }
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            if snapshot != nil {
                row(.tempo) {
                    HStack(spacing:8) {ValueField(title:"템포 BPM",value:binding(\.tempo,MusicContextChange.tempo),width:92,showsLabel:false,range:1...999);Text("BPM").foregroundStyle(StudioTheme.secondary)}
                }
                row(.meter) {
                    HStack(spacing:10) {
                        CountControl(title:"박 수",value:binding(\.meter.numerator,MusicContextChange.numerator),range:1...64)
                        Text("/").foregroundStyle(StudioTheme.secondary)
                        StudioChoice("",selection:binding(\.meter.denominator,MusicContextChange.denominator),options:[1,2,4,8,16,32,64].map{($0,String($0))}).frame(width:80).accessibilityLabel("박자 분모")
                    }
                }
                row(.scale) {
                    HStack(spacing:10) {
                        StudioChoice("",selection:binding(\.scale.root,MusicContextChange.scaleRoot),options:(0..<12).map{($0,Scale.roots[$0])}).frame(width:80).accessibilityLabel("스케일 기준음")
                        StudioChoice("",selection:binding(\.scale.name,MusicContextChange.scaleMode),options:scaleOptions).frame(width:158).accessibilityLabel("스케일 종류")
                    }
                }
                row(.beatGrid) {
                    VStack(alignment:.leading,spacing:8) {
                        HStack(spacing:14) {
                            CountControl(title:"분할",value:binding(\.beatGrid.subdivisions,MusicContextChange.subdivisions),range:1...32)
                            ValueField(title:"스윙",value:binding(\.beatGrid.swing,MusicContextChange.swing),width:76,range:0...0.75)
                        }
                        AccentContextField(value:current.beatGrid.accents) {text in apply(.accents(text))}
                    }
                }
                row(.rhythm) {
                    StudioChoice("",selection:Binding(get:{current.rhythm.patternID ?? ""},set:{_=apply(.rhythm($0.isEmpty ? nil:$0))}),options:[("","재생 안 함")]+store.project.patterns.map{($0.id,$0.name)}).frame(maxWidth:340).accessibilityLabel("재생할 리듬 패턴")
                }
                Text(address == .album ? "앨범 기본값 · 숫자는 Return·Tab으로 적용 · ⌘Z 실행 취소":"값을 바꾸면 이 항목만 개별 설정 · 기본값은 상위 서클·공유 원본을 따릅니다")
                    .font(.system(size:11)).foregroundStyle(StudioTheme.secondary).fixedSize(horizontal:false,vertical:true)
            } else {
                Text(original ? "이번 사용에만 있는 서클은 공유 원본을 편집할 수 없습니다":"음악 설정을 읽을 수 없습니다")
                if original {Button("이번 사용 편집으로 전환"){store.editOriginal=false}}
            }
        }.frame(maxWidth:800,alignment:.leading).font(.system(size:13))
    }
    private var scaleOptions:[(String,String)] {
        var options=Scale.modes.map{($0.0,$0.0)}
        if !options.contains(where:{$0.0==current.scale.name}) {options.append((current.scale.name,current.scale.name+" · 사용자 설정"))}
        return options
    }
    private func row<Content:View>(_ field:MusicContextField,@ViewBuilder content:()->Content) -> some View {
        HStack(alignment:.top,spacing:14) {
            Text(title(field)).fontWeight(.medium).frame(width:90,height:32,alignment:.leading)
            if let source=snapshot?.source(field) {
                Menu {
                    ForEach(SettingSource.allCases,id:\.self) {value in Button((source==value ? "✓ ":"")+sourceName(value)){_=apply(.source(field,value))}}
                } label: {
                    HStack(spacing:7){Text(sourceName(source));Image(systemName:"chevron.down").font(.system(size:8,weight:.semibold))}
                        .foregroundStyle(source == .local ? StudioTheme.accent:StudioTheme.text)
                        .frame(width:78,height:32).background(StudioTheme.raised,in:RoundedRectangle(cornerRadius:5))
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel(title(field)+" 설정 출처").accessibilityValue(sourceName(source))
                    .help("기본값: 상위 서클·공유 원본 · 앨범: 글로벌 값 · 개별: 이 대상의 값")
            } else {Text("앨범").foregroundStyle(StudioTheme.secondary).frame(width:78,height:32)}
            content().frame(maxWidth:.infinity,alignment:.leading)
        }
    }
}

/// Only the custom accent string is a draft. Other settings never wait for this field.
private struct AccentContextField: View {
    let value:[Int]
    let apply:(String)->Bool
    @Environment(\.numberEditing) private var context
    @State private var text=""
    @State private var baseline:String?
    @State private var identity:NumberEditIdentity?
    @State private var error=""
    @FocusState private var focused:Bool
    private var formatted:String {value.map(String.init).joined(separator:"+")}
    var body:some View {
        VStack(alignment:.leading,spacing:4) {
            HStack(spacing:8) {
                Text("강세").foregroundStyle(StudioTheme.secondary)
                TextField("없음 · 예: 2+2+3",text:Binding(get:{text},set:{newValue in
                    guard newValue != text else {return}
                    if baseline==nil {baseline=formatted;identity=context.beforeTyping()}
                    text=newValue
                })).textFieldStyle(StudioFieldStyle()).frame(maxWidth:190).focused($focused).accessibilityLabel("강세 묶음")
                    .onSubmit{commit()}.onExitCommand{reset();focused=false}
                if baseline != nil {
                    Button{commit()}label:{Image(systemName:"checkmark")}.accessibilityLabel("강세 적용").help("강세 적용 · Return")
                    Button{reset();focused=false}label:{Image(systemName:"xmark")}.accessibilityLabel("강세 취소").help("강세 취소 · Esc")
                }
            }
            if !error.isEmpty {Text(error).font(.system(size:11)).foregroundStyle(Color.red).fixedSize(horizontal:false,vertical:true)}
        }.onAppear{reset()}.onChange(of:value){_,_ in if baseline==nil {reset()}}
    }
    private func reset() {text=formatted;baseline=nil;identity=nil;error=""}
    private func commit() {
        guard let baseline else {return}
        if text==baseline {reset();focused=false;return}
        guard identity==context.current(),formatted==baseline else {error="설정이 변경되었습니다. 취소한 뒤 다시 입력하세요";return}
        do {
            _=try MusicContextEditing.parseAccents(text)
            if apply(text) {self.baseline=nil;identity=nil;error="";focused=false}
        } catch {self.error=error.localizedDescription}
    }
}
