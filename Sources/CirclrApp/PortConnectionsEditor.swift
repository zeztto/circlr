import SwiftUI
import CirclrCore

struct ConnectionEditorIntent: Equatable, Codable {
    var id = UUID()
    var projectID: ID
    var node: CircleAddress
    var portID: String?
    var connection: CircleConnectionID?
}

struct ConnectionWorkspaceKey:Hashable {
    let node:CircleAddress
    let original:Bool
}

extension AppStore {
    var canEditCirclePorts:Bool {selectedCircle?.ports.isEmpty == false || selectedHierarchyGroup != nil}
    func showConnections(portID: String? = nil, replacing: CircleConnectionID? = nil) {
        guard nameEditing.resolve(),let node = selectedCircle, canEditCirclePorts else { return }
        connectionEditorIntent = .init(projectID: project.id, node: node.id, portID: portID, connection: replacing)
        connectionsOpen = true; hierarchySettingsOpen = false; focusHierarchy(node.id, detail: true)
    }
    func moveConnection(_ id: CircleConnectionID, from: PortOctant? = nil, to: PortOctant? = nil) {
        mutate("연결 위치 이동", musical: false, portLayoutOnly: true) { p in
            var placement = p.portLayout?.placement(for: id) ?? .init()
            if let from { placement.from = from }; if let to { placement.to = to }
            try CirclePortLayoutEditing.apply([.init(id: id, placement: placement)], projectID: p.id,
                expectedMusicRevision: p.musicRevision, expectedLayoutRevision: p.portLayout?.revision ?? 0, in: &p)
        }
    }
    func addMusicRouter(at point: Point? = nil) {
        guard var graph = selectedGraph, let use = selectedUse else { return }
        let node = MusicCircle(name: "오디오 라우터", content: .router(AudioRouter()))
        graph.nodes.append(node); graph.layout.positions[node.id] = point ?? Point(180, 240)
        setGraph("오디오 라우터 만들기", graph)
        if selectedGraph?.nodes.contains(where: { $0.id == node.id }) == true {
            selectHierarchy(.music(arrangementID: project.activeArrangementID, useID: use.id, nodeID: node.id)); showConnections()
        }
    }
}

