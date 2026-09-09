import SwiftUI
import CirclrCore

extension AppStore {
    var libraryPlacementIssue:String? {
        guard let request=libraryDestination else{return "가져올 섹션을 선택하세요"}
        if case .pattern=request.destination,library.chosen.contains(where:{$0.kind == .midi}){return "MIDI를 가져올 섹션을 선택하세요"}
        do {_=try AudioImportPlacement.start(AudioImportPlacement.beat(request.destination),of:request.destination,in:project);return nil}
        catch{return error.localizedDescription}
    }
    @discardableResult func changeLibraryPlacement(_ request:MediaImportRequest,change:(AudioImportDestination)throws->AudioImportDestination)->Bool {
        guard libraryOpen,canStartMediaImport,libraryDestinationCurrent,libraryDestination==request else{library.notice="대상이 변경됐습니다. 가져오기 대상을 갱신하세요";return false}
        do {
            let target=try change(request.destination)
            libraryDestination=MediaImportRequest(projectID:request.projectID,revision:request.revision,generation:request.generation,selection:request.selection,destination:target)
            library.notice="";return true
        }catch{library.notice=error.localizedDescription;return false}
    }
    func chooseLibrarySection(_ address:CircleAddress,projectID:ID,revision:Int,generation:Int,selection:CircleAddress?) {
        guard libraryOpen,canStartMediaImport,project.id==projectID,project.musicRevision==revision,
              mediaImportGeneration==generation,hierarchySelection==selection else{library.notice="대상이 변경됐습니다. 섹션을 다시 선택하세요";return}
        guard case .section(let a,let u)=address else{return}
        do {
            let target=AudioImportDestination.section(arrangementID:a,useID:u,trackID:nil,beat:0,position:nil,original:false)
            _=try AudioImportPlacement.clock(target,in:project)
            libraryDestination=mediaImportRequest(target);library.notice="";library.choosingDestination=false
        }catch{library.notice=error.localizedDescription}
    }
    var libraryNumberIdentity:NumberEditIdentity {
        let base=numberEditIdentity
        var arrangement=base.arrangementID,circle=base.circle,track=base.trackID,pattern=base.patternID,original=base.original
        if let request=libraryDestination {
            switch request.destination {
            case .pattern(let id,_):pattern=id
            case .section(let a,let u,let t,_,_,let shared):arrangement=a;circle = .section(arrangementID:a,useID:u);track=t;original=shared
            }
        }
        return NumberEditIdentity(projectID:base.projectID,revision:base.revision,generation:base.generation,
            arrangementID:arrangement,circle:circle,trackID:track,laneID:base.laneID,patternID:pattern,
            notes:base.notes,clipID:base.clipID,edgeID:base.edgeID,transitionID:base.transitionID,original:original,
            settings:base.settings,steps:base.steps,connections:base.connections,automation:base.automation,
            focus:base.focus,activation:base.activation,automationPoint:base.automationPoint,automationParameter:base.automationParameter)
    }
}

