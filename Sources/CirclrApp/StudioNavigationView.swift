import SwiftUI
import CirclrCore

struct StudioNavigationIntent {
    var id=UUID()
    var anchorSectionID:CircleAddress?
    var sectionID:CircleAddress?
    var trackID:ID?
    var role:StudioNavigationRole?
}

extension AppStore {
    var studioRoutes:[StudioSectionRoute] {
        if navigationCacheRevision != hierarchyRevision {
            navigationCacheRevision=hierarchyRevision
            navigationCache=(try? StudioNavigation.build(project)) ?? []
            navigationEntryCache=StudioNavigationSearch.catalog(navigationCache,trackOrder:project.tracks.map(\.id))
        }
        return navigationCache
    }
    var studioNavigationEntries:[StudioNavigationEntry] {_=studioRoutes;return navigationEntryCache}
    var currentStudioSection:StudioSectionRoute? {
        guard let use=selectedUse else{return nil}
        return studioRoutes.first{$0.id == .section(arrangementID:project.activeArrangementID,useID:use.id)}
    }
    var currentStudioTrack:StudioTrackRoute? {currentStudioSection?.tracks.first{$0.id==selectedTrackID}}
    func showNavigation(section:CircleAddress?=nil,track:ID?=nil,role:StudioNavigationRole?=nil) {
        arrangementPickerRequest=nil
        soundPickerRequest=nil;libraryOpen=false;commandPalette=nil;keyboardHelp=false
        navigationIntent=StudioNavigationIntent(anchorSectionID:section ?? currentStudioSection?.id,sectionID:section,trackID:track,role:role)
        navigationOpen=true
    }
    func navigateStudio(_ destination:CircleAddress,track:ID?=nil) {
        do {
            _ = try StudioNavigation.scene(revealing:destination,in:project)
            navigationOpen=false;hierarchySettingsOpen=false;hierarchyTransitionID=nil
            if let track {selectedTrackID=track}
            focusCanvas?();focusHierarchy(destination,detail:{if case .music=destination{return true};return false}())
        }catch{fail(error)}
    }
    func openTrackComponent(_ index:Int) {
        guard let track=currentStudioTrack else{return}
        let roles=index==0 ? ["MIDI","오디오"]:index==1 ? ["악기"]:["이펙터"]
        let choices=track.destinations.filter{roles.contains($0.role)}
        if let destination=choices.first(where:\.connected) ?? choices.first {navigateStudio(destination.id,track:track.id)}
    }
}

