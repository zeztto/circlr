import SwiftUI
import CirclrCore

struct StudioNavigationIntent {
    var id=UUID()
    var anchorSectionID:CircleAddress?
    var sectionID:CircleAddress?
    var trackID:ID?
    var role:StudioNavigationRole?
    var roles:[StudioNavigationRole]?
    var workspaceIntent:CircleWorkspaceIntent?
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
    func showNavigation(section:CircleAddress?=nil,track:ID?=nil,role:StudioNavigationRole?=nil,roles:[StudioNavigationRole]?=nil,workspaceIntent:CircleWorkspaceIntent?=nil) {
        var scope=numberEditIdentity
        guard resolveActiveNumericDraft(),nameEditing.resolve() else{return}
        scope.revision=project.musicRevision
        guard scope==numberEditIdentity else{return}
        arrangementPickerRequest=nil
        soundPickerRequest=nil;libraryOpen=false;commandPalette=nil;keyboardHelp=false
        navigationIntent=StudioNavigationIntent(anchorSectionID:section ?? currentStudioSection?.id,sectionID:section,trackID:track,role:role,roles:roles,workspaceIntent:workspaceIntent)
        navigationOpen=true
    }
    @discardableResult func navigateStudio(_ destination:CircleAddress,track:ID?=nil,explicitIntent:CircleWorkspaceIntent?=nil)->Bool {
        guard focusUserWorkspace(destination,detail:{if case .music=destination{return true};return false}(),explicitIntent:explicitIntent) else{return false}
        navigationOpen=false
        // Selection resolves concrete source owners. A routing destination may
        // use the caller's track only when it still reaches that output.
        if let track,let node=selectedMusic,let graph=selectedGraph {
            switch node.content {
            case .effect,.mix,.router:if StudioNavigation.outputTracks(from:node.id,graph:graph).contains(track){selectedTrackID=track}
            default:break
            }
        }
        return true
    }
    func openTrackComponent(_ index:Int) {
        guard (0...2).contains(index),let track=currentStudioTrack else{status="작업할 섹션과 트랙을 선택하세요";return}
        let roles:[StudioNavigationRole]=index==0 ? [.midi,.audio]:index==1 ? [.instrument]:[.effect]
        openTrackRoles(roles,trackID:track.id)
    }
    func openTrackRoles(_ roles:[StudioNavigationRole],trackID:ID,workspaceIntent:CircleWorkspaceIntent?=nil) {
        guard nameEditing.resolve(),let section=currentStudioSection,let track=currentStudioTrack,track.id==trackID else{return}
        let choices=track.destinations.filter{destination in
            StudioNavigationRole(source:destination.role).map{roles.contains($0)} ?? false
        }
        if choices.count==1,let destination=choices.first {navigateStudio(destination.id,track:track.id,explicitIntent:workspaceIntent)}
        else {
            showNavigation(section:section.id,track:track.id,role:roles.count==1 ? roles.first:nil,
                           roles:roles.count>1 ? roles:nil,workspaceIntent:workspaceIntent)
        }
    }
}