struct LibraryPlacementControls:View {
    @ObservedObject var store:AppStore
    @ObservedObject var library:MediaLibraryController
    let request:MediaImportRequest
    var body:some View {
        if let clock=try? AudioImportPlacement.clock(request.destination,in:store.project) {
            let beat=AudioImportPlacement.beat(request.destination)
            HStack(spacing:10) {
                Text("시작")
                CommittedNumberField(title:"라이브러리 가져오기 시작 박",value:Binding(get:{AudioImportPlacement.beat(request.destination)},set:{value in store.changeLibraryPlacement(request){try AudioImportPlacement.start(value,of:$0,in:store.project)}}),range:0...clock.beats,width:85,presentation:.beatPosition,validate:{value in _=try AudioImportPlacement.start(value,of:request.destination,in:store.project)})
                    .environment(\.numberEditing,NumberEditingContext(snapshot:store.libraryNumberIdentity,current:{store.libraryNumberIdentity},focusCanvas:{library.searchFocus=UUID()}))
                    .disabled(!store.libraryDestinationCurrent || !store.canStartMediaImport)
                Text("박 · 4분음표").foregroundStyle(StudioTheme.secondary)
                Button("처음"){store.changeLibraryPlacement(request){try AudioImportPlacement.start(0,of:$0,in:store.project)}}
                    .disabled(!store.libraryDestinationCurrent || !store.canStartMediaImport)
                if beat.isFinite,beat>=0,beat<clock.beats {
                    Text("\(clock.bar(at:beat)+1)마디 · \(clock.seconds(at:beat).formatted(.number.precision(.fractionLength(0...2))))초 / \(clock.beats.formatted())박 길이")
                        .foregroundStyle(StudioTheme.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength:4)
                if case .section(_,_,let track,_,_,_)=request.destination,library.chosen.count==1,library.chosen.first?.kind == .audio {
                    Button {
                        if let entry=library.chosen.first {library.notice="";library.workspace = .track(request,entryID:entry.id)}
                    }label:{Label(AudioImportPlacement.trackLabel(track,in:store.project),systemImage:"magnifyingglass").lineLimit(1).truncationMode(.middle)}
                        .frame(maxWidth:180).accessibilityLabel("가져올 오디오 트랙 선택")
                        .help(AudioImportPlacement.trackLabel(track,in:store.project)+" · 이름·번호로 대상 트랙 검색")
                        .disabled(!store.libraryDestinationCurrent || !store.canStartMediaImport)
                }
            }.font(.system(size:12))
        }
    }
}

struct LibrarySectionChooser:View {
    @ObservedObject var store:AppStore
    @ObservedObject var library:MediaLibraryController
    let projectID:ID
    let revision:Int
    let generation:Int
    let selection:CircleAddress?
    @State private var query=""
    @State private var selected:CircleAddress?
    private var routes:[StudioSectionRoute] {AudioImportPlacement.sections(store.studioRoutes,query:query)}
    private var active:CircleAddress? {routes.contains{$0.id==selected} ? selected:routes.first?.id}
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:10) {
                Image(systemName:"magnifyingglass").foregroundStyle(StudioTheme.secondary)
                CommandSearchField(text:$query,onMove:move,onSubmit:{if let active{choose(active)}},onCancel:{library.choosingDestination=false},placeholder:"가져올 곡 · 섹션 검색")
            }.padding(.horizontal,18).padding(.bottom,14)
            Text("섹션을 고른 뒤 파일 목록에서 시작 박과 트랙을 정합니다.")
                .font(.system(size:12)).foregroundStyle(StudioTheme.secondary).padding(.horizontal,18).padding(.bottom,14)
            if !library.notice.isEmpty {Text(library.notice).foregroundStyle(StudioTheme.accent).padding(.horizontal,18)}
            ScrollViewReader { proxy in
                ScrollView {
                    if routes.isEmpty {Text("일치하는 섹션이 없습니다").foregroundStyle(StudioTheme.secondary).padding(30)}
                    LazyVStack(spacing:1) {
                        ForEach(routes){route in
                            Button{choose(route.id)}label:{
                                VStack(alignment:.leading,spacing:6) {
                                    Text(route.name).font(.system(size:14,weight:.medium)).lineLimit(1)
                                    Text(route.path).font(.system(size:12)).foregroundStyle(StudioTheme.secondary).lineLimit(2)
                                }.frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,18).padding(.vertical,12)
                                    .background(active==route.id ? StudioTheme.raised:Color.clear)
                            }.buttonStyle(.plain).id(route.id).accessibilityLabel(route.path+" › "+route.name)
                                .accessibilityAddTraits(active==route.id ? .isSelected:[])
                        }
                    }
                }.onChange(of:active){_,id in if let id{proxy.scrollTo(id,anchor:.center)}}
            }
            Divider().overlay(StudioTheme.line)
            Text("↑↓ 선택 · Return 대상 지정 · Esc 파일 목록으로 복귀")
                .font(.system(size:12)).foregroundStyle(StudioTheme.secondary).padding(18)
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .onAppear {
            if case .section(let a,let u,_,_,_,_)=store.libraryDestination?.destination {selected = .section(arrangementID:a,useID:u)}
        }
    }
    private func move(_ delta:Int) {
        guard !routes.isEmpty else{return}
        let index=routes.firstIndex{$0.id==active} ?? 0
        selected=routes[max(0,min(routes.count-1,index+delta))].id
    }
    private func choose(_ id:CircleAddress) {store.chooseLibrarySection(id,projectID:projectID,revision:revision,generation:generation,selection:selection)}
}