struct StudioRouteButtons:View {
    @ObservedObject var store:AppStore
    let route:StudioTrackRoute
    var body:some View {
        HStack(spacing:4) {
            ForEach(["MIDI","오디오","악기","이펙터","오디오 라우터","믹스","출력"],id:\.self) { role in
                let items=route.destinations.filter{$0.role==role}
                if let first=items.first {
                    if items.count==1 {
                        Button{store.navigateStudio(first.id,track:route.id)}label:{title(role,selected:store.hierarchySelection==first.id)}
                            .help(first.name+(first.connected ? "":" · 출력에 연결되지 않은 원본"))
                            .accessibilityLabel(route.name+" · "+displayName(role))
                    } else {
                        searchButton(role,items:items)
                    }
                }
            }
        }
    }
    private func searchButton(_ role:String,items:[StudioDestination])->some View {
        let name=displayName(role),count=String(items.count)
        let label=route.name+" · "+name+" 검색 · "+count+"개"
        return Button {
            guard let first=items.first,case .music(let a,let u,_)=first.id else{return}
            store.showNavigation(section:.section(arrangementID:a,useID:u),track:route.id,role:StudioNavigationRole(source:role))
        } label:{
            Label(name+" · "+count,systemImage:"magnifyingglass").font(.system(size:12,weight:.medium))
                .foregroundStyle(items.contains{$0.id==store.hierarchySelection} ? StudioTheme.accent:StudioTheme.text)
                .padding(.horizontal,9).padding(.vertical,7).background(StudioTheme.raised,in:RoundedRectangle(cornerRadius:5))
        }.fixedSize().help(count+"개 "+name+" 서클 검색 · ↑↓·Return으로 바로 이동").accessibilityLabel(label)
    }
    func displayName(_ role:String)->String {role=="악기" ? "음색":role=="이펙터" ? "이펙트":role=="오디오 라우터" ? "라우터":role}
    func title(_ role:String,selected:Bool)->some View {
        Text(displayName(role)).font(.system(size:12,weight:selected ? .semibold:.medium))
            .foregroundStyle(selected ? StudioTheme.accent:StudioTheme.text)
            .padding(.horizontal,9).padding(.vertical,7)
            .background(StudioTheme.raised,in:RoundedRectangle(cornerRadius:5))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
struct StudioRouteBar:View {
    @ObservedObject var store:AppStore
    private var showsBounceStatus:Bool {
        (store.trackBounceAssessment.map{store.trackBounceStatus($0) != nil} ?? false) || store.bounceTailNotice != nil
    }
    var body:some View {
        if let route=store.currentStudioTrack {
            if showsBounceStatus {
                ViewThatFits(in:.horizontal) {
                    HStack(spacing:8) {
                        trackButton(route).frame(maxWidth:110)
                        TrackBounceStatus(store:store).frame(minWidth:280)
                        routeControls(route).fixedSize(horizontal:true,vertical:false)
                    }
                    HStack(spacing:8) {
                        trackButton(route).frame(maxWidth:110)
                        TrackBounceStatus(store:store).frame(minWidth:280)
                        ScrollView(.horizontal) {routeControls(route)}
                            .frame(width:250,height:32)
                    }
                }.padding(.vertical,2)
            }else{
                HStack(spacing:8) {
                    trackButton(route)
                    Spacer(minLength:4)
                    routeControls(route)
                }.padding(.vertical,2)
            }
        }else if showsBounceStatus {
            TrackBounceStatus(store:store)
        }
    }
    private func trackButton(_ route:StudioTrackRoute)->some View {
        Button{store.showNavigation()}label:{Label(route.name,systemImage:"arrow.left.arrow.right").lineLimit(1)}
            .help(route.name+" · 다른 트랙으로 이동 · ⌘J")
    }
    private func routeControls(_ route:StudioTrackRoute)->some View {
        HStack(spacing:8) {
            StudioRouteButtons(store:store,route:route).buttonStyle(.plain)
            if store.canInsertMusicEffect {
                Menu("이펙트 추가") {
                    ForEach(EffectKind.allCases,id:\.self) {kind in Button(AppStore.effectName(kind)){store.addMusicEffect(kind)}}
                }.menuStyle(.borderlessButton).fixedSize().help("선택한 오디오 경로에 이펙터 추가")
            }
        }
    }
}

struct StudioNavigationView:View {
    @ObservedObject var store:AppStore
    let projectID:ID
    let anchorSectionID:CircleAddress?
    @State private var query=""
    @State private var sectionID:CircleAddress?
    @State private var trackID:ID?
    @State private var role:StudioNavigationRole?
    @State private var highlighted:StudioNavigationEntryID?
    @State private var searchFocus=UUID()
    @State private var notice=""
    init(store:AppStore) {
        self.store=store;projectID=store.project.id;anchorSectionID=store.navigationIntent.anchorSectionID
        _sectionID=State(initialValue:store.navigationIntent.sectionID)
        _trackID=State(initialValue:store.navigationIntent.trackID)
        _role=State(initialValue:store.navigationIntent.role)
    }
    private var rows:[StudioNavigationEntry] {
        StudioNavigationSearch.search(store.studioNavigationEntries,query:query,sectionID:sectionID,trackID:trackID,role:role)
    }
    private var currentEntry:StudioNavigationEntry? {store.studioNavigationEntries.first{$0.target==store.hierarchySelection && ($0.trackID==nil || $0.trackID==store.selectedTrackID)}}
    private var active:StudioNavigationEntryID? {rows.contains{$0.id==highlighted} ? highlighted:rows.first?.id}
    private var scopeName:String {
        if let sectionID {return store.studioRoutes.first{$0.id==sectionID}.map{$0.path+" › "+$0.name} ?? "삭제된 섹션"}
        return "전체 앨범"
    }
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack {
                Text("작업 이동").font(.system(size:18,weight:.semibold))
                Spacer();Button("닫기 · Esc"){close()}.foregroundStyle(StudioTheme.secondary)
            }.padding(18)
            HStack(spacing:10) {
                Image(systemName:"magnifyingglass").foregroundStyle(StudioTheme.secondary)
                CommandSearchField(text:$query,onMove:move,onSubmit:openSelected,onCancel:close,placeholder:"섹션 · 트랙 · 서클 이름 · 종류 검색").id(searchFocus)
            }.padding(.horizontal,18).padding(.bottom,14)
            HStack(spacing:8) {
                filterButton("전체 앨범",selected:sectionID==nil){sectionID=nil;refocus()}
                filterButton("이 섹션",selected:sectionID != nil){sectionID=anchorSectionID;refocus()}.disabled(anchorSectionID==nil)
                Spacer()
                Button("현재 서클 찾기"){query="";sectionID=nil;trackID=nil;role=nil;selectCurrent();searchFocus=UUID()}
                    .disabled(currentEntry==nil).help("검색과 필터를 해제하고 현재 선택을 목록에서 찾습니다")
            }.padding(.horizontal,18).padding(.bottom,10)
            HStack(spacing:4) {
                filterButton("전체 종류",selected:role==nil){role=nil;refocus()}
                ForEach(StudioNavigationRole.allCases){item in filterButton(item.label,selected:role==item){role=item;refocus()}}
            }.padding(.horizontal,18).padding(.bottom,10)
            HStack(alignment:.top,spacing:8) {
                Text(scopeName+(trackID.map{" › "+AudioImportPlacement.trackLabel($0,in:store.project)} ?? ""))
                    .lineLimit(2).help(scopeName+(trackID.map{" › "+AudioImportPlacement.trackLabel($0,in:store.project)} ?? ""))
                if trackID != nil {Button("트랙 제한 해제"){trackID=nil;refocus()}}
                Spacer(minLength:4);Text("\(rows.count)개 결과").monospacedDigit().fixedSize()
            }.font(.system(size:12)).foregroundStyle(StudioTheme.secondary).padding(.horizontal,18).padding(.bottom,12)
            if !notice.isEmpty {Text(notice).foregroundStyle(StudioTheme.accent).font(.system(size:12)).padding(.horizontal,18).padding(.bottom,8)}
            ScrollViewReader { proxy in
                ScrollView {
                    if rows.isEmpty {
                        Text(store.studioRoutes.isEmpty ? "섹션을 만들면 작업할 서클이 표시됩니다":"일치하는 작업이 없습니다. 검색어나 종류·범위를 바꿔보세요.")
                            .foregroundStyle(StudioTheme.secondary).font(.system(size:13)).padding(30)
                    }
                    LazyVStack(spacing:1) {
                        ForEach(rows){entry in
                            Button{open(entry)}label:{
                                HStack(spacing:12) {
                                    VStack(alignment:.leading,spacing:6) {
                                        Text(entry.title).font(.system(size:14,weight:.medium)).lineLimit(2)
                                        Text(entry.detail).font(.system(size:12)).foregroundStyle(StudioTheme.secondary).lineLimit(2)
                                    }.frame(maxWidth:.infinity,alignment:.leading)
                                    if entry.target==store.hierarchySelection && (entry.trackID==nil || entry.trackID==store.selectedTrackID) {
                                        Text("현재").font(.system(size:12)).foregroundStyle(StudioTheme.accent)
                                    }
                                }.padding(.horizontal,18).padding(.vertical,12).contentShape(Rectangle())
                                    .background(active==entry.id ? StudioTheme.raised:Color.clear)
                            }.buttonStyle(.plain).id(entry.id).disabled(store.project.id != projectID)
                                .accessibilityLabel(entry.title+" · "+entry.detail).help(entry.title+" · "+entry.detail)
                                .accessibilityAddTraits(active==entry.id ? .isSelected:[])
                        }
                    }
                }.onChange(of:active){_,id in if let id{proxy.scrollTo(id,anchor:.center)}}
                    .onChange(of:query){_,value in
                        if value.isEmpty{selectCurrent()}else{highlighted=rows.first?.id}
                        notice="";if let active{proxy.scrollTo(active,anchor:.center)}
                    }
                    .onChange(of:rows.map(\.id)){_,ids in if let highlighted,!ids.contains(highlighted){self.highlighted=ids.first}}
            }
            Divider().overlay(StudioTheme.line)
            Text("↑↓ 선택 · Return 표시된 작업 열기 · Esc 캔버스로 복귀 · ⌘J")
                .font(.system(size:12)).foregroundStyle(StudioTheme.secondary).padding(18)
        }.frame(width:850,height:560).background(StudioTheme.surface,in:RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(StudioTheme.line))
            .onAppear{selectCurrent()}
    }
    private func filterButton(_ text:String,selected:Bool,action:@escaping()->Void)->some View {
        Button(action:action){Text(text).font(.system(size:12,weight:selected ? .semibold:.medium))
            .foregroundStyle(selected ? StudioTheme.accent:StudioTheme.text).padding(.horizontal,9).padding(.vertical,7)
            .background(selected ? StudioTheme.raised:Color.clear,in:RoundedRectangle(cornerRadius:5))}
            .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected:[])
    }
    private func selectCurrent() {
        highlighted=rows.first{$0.target==store.hierarchySelection && ($0.trackID==nil || $0.trackID==store.selectedTrackID)}?.id ?? rows.first?.id
    }
    private func refocus(){highlighted=nil;notice="";searchFocus=UUID()}
    private func move(_ delta:Int) {
        guard !rows.isEmpty else{return}
        let index=rows.firstIndex{$0.id==active} ?? 0
        highlighted=rows[max(0,min(rows.count-1,index+delta))].id
    }
    private func open(_ entry:StudioNavigationEntry) {
        guard store.project.id==projectID,rows.contains(where:{$0.id==entry.id}) else{notice="대상이 변경됐습니다. 현재 목록에서 다시 선택하세요.";return}
        store.navigateStudio(entry.target,track:entry.trackID)
    }
    private func openSelected(){if let entry=rows.first(where:{$0.id==active}){open(entry)}}
    private func close(){store.navigationOpen=false;store.focusCanvas?()}
}