struct StudioRouteButtons:View {
    @ObservedObject var store:AppStore
    let route:StudioTrackRoute
    var body:some View {
        Group {
            ForEach(["MIDI","오디오","악기","이펙터","오디오 라우터","믹스","출력"],id:\.self) { role in
                let items=route.destinations.filter{$0.role==role}
                if let first=items.first {
                    if items.count==1 {
                        if first.id != store.hierarchySelection {
                            Button{if let kind=StudioNavigationRole(source:role){store.openTrackRoles([kind],trackID:route.id)}}label:{title(role,selected:false)}
                                .fixedSize(horizontal:true,vertical:false)
                                .help(first.name+(first.connected ? "":" · 출력에 연결되지 않은 원본"))
                                .accessibilityLabel(route.name+" · "+displayName(role))
                        }
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
            guard let kind=StudioNavigationRole(source:role) else{return}
            store.openTrackRoles([kind],trackID:route.id)
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
                        HStack(spacing:8) {routeControls(route)}.fixedSize(horizontal:true,vertical:false)
                    }
                    HStack(spacing:8) {
                        trackButton(route).frame(maxWidth:110)
                        TrackBounceStatus(store:store).frame(minWidth:280)
                        ScrollView(.horizontal) {HStack(spacing:8) {routeControls(route)}}
                            .frame(width:250,height:32)
                    }
                }.padding(.vertical,2)
            }else{
                StudioRouteBarLayout {
                    trackButton(route)
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
        Group {
            StudioRouteButtons(store:store,route:route).buttonStyle(.plain)
            if store.canInsertMusicEffect {
                Menu("이펙트 추가") {
                    ForEach(EffectKind.allCases,id:\.self) {kind in Button(AppStore.effectName(kind)){store.addMusicEffect(kind)}}
                }.menuStyle(.borderlessButton).fixedSize().help("선택한 오디오 경로에 이펙터 추가")
            }
        }
    }
}

private struct StudioRouteBarLayout:SwiftUI.Layout {
    let gap:CGFloat=8
    private func arrangement(width:CGFloat,subviews:Subviews)->(positions:[CGPoint],sizes:[CGSize],height:CGFloat) {
        guard let title=subviews.first else{return ([],[],0)}
        let titleSize=title.sizeThatFits(ProposedViewSize(width:width,height:nil))
        let controls=subviews.dropFirst().map{$0.sizeThatFits(.unspecified)}
        let controlsWidth=controls.reduce(CGFloat.zero){$0+$1.width}+CGFloat(max(0,controls.count-1))*gap
        let naturalTitle=title.sizeThatFits(.unspecified)
        if naturalTitle.width+gap+controlsWidth<=width {
            let height=max(naturalTitle.height,controls.map(\.height).max() ?? 0)
            var positions=[CGPoint(x:0,y:(height-naturalTitle.height)/2)],x=width-controlsWidth
            for size in controls {positions.append(CGPoint(x:x,y:(height-size.height)/2));x+=size.width+gap}
            return (positions,[naturalTitle]+controls,height)
        }
        var positions=[CGPoint.zero],x:CGFloat=0,y=titleSize.height+gap,rowHeight:CGFloat=0
        for size in controls {
            if x>0,x+size.width>width {x=0;y+=rowHeight+gap;rowHeight=0}
            positions.append(CGPoint(x:x,y:y));x+=size.width+gap;rowHeight=max(rowHeight,size.height)
        }
        return (positions,[titleSize]+controls,controls.isEmpty ? titleSize.height:y+rowHeight)
    }
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ())->CGSize {
        let ideal=subviews.reduce(CGFloat.zero){$0+$1.sizeThatFits(.unspecified).width}+CGFloat(max(0,subviews.count-1))*gap
        let width=proposal.width ?? ideal
        return CGSize(width:width,height:arrangement(width:width,subviews:subviews).height)
    }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        let result=arrangement(width:bounds.width,subviews:subviews)
        for index in subviews.indices {
            let position=result.positions[index],size=result.sizes[index]
            subviews[index].place(at:CGPoint(x:bounds.minX+position.x,y:bounds.minY+position.y),anchor:.topLeading,
                proposal:ProposedViewSize(width:size.width,height:size.height))
        }
    }
}

struct StudioNavigationView:View {
    @ObservedObject var store:AppStore
    let size:CGSize
    let projectID:ID
    let anchorSectionID:CircleAddress?
    @State private var query=""
    @State private var sectionID:CircleAddress?
    @State private var trackID:ID?
    @State private var role:StudioNavigationRole?
    @State private var roles:[StudioNavigationRole]?
    @State private var highlighted:StudioNavigationEntryID?
    @State private var searchFocus=UUID()
    @State private var notice=""
    @FocusState private var keyboardFocus:String?
    init(store:AppStore,size:CGSize) {
        self.store=store;self.size=size;projectID=store.project.id;anchorSectionID=store.navigationIntent.anchorSectionID
        _sectionID=State(initialValue:store.navigationIntent.sectionID)
        _trackID=State(initialValue:store.navigationIntent.trackID)
        _role=State(initialValue:store.navigationIntent.role)
        _roles=State(initialValue:store.navigationIntent.roles)
    }
    private var rows:[StudioNavigationEntry] {
        StudioNavigationSearch.search(store.studioNavigationEntries,query:query,sectionID:sectionID,trackID:trackID,role:role)
            .filter{entry in roles.map{$0.contains(entry.role)} ?? true}
    }
    private var emptyDescription:String {
        if store.studioRoutes.isEmpty {return "섹션을 만들면 작업할 서클이 표시됩니다"}
        if query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,trackID != nil {
            let kinds=roles?.map(\.label).joined(separator:"·") ?? role?.label ?? "선택한 종류의"
            return "이 트랙에 "+kinds+" 작업이 없습니다. 종류·범위를 바꿔보세요."
        }
        return "일치하는 작업이 없습니다. 검색어나 종류·범위를 바꿔보세요."
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
                Spacer();Button("닫기 · Esc"){close()}.frame(minHeight:32).foregroundStyle(StudioTheme.secondary)
                    .focusable().focused($keyboardFocus,equals:"close")
            }.padding(18)
            HStack(spacing:10) {
                Image(systemName:"magnifyingglass").foregroundStyle(StudioTheme.secondary)
                CommandSearchField(text:$query,onMove:move,onSubmit:openSelected,onCancel:close,placeholder:"섹션 · 트랙 · 서클 이름 · 종류 검색").id(searchFocus).frame(minHeight:32)
                    .focused($keyboardFocus,equals:"search")
            }.padding(.horizontal,18).padding(.bottom,14)
            HStack(spacing:8) {
                filterButton("전체 앨범",selected:sectionID==nil){sectionID=nil;refocus()}
                filterButton("이 섹션",selected:sectionID != nil){sectionID=anchorSectionID;refocus()}.disabled(anchorSectionID==nil)
                Spacer()
                Button("현재 서클 찾기"){query="";sectionID=nil;trackID=nil;role=nil;roles=nil;selectCurrent();searchFocus=UUID();keyboardFocus="search"}
                    .disabled(currentEntry==nil).help("검색과 필터를 해제하고 현재 선택을 목록에서 찾습니다")
                    .focusable().focused($keyboardFocus,equals:"current")
            }.padding(.horizontal,18).padding(.bottom,10)
            if size.width<760 {
                Menu {
                    Button("전체 종류"){role=nil;roles=nil;refocus()}
                    if let group=roles {Button(group.map(\.label).joined(separator:"·")){role=nil;refocus()}}
                    ForEach(StudioNavigationRole.allCases){item in
                        Button(item.label){role=item;roles=nil;refocus()}
                    }
                }label:{Label(role?.label ?? roles?.map(\.label).joined(separator:"·") ?? "전체 종류",systemImage:"line.3.horizontal.decrease")}
                    .accessibilityLabel("작업 종류 선택")
                    .focusable().focused($keyboardFocus,equals:"role-menu")
                    .padding(.horizontal,18).frame(height:32,alignment:.leading).padding(.bottom,10)
            } else {
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack(spacing:4) {
                        filterButton("전체 종류",selected:role==nil && roles==nil){role=nil;roles=nil;refocus()}
                        if let group=roles {filterButton(group.map(\.label).joined(separator:"·"),selected:true){role=nil;refocus()}}
                        ForEach(StudioNavigationRole.allCases){item in filterButton(item.label,selected:role==item && roles==nil){role=item;roles=nil;refocus()}}
                    }.padding(.horizontal,18)
                }.frame(height:32).padding(.bottom,10)
            }
            HStack(alignment:.top,spacing:8) {
                Text(scopeName+(trackID.map{" › "+AudioImportPlacement.trackLabel($0,in:store.project)} ?? ""))
                    .lineLimit(2).help(scopeName+(trackID.map{" › "+AudioImportPlacement.trackLabel($0,in:store.project)} ?? ""))
                if trackID != nil {Button("트랙 제한 해제"){trackID=nil;refocus()}.focusable().focused($keyboardFocus,equals:"clear-track")}
                Spacer(minLength:4);Text("\(rows.count)개 결과").monospacedDigit().fixedSize()
            }.font(.system(size:12)).foregroundStyle(StudioTheme.secondary).padding(.horizontal,18).padding(.bottom,12)
            if !notice.isEmpty {Text(notice).foregroundStyle(StudioTheme.accent).font(.system(size:12)).padding(.horizontal,18).padding(.bottom,8)}
            ScrollViewReader { proxy in
                ScrollView {
                    if rows.isEmpty {
                        Text(emptyDescription)
                            .foregroundStyle(StudioTheme.secondary).font(.system(size:13)).padding(30)
                    }
                    LazyVStack(spacing:1) {
                        ForEach(Array(rows.enumerated()),id:\.element.id){index,entry in row(entry,index:index)}
                    }
                }.onChange(of:active){_,id in if let id{proxy.scrollTo(id,anchor:.center)}}
                    .onChange(of:keyboardFocus){_,focus in
                        guard let focus,focus.hasPrefix("row-"),let index=Int(focus.dropFirst(4)),rows.indices.contains(index) else{return}
                        proxy.scrollTo(rows[index].id,anchor:.center)
                    }
                    .onChange(of:query){_,value in
                        if value.isEmpty{selectCurrent()}else{highlighted=rows.first?.id}
                        notice="";if let active{proxy.scrollTo(active,anchor:.center)}
                    }
                    .onChange(of:rows.map(\.id)){_,ids in if let highlighted,!ids.contains(highlighted){self.highlighted=ids.first}}
            }
            Divider().overlay(StudioTheme.line)
            Text(size.height<500 ? "↑↓ 선택 · Return 열기 · Esc 닫기":"↑↓ 선택 · Return 표시된 작업 열기 · Esc 캔버스로 복귀 · ⌘J")
                .font(.system(size:12)).foregroundStyle(StudioTheme.secondary).padding(size.height<500 ? 10:18)
        }.frame(width:size.width,height:size.height).background(StudioTheme.surface,in:RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(StudioTheme.line))
            .background(OverlayKeyboardKeys(active:{store.navigationOpen},move:moveKeyboardFocus,cancel:close).frame(width:0,height:0))
            .onAppear{selectCurrent()}
    }
    private func filterButton(_ text:String,selected:Bool,action:@escaping()->Void)->some View {
        Button(action:action){Text(text).font(.system(size:12,weight:selected ? .semibold:.medium))
            .foregroundStyle(selected ? StudioTheme.accent:StudioTheme.text).padding(.horizontal,9).padding(.vertical,7)
            .background(selected ? StudioTheme.raised:Color.clear,in:RoundedRectangle(cornerRadius:5))}
            .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected:[])
            .focusable().focused($keyboardFocus,equals:"filter-\(text)")
    }
    private func row(_ entry:StudioNavigationEntry,index:Int)->some View {
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
            .focusable().focused($keyboardFocus,equals:"row-\(index)")
    }
    private func selectCurrent() {
        highlighted=rows.first{$0.target==store.hierarchySelection && ($0.trackID==nil || $0.trackID==store.selectedTrackID)}?.id ?? rows.first?.id
    }
    private func refocus(){highlighted=nil;notice="";searchFocus=UUID();keyboardFocus="search"}
    private var keyboardOrder:[String] {
        var order=["search","close","filter-전체 앨범"]
        if anchorSectionID != nil {order.append("filter-이 섹션")}
        if currentEntry != nil {order.append("current")}
        if size.width<760 {order.append("role-menu")}
        else {
            order.append("filter-전체 종류")
            if let roles {order.append("filter-"+roles.map(\.label).joined(separator:"·"))}
            order += StudioNavigationRole.allCases.map{"filter-\($0.label)"}
        }
        if trackID != nil {order.append("clear-track")}
        if store.project.id==projectID {order += rows.indices.map{"row-\($0)"}}
        return order
    }
    private func moveKeyboardFocus(_ backward:Bool) {
        keyboardFocus=OverlayKeyboardTraversal.next(in:keyboardOrder,current:keyboardFocus,backward:backward)
    }
    private func move(_ delta:Int) {
        guard !rows.isEmpty else{return}
        let index=rows.firstIndex{$0.id==active} ?? 0
        highlighted=rows[max(0,min(rows.count-1,index+delta))].id
    }
    private func open(_ entry:StudioNavigationEntry) {
        guard store.project.id==projectID,rows.contains(where:{$0.id==entry.id}) else{notice="대상이 변경됐습니다. 현재 목록에서 다시 선택하세요.";return}
        store.navigateStudio(entry.target,track:entry.trackID,explicitIntent:store.navigationIntent.workspaceIntent)
    }
    private func openSelected(){if let entry=rows.first(where:{$0.id==active}){open(entry)}}
    private func close(){store.navigationOpen=false;store.focusCanvas?()}
}
