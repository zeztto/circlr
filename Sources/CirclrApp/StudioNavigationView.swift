import SwiftUI
import CirclrCore

extension AppStore {
    var studioRoutes:[StudioSectionRoute] {
        if navigationCacheRevision != hierarchyRevision {
            navigationCacheRevision=hierarchyRevision
            navigationCache=(try? StudioNavigation.build(project)) ?? []
        }
        return navigationCache
    }
    var currentStudioSection:StudioSectionRoute? {
        guard let use=selectedUse else{return nil}
        return studioRoutes.first{$0.id == .section(arrangementID:project.activeArrangementID,useID:use.id)}
    }
    var currentStudioTrack:StudioTrackRoute? {currentStudioSection?.tracks.first{$0.id==selectedTrackID}}
    func showNavigation(){libraryOpen=false;commandPalette=nil;keyboardHelp=false;navigationOpen=true}
    func navigateStudio(_ destination:CircleAddress,track:ID?=nil) {
        do {
            var revealed=project;try StudioNavigation.reveal(destination,in:&revealed)
            if revealed != project {mutate("작업 경로 펼치기",musical:false){$0=revealed}}
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
                        Menu {
                            ForEach(items){item in Button(item.name+(item.connected ? "":" · 미연결")){store.navigateStudio(item.id,track:route.id)}}
                        } label:{title(role,selected:items.contains{$0.id==store.hierarchySelection})}
                            .menuStyle(.borderlessButton).fixedSize().accessibilityLabel(route.name+" · "+displayName(role))
                    }
                }
            }
        }
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
    var body:some View {
        if let route=store.currentStudioTrack {
            HStack(spacing:8) {
                Button{store.showNavigation()}label:{Label(route.name,systemImage:"arrow.left.arrow.right").lineLimit(1)}
                    .help("다른 트랙으로 이동 · ⌘J")
                Spacer(minLength:4)
                StudioRouteButtons(store:store,route:route).buttonStyle(.plain)
                if store.canInsertMusicEffect {
                    Menu("이펙트 추가") {
                        ForEach(EffectKind.allCases,id:\.self) {kind in Button(AppStore.effectName(kind)){store.addMusicEffect(kind)}}
                    }.menuStyle(.borderlessButton).fixedSize().help("선택한 오디오 경로에 이펙터 추가")
                }
            }.padding(.vertical,2)
        }
    }
}

struct StudioNavigationView:View {
    @ObservedObject var store:AppStore
    @State private var query=""
    @State private var sectionID:CircleAddress?
    @State private var selection=0
    struct Row:Identifiable {
        var section:StudioSectionRoute
        var track:StudioTrackRoute
        var id:String {"\(section.id):\(track.id)"}
        var primary:StudioDestination? {
            track.destinations.first{["MIDI","오디오"].contains($0.role) && $0.connected}
                ?? track.destinations.first{$0.connected} ?? track.destinations.first
        }
    }
    var section:StudioSectionRoute? {store.studioRoutes.first{$0.id==sectionID} ?? store.currentStudioSection ?? store.studioRoutes.first}
    var rows:[Row] {
        let terms=query.split(whereSeparator:{$0.isWhitespace}).map(String.init)
        let sections=terms.isEmpty ? section.map{[$0]} ?? []:store.studioRoutes
        return sections.flatMap { section in section.tracks.compactMap {track in
            let text=section.path+" "+section.name+" "+track.name+" "+track.destinations.map{$0.name+" "+$0.role}.joined(separator:" ")
            return terms.allSatisfy{text.localizedCaseInsensitiveContains($0)} ? Row(section:section,track:track):nil
        }}
    }
    var body:some View {
        VStack(spacing:0) {
            HStack {
                Text("작업 이동").font(.system(size:18,weight:.semibold))
                Spacer();Button("닫기 · Esc"){close()}.foregroundStyle(StudioTheme.secondary)
            }.padding(18)
            HStack(spacing:10) {
                Image(systemName:"magnifyingglass").foregroundStyle(StudioTheme.secondary)
                CommandSearchField(text:$query,onMove:{delta in selection=max(0,min(rows.count-1,selection+delta))},onSubmit:openSelected,onCancel:close,placeholder:"섹션 · 트랙 · 이펙트 검색")
            }.padding(.horizontal,18).padding(.bottom,15)
            if let section {
                HStack {
                    Menu {
                        ForEach(store.studioRoutes){section in Button(section.path+" › "+section.name){sectionID=section.id;query="";selection=0}}
                    }label:{Label(section.name,systemImage:"circle.grid.2x2").lineLimit(1)}
                        .menuStyle(.borderlessButton).accessibilityLabel("작업할 섹션 선택")
                    Spacer()
                    Button("섹션 보기"){store.navigateStudio(section.id)}
                }.padding(.horizontal,18).padding(.vertical,10).background(StudioTheme.raised.opacity(0.5))
            }
            ScrollViewReader { proxy in
                ScrollView {
                    if rows.isEmpty {Text(store.studioRoutes.isEmpty ? "섹션을 만들면 트랙으로 바로 이동할 수 있습니다":"일치하는 트랙이 없습니다").foregroundStyle(StudioTheme.secondary).padding(30)}
                    LazyVStack(spacing:1) {
                        ForEach(Array(rows.enumerated()),id:\.element.id){index,row in
                            HStack(spacing:12) {
                                Button {open(row)} label:{
                                    VStack(alignment:.leading,spacing:5) {
                                        Text(row.track.name).font(.system(size:14,weight:.medium)).lineLimit(1)
                                        Text(row.section.path+" › "+row.section.name).font(.system(size:11)).foregroundStyle(StudioTheme.secondary).lineLimit(1)
                                    }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                StudioRouteButtons(store:store,route:row.track).buttonStyle(.plain)
                            }.padding(.horizontal,14).padding(.vertical,10)
                                .background(selection==index ? StudioTheme.raised:Color.clear,in:RoundedRectangle(cornerRadius:6))
                                .id(row.id)
                        }
                    }.padding(8)
                }.frame(maxHeight:350)
                .onChange(of:selection){_,value in if rows.indices.contains(value){proxy.scrollTo(rows[value].id,anchor:.center)}}
                .onChange(of:query){_,_ in selection=0;if let first=rows.first{proxy.scrollTo(first.id,anchor:.top)}}
            }
            Divider().overlay(StudioTheme.line)
            HStack{Text("↑ ↓ 선택 · Return 연주 편집 · 각 버튼으로 바로 이동");Spacer();Text("⌘J")}
                .font(.system(size:11)).foregroundStyle(StudioTheme.secondary).padding(14)
        }.frame(width:760).background(StudioTheme.surface,in:RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(StudioTheme.line))
            .onAppear{sectionID=store.currentStudioSection?.id}
    }
    func open(_ row:Row){if let target=row.primary{store.navigateStudio(target.id,track:row.track.id)}}
    func openSelected(){if rows.indices.contains(selection){open(rows[selection])}}
    func close(){store.navigationOpen=false;store.focusCanvas?()}
}