/// Part of the inline canvas editor; no window or docked panel is created.
struct PortConnectionsEditor: View {
    @ObservedObject var store: AppStore
    @State private var workspace=ConnectionWorkspaceState()
    @State private var workspaceKey:ConnectionWorkspaceKey?
    @State private var workspaceProjectID:ID?
    @State private var workspaceGeneration:Int?
    let keyboard:PortKeyboardFocus
    private var isCurrentWorkspace:Bool {
        workspaceProjectID==store.project.id && workspaceGeneration==store.mediaImportGeneration && workspaceKey?.node==node?.id && workspaceKey?.original==store.editOriginal
    }
    private var node: CircleSceneNode? { store.selectedCircle }
    private var ports: [CirclePort] { node?.ports ?? [] }
    private var own: CirclePortEndpoint? {
        guard let node, ports.contains(where: { $0.id == workspace.ownPortID }) else { return nil }
        return .init(node: node.id, portID: workspace.ownPortID)
    }
    private var connections: [CirclePortConnection] {
        guard let node else {return []}
        return ((try? AgentPortEditing.snapshot(at:node.id,in:store.project))?.connections ?? []).map(\.connection)
    }
    private var isGroup:Bool {store.selectedHierarchyGroup != nil}
    private var managing:Bool {isGroup && (workspace.managingGroupPorts || ports.isEmpty)}
    private func presented(_ endpoint:CirclePortEndpoint)->CirclePortEndpoint {
        guard let node else {return endpoint}
        return GroupPortEditing.presented(endpoint,at:node.id,in:store.project) ?? endpoint
    }
    private func visible(_ endpoint:CirclePortEndpoint)->CirclePortEndpoint {
        guard let scene=store.hierarchyScene,scene.node(endpoint.node)==nil else {return endpoint}
        for node in scene.nodes {
            if let port=node.ports.first(where:{$0.bindingTarget==endpoint}) {return .init(node:node.id,portID:port.id)}
        }
        return endpoint
    }
    private var availableTargets: [PortTargetItem] {
        guard let own else { return [] }
        let choices=(store.hierarchyScene?.nodes ?? []).flatMap { n in n.ports.compactMap { port->PortTargetItem? in
            let endpoint = CirclePortEndpoint(node: n.id, portID: port.id)
            guard (try? CirclePortCatalog.normalize(own, endpoint, in: store.project)) != nil else { return nil }
            return ConnectionTargetSearch.choice(endpoint,name:n.title,port:port.name,in:store.project)
        } }
        return choices
    }
    private var targets:[PortTargetItem] {ConnectionTargetSearch.search(availableTargets,query:workspace.query)}
    private var listedConnections:[CirclePortConnection] {
        guard workspace.currentPortOnly,let own else{return connections}
        let logical=(try? GroupPortEditing.resolve(own,in:store.project)) ?? own
        return connections.filter{$0.from==logical || $0.to==logical}
    }
    private var canConnect:Bool {own != nil && workspace.target.map{id in targets.contains{$0.endpoint==id}} == true}
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment:.leading,spacing:12) {
                if isGroup {
                    HStack {
                        Text("노출 포트 \(ports.count)개").fontWeight(.semibold)
                        scopeLabel
                        Spacer()
                        if !ports.isEmpty {PortActionButton(title:managing ? "연결 편집":"노출 포트 관리",keyboard:keyboard,order:-100) {
                            workspace.managingGroupPorts.toggle();focusSearch()
                        }.frame(width:140)}
                    }.padding(.bottom,12)
                }
                if managing,let node {
                    ScrollView {GroupPortEditor(store:store,group:node.id,keyboard:keyboard) { id in
                        workspace.managingGroupPorts=false;workspace.replacing=nil;workspace.target=nil;workspace.query="";workspace.ownPortID=id;focusSearch()
                    }}
                } else if geometry.size.width >= 800 {
                    HStack(alignment: .top, spacing: 24) {
                        compose(height:geometry.size.height-(isGroup ? 54:0)).frame(maxWidth: .infinity)
                        connectionWorkspace.frame(maxWidth: .infinity)
                    }.padding(.trailing, 8)
                } else {
                    ScrollView {VStack(alignment: .leading, spacing: 18) { compose(height:340); Divider(); connectionHeading;connectionList }.padding(.trailing, 8)}
                }
            }
        }
        .onAppear { loadIntent(); focusSearch() }
        .onChange(of:workspace) { _,_ in rememberWorkspace() }
        .onDisappear { rememberWorkspace() }
        .onChange(of: store.connectionEditorIntent?.id) { _, id in if id != nil {loadIntent();focusSearch()} }
        .onChange(of: store.editOriginal) { _,_ in rememberWorkspace();loadIntent();focusSearch() }
        .onChange(of: connections) { _,_ in if isCurrentWorkspace {workspace=workspace.restored(ports:ports,targets:availableTargets,connections:connections)} }
        .onChange(of: targets.map(\.endpoint)) { _, ids in if isCurrentWorkspace,let target=workspace.target,!ids.contains(target) {workspace.target=nil} }
        .onChange(of: ports.map(\.id)) {_,ids in if isCurrentWorkspace,!ids.contains(workspace.ownPortID) {reset()} }
    }
    private var connectionWorkspace:some View {
        VStack(alignment:.leading,spacing:10) {connectionHeading;ScrollView {connectionList}}
    }
    private var connectionHeading:some View {
        HStack {
            Text("연결 \(listedConnections.count)개").fontWeight(.semibold)
            scopeLabel
            Spacer()
            PortChoice(label:"연결 표시 범위",selection:$workspace.currentPortOnly,options:[(false,"전체 포트"),(true,"현재 포트")],keyboard:keyboard,order:70).frame(width:120)
        }
    }
    @ViewBuilder private var scopeLabel:some View {
        if store.selectedMusic != nil || isGroup && store.selectedUse != nil {
            Text(store.editOriginal ? "공유 원본":"이번 사용").font(.system(size:12)).foregroundStyle(StudioTheme.secondary)
                .help(store.editOriginal ? "같은 원본을 사용하는 서클에 반영":"이 섹션의 이번 사용에만 반영")
        }
    }
    private var connectionList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if listedConnections.isEmpty {Text(workspace.currentPortOnly ? "이 포트에 연결된 케이블이 없습니다":"입력 또는 출력을 골라 첫 연결을 만드세요").foregroundStyle(StudioTheme.secondary)}
            ForEach(Array(listedConnections.enumerated()), id: \.element.id) { index, edge in row(edge, index: index) }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func compose(height:CGFloat)->some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing:8) {
                PortChoice(label:"이 서클의 IN OUT 포트",selection:Binding(get:{workspace.ownPortID},set:{selectOwnPort($0)}),options:ports.map{($0.id,$0.name)},keyboard:keyboard,order:10)
                if workspace.replacing != nil { PortActionButton(title: "취소", keyboard: keyboard, order: 0) { reset(); focusSearch() }.frame(width:60) }
                PortActionButton(title: workspace.replacing == nil ? "연결" : "재연결 적용", keyboard: keyboard, order: 60) { commit(); focusSearch() }
                    .frame(width:workspace.replacing == nil ? 60:100).disabled(!canConnect)
            }.frame(height:34)
            HStack(spacing:8) {
                PortChoice(label:"시작 위치",selection:$workspace.firstOctant,options:PortOctant.allCases.map{($0,"시작 "+$0.label)},keyboard:keyboard,order:40)
                PortChoice(label:"대상 위치",selection:$workspace.secondOctant,options:PortOctant.allCases.map{($0,"대상 "+$0.label)},keyboard:keyboard,order:50)
            }.frame(height:34)
            HStack {
                Text("↑ ↓ 대상 선택 · Return 연결 · Tab 항목 이동").font(.system(size:11)).foregroundStyle(StudioTheme.secondary)
                Spacer()
            }.frame(height:14)
            HStack(spacing:8) {
                PortSearchField(text:$workspace.query,keyboard:keyboard,order:20,label:"대상 이름 · 경로 · #섹션 번호 검색",moveSelection:moveTarget,submit:{commit();focusSearch()})
                Text("\(targets.count)개").font(.system(size:11)).foregroundStyle(StudioTheme.secondary).frame(width:36)
            }.frame(height:34)
            if targets.isEmpty {Text(workspace.query.isEmpty ? "연결 가능한 대상 포트가 없습니다":"검색 결과가 없습니다").foregroundStyle(StudioTheme.secondary).frame(maxWidth:.infinity).frame(height:max(60,height-148))}
            else {PortTargetList(items:targets,selection:$workspace.target,keyboard:keyboard,order:30,activate:{commit();focusSearch()}).frame(height:max(60,height-148))}
        }
    }
    private func moveTarget(_ step:Int) {
        guard !targets.isEmpty else {workspace.target=nil;return}
        let current=workspace.target.flatMap{id in targets.firstIndex{$0.endpoint==id}}
        let index=current.map{max(0,min(targets.count-1,$0+step))} ?? 0
        workspace.target=targets[index].endpoint
    }
    private func title(_ endpoint: CirclePortEndpoint) -> String {
        let endpoint=visible(presented(endpoint))
        let name = store.hierarchyScene?.node(endpoint.node)?.title ?? storedTitle(endpoint.node)
        let port = (try? CirclePortCatalog.ports(at: endpoint.node, in: store.project))?.first { $0.id == endpoint.portID }?.name ?? endpoint.portID
        let choice=ConnectionTargetSearch.choice(endpoint,name:name,port:port,in:store.project)
        return choice.title + " · " + choice.detail
    }
    private func displayTitle(_ endpoint:CirclePortEndpoint)->String {
        let endpoint=visible(presented(endpoint))
        let name=store.hierarchyScene?.node(endpoint.node)?.title ?? storedTitle(endpoint.node)
        let port=(try? CirclePortCatalog.ports(at:endpoint.node,in:store.project))?.first{$0.id==endpoint.portID}?.name ?? endpoint.portID
        return ConnectionTargetSearch.choice(endpoint,name:name,port:port,in:store.project).title+" · "+port
    }
    private func storedTitle(_ address:CircleAddress)->String {
        switch address {
        case .music(let ai,let ui,let ni):
            if let use=store.project.arrangements.first(where:{$0.id==ai})?.uses.first(where:{$0.id==ui}),
               let section=store.project.sections.first(where:{$0.id==use.sectionID}),
               let graph=try? SectionGraphEditing.effective(section:section,use:use),let node=graph.nodes.first(where:{$0.id==ni}) {return node.name}
        case .signal(let id):if let node=store.project.signal.nodes.first(where:{$0.id==id}) {return node.name}
        case .section(let ai,let ui):if let use=store.project.arrangements.first(where:{$0.id==ai})?.uses.first(where:{$0.id==ui}) {return use.name}
        case .composition(let id):if let node=store.project.album?.composition(id) {return node.name}
        default:break
        }
        return "대상 서클 없음"
    }
    private func row(_ edge: CirclePortConnection, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(displayTitle(edge.from)).lineLimit(2).help(title(edge.from)).accessibilityLabel(title(edge.from))
            Label(displayTitle(edge.to), systemImage: "arrow.down.right").lineLimit(2).help(title(edge.to)).accessibilityLabel(title(edge.to))
            if SectionFlowSelection.edge(edge.id,in:store.project) != nil {
                HStack(spacing:8) {
                    let selected=SectionFlowSelection.isSelected(edge.id,in:store.project)
                    PortActionButton(title:selected ? "재생 경로":"이 경로 재생",keyboard:keyboard,order:98+index*10,
                                     label:(selected ? "재생 경로 · ":"이 경로 재생 · ")+title(edge.to)) {
                        store.mutate("재생할 분기 선택"){try SectionFlowSelection.choose(edge.id,in:&$0)}
                    }.frame(width:110).disabled(selected)
                    PortActionButton(title:"전환 편집",keyboard:keyboard,order:99+index*10,label:"전환 편집 · "+title(edge.from)+" → "+title(edge.to)) {
                        guard SectionFlowSelection.edge(edge.id,in:store.project) != nil else{return}
                        store.connectionsOpen=false;store.openHierarchyTransition(edge.from.node,edgeID:edge.id.edgeID)
                    }.frame(width:90)
                    Spacer(minLength:0)
                }
            }
            HStack(spacing:8) {
            if edge.signal != .flow || { if case .section = edge.from.node { return true }; return false }() {
                    PortActionButton(title: "재연결", keyboard: keyboard, order: 100+index*10, label: "재연결 · " + title(edge.from) + " → " + title(edge.to)) { populate(edge); focusSearch() }
                        .frame(width:66)
                    PortActionButton(title: "해제", keyboard: keyboard, order: 101+index*10, label: "해제 · " + title(edge.from) + " → " + title(edge.to)) { let original = store.editOriginal; store.mutate("케이블 해제") { try CircleConnectionEditing.disconnect(edge.id, original: original, in: &$0) } }
                        .frame(width:52)
            }
                Spacer(minLength:0)
                PortChoice(label:"OUT 위치 · "+title(edge.from),selection:Binding(get:{store.project.portLayout?.placement(for:edge.id).from ?? .east},set:{store.moveConnection(edge.id,from:$0)}),options:PortOctant.allCases.map{($0,"OUT "+$0.label)},keyboard:keyboard,order:102+index*10).frame(width:110)
                PortChoice(label:"IN 위치 · "+title(edge.to),selection:Binding(get:{store.project.portLayout?.placement(for:edge.id).to ?? .west},set:{store.moveConnection(edge.id,to:$0)}),options:PortOctant.allCases.map{($0,"IN "+$0.label)},keyboard:keyboard,order:103+index*10).frame(width:100)
            }
            if edge.signal != .flow {Text(edge.signal == .audio ? "오디오 · \(GainScale.text(edge.gain)) dB" : "MIDI 연주").font(.system(size:11)).foregroundStyle(StudioTheme.secondary)}
            Divider()
        }.padding(6).background(workspace.replacing==edge.id ? StudioTheme.raised:Color.clear,in:RoundedRectangle(cornerRadius:5))
    }
    private func populate(_ edge: CirclePortConnection) {
        workspace.replacing = edge.id; workspace.replacementSource=edge.from;workspace.replacementDestination=edge.to; workspace.query = ""
        let from=presented(edge.from),to=presented(edge.to)
        let incoming = to.node == node?.id
        workspace.ownPortID = incoming ? to.portID : from.portID
        workspace.target = visible(incoming ? edge.from : edge.to)
        let placement = store.project.portLayout?.placement(for: edge.id) ?? .init()
        workspace.firstOctant = incoming ? placement.to : placement.from; workspace.secondOctant = incoming ? placement.from : placement.to
    }
    private func focusSearch() { DispatchQueue.main.async { keyboard.focus(managing ? -60:20) } }
    private func rememberWorkspace() {
        guard let workspaceKey,workspaceProjectID==store.project.id,workspaceGeneration==store.mediaImportGeneration else{return}
        store.connectionWorkspaceStates[workspaceKey]=workspace
    }
    private func selectOwnPort(_ id:String) {
        workspace.ownPortID=id
        if let own,let target=workspace.target,(try? CirclePortCatalog.normalize(own,target,in:store.project))==nil {workspace.target=nil}
        if workspace.replacing==nil,let port=ports.first(where:{$0.id==id}) {
            workspace.firstOctant=port.defaultOctant;workspace.secondOctant=port.direction == .input ? .east:.west
        }
    }
    private func loadIntent() {
        guard let node else{return}
        workspaceKey=ConnectionWorkspaceKey(node:node.id,original:store.editOriginal)
        workspaceProjectID=store.project.id;workspaceGeneration=store.mediaImportGeneration
        let intent=store.connectionEditorIntent
        let matches=intent?.projectID==store.project.id && intent?.node==node.id
        defer {if matches {store.connectionEditorIntent=nil}}
        if intent==nil || matches && intent?.connection==nil && intent?.portID==nil,let key=workspaceKey,let remembered=store.connectionWorkspaceStates[key] {
            workspace=remembered
            workspace=remembered.restored(ports:ports,targets:availableTargets,connections:connections)
            return
        }
        workspace=ConnectionWorkspaceState();reset()
        guard matches else{return}
        if let id=intent?.connection,let edge=connections.first(where:{$0.id==id}) {populate(edge)}
        else if let port=ports.first(where:{$0.id==intent?.portID}) {selectOwnPort(port.id)}
    }
    private func reset() {
        workspace.replacing = nil;workspace.replacementSource=nil;workspace.replacementDestination=nil; workspace.target = nil; workspace.query = ""
        let port = ports.first { $0.direction == .output } ?? ports.first
        workspace.ownPortID = port?.id ?? ""; workspace.firstOctant = port?.defaultOctant ?? .east
        workspace.secondOctant = port?.direction == .input ? .east : .west
    }
    private func commit() {
        guard canConnect,let own, let target=workspace.target else { return }
        let before = store.project, original = store.editOriginal
        store.mutate(workspace.replacing == nil ? "포트 연결" : "케이블 재연결") { p in
            try CircleConnectionEditing.connect(own, target, firstOctant: workspace.firstOctant, secondOctant: workspace.secondOctant,
                replacing: workspace.replacing, original: original, in: &p)
        }
        if store.project != before { reset() }
    }
}

struct AudioRouterEditor: View {
    @ObservedObject var store: AppStore
    let router: AudioRouter
    @State private var draft: [String: Double] = [:]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("스테레오 2 IN / 2 OUT").fontWeight(.semibold); Spacer(); Button("연결 편집") { store.showConnections() } }
            Text("입력별로 출력에 보낼 양을 정합니다").foregroundStyle(StudioTheme.secondary)
            ForEach(0..<2, id: \.self) { input in ForEach(0..<2, id: \.self) { output in
                HStack {
                    Text("IN \(input + 1) → OUT \(output + 1)").frame(width: 106, alignment: .leading)
                    Slider(value: binding(input, output), in: 0...4, step: 0.05, onEditingChanged: { editing in if !editing { commit(input,output) } }).accessibilityLabel("입력 \(input + 1)에서 출력 \(output + 1)로 보낼 양")
                    RouterAmountField(value:binding(input,output).wrappedValue,label:"IN \(input+1) OUT \(output+1) 전송량") { value in
                        draft["\(input):\(output)"]=value;commit(input,output)
                    }.frame(width:68)
                }
            } }
            HStack {
                Button("1 → 1 · 2 → 2") { store.updateMusic("라우터 기본 경로") { $0.content = .router(AudioRouter()) } }
                Button("1 → 2 · 2 → 1") { store.updateMusic("라우터 교차 경로") { $0.content = .router(AudioRouter(routes: [.init(input: AudioRouter.input1, output: AudioRouter.output2), .init(input: AudioRouter.input2, output: AudioRouter.output1)])) } }
            }
        }
    }
    private func binding(_ input: Int, _ output: Int) -> Binding<Double> {
        Binding(get: { draft["\(input):\(output)"] ?? router.routes.first { $0.input == AudioRouter.inputs[input] && $0.output == AudioRouter.outputs[output] }?.gain ?? 0 }, set: { draft["\(input):\(output)"] = $0 })
    }
    private func commit(_ input: Int, _ output: Int) {
        let key = "\(input):\(output)"
        if let value = draft[key] {
            store.updateMusic("라우터 전송량") { node in
                guard case .router(var current) = node.content else { return }
                guard (current.routes.first { $0.input == AudioRouter.inputs[input] && $0.output == AudioRouter.outputs[output] }?.gain ?? 0) != value else { return }
                current.routes.removeAll { $0.input == AudioRouter.inputs[input] && $0.output == AudioRouter.outputs[output] }
                if value != 0 { current.routes.append(.init(input: AudioRouter.inputs[input], output: AudioRouter.outputs[output], gain: value)) }
                node.content = .router(current)
            }
            draft[key] = nil
        }
    }
}

private struct RouterAmountField: View {
    let value: Double
    let label: String
    let apply: (Double) -> Void
    @State private var text = ""
    @State private var invalid = false
    @FocusState private var editing: Bool
    private func formatted(_ value: Double) -> String { String(format:"%.2f",value) }
    var body: some View {
        TextField("0–4",text:$text)
            .textFieldStyle(StudioFieldStyle()).monospacedDigit().focused($editing)
            .foregroundStyle(invalid ? Color.red : StudioTheme.text)
            .accessibilityLabel(label).help("0–4 · Return으로 적용 · Esc로 취소")
            .onAppear {text=formatted(value)}
            .onChange(of:value) { _,next in if !editing {text=formatted(next)} }
            .onChange(of:editing) { _,focused in if !focused {commit()} }
            .onSubmit {if commit() {editing=false}}
            .onExitCommand {text=formatted(value);invalid=false;editing=false}
    }
    @discardableResult private func commit() -> Bool {
        guard let next=Double(text.trimmingCharacters(in:.whitespacesAndNewlines)),next.isFinite,(0...4).contains(next) else {invalid=true;return false}
        invalid=false;text=formatted(next)
        if next != value {apply(next)}
        return true
    }
}
