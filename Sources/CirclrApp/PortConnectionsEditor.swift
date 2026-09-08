import SwiftUI
import CirclrCore

extension AppStore {
    func showConnections() {
        guard let node = selectedCircle, !node.ports.isEmpty else { return }
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
    @State private var ownPortID = ""
    @State private var target: CirclePortEndpoint?
    @State private var firstOctant = PortOctant.east
    @State private var secondOctant = PortOctant.west
    @State private var replacing: CircleConnectionID?
    @State private var query = ""
    private var node: CircleSceneNode? { store.selectedCircle }
    private var ports: [CirclePort] { node?.ports ?? [] }
    private var own: CirclePortEndpoint? {
        guard let node, ports.contains(where: { $0.id == ownPortID }) else { return nil }
        return .init(node: node.id, portID: ownPortID)
    }
    private var connections: [CirclePortConnection] {
        ((try? CirclePortCatalog.connections(in: store.project)) ?? []).filter { $0.from.node == node?.id || $0.to.node == node?.id }
    }
    private var targets: [(CirclePortEndpoint, String)] {
        guard let own else { return [] }
        return (store.hierarchyScene?.nodes ?? []).flatMap { n in n.ports.compactMap { port in
            let endpoint = CirclePortEndpoint(node: n.id, portID: port.id)
            guard (try? CirclePortCatalog.normalize(own, endpoint, in: store.project)) != nil else { return nil }
            let title = n.title + " · " + port.name
            guard query.isEmpty || title.localizedCaseInsensitiveContains(query) else { return nil }
            return (endpoint, title)
        } }
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                if geometry.size.width >= 660 {
                    HStack(alignment: .top, spacing: 24) {
                        compose.frame(maxWidth: .infinity)
                        connectionList.frame(maxWidth: .infinity)
                    }.padding(.trailing, 8)
                } else {
                    VStack(alignment: .leading, spacing: 18) { compose; Divider(); connectionList }.padding(.trailing, 8)
                }
            }
        }
        .onAppear { reset() }
        .onChange(of: ownPortID) { _, _ in
            if let own, let target, (try? CirclePortCatalog.normalize(own,target,in:store.project)) == nil { self.target = nil }
            if replacing == nil, let port = ports.first(where: { $0.id == ownPortID }) {
                firstOctant = port.defaultOctant; secondOctant = port.direction == .input ? .east : .west
            }
        }
        .onChange(of: query) { _, _ in if let target, !targets.contains(where: { $0.0 == target }) { self.target = nil } }
    }
    private var connectionList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("연결 \(connections.count)개").fontWeight(.semibold)
            if connections.isEmpty { Text("입력 또는 출력을 골라 첫 연결을 만드세요").foregroundStyle(StudioTheme.secondary) }
            ForEach(connections, id: \.id) { edge in row(edge) }
        }
    }
    private var compose: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(replacing == nil ? "새 연결" : "케이블 재연결").fontWeight(.semibold)
                Spacer()
                if replacing != nil { Button("취소") { reset() } }
            }
            StudioChoice("", selection: $ownPortID, options: ports.map { ($0.id,$0.name) }).accessibilityLabel("이 서클의 IN OUT 포트")
            TextField("대상 이름 검색", text: $query).textFieldStyle(StudioFieldStyle())
            StudioChoice("", selection: $target, options: [(Optional<CirclePortEndpoint>.none,"대상 포트 선택")]+targets.map { (Optional($0.0),$0.1) }).accessibilityLabel("대상 포트")
            HStack {
                octantPicker("시작 위치", value: $firstOctant)
                octantPicker("대상 위치", value: $secondOctant)
            }
            HStack {
                Text("신호는 항상 OUT → IN").foregroundStyle(StudioTheme.secondary)
                Spacer()
                Button(replacing == nil ? "연결" : "재연결 적용") { commit() }.disabled(own == nil || target == nil)
            }
        }
    }
    private func octantPicker(_ title: String, value: Binding<PortOctant>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10)).foregroundStyle(StudioTheme.secondary)
            StudioChoice("", selection: value, options: PortOctant.allCases.map { ($0,$0.label) }).accessibilityLabel(title)
        }
    }
    private func title(_ endpoint: CirclePortEndpoint) -> String {
        let name = store.hierarchyScene?.node(endpoint.node)?.title ?? "접힌 그룹 내부"
        let port = (try? CirclePortCatalog.ports(at: endpoint.node, in: store.project))?.first { $0.id == endpoint.portID }?.name ?? endpoint.portID
        return name + " · " + port
    }
    private func row(_ edge: CirclePortConnection) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title(edge.from)).lineLimit(2)
            Label(title(edge.to), systemImage: "arrow.down.right").lineLimit(2)
            if edge.signal != .flow || { if case .section = edge.from.node { return true }; return false }() {
                HStack {
                    Text(edge.signal == .audio ? "오디오 · gain \(edge.gain.formatted())" : edge.signal == .midi ? "MIDI 연주" : "재생 경로").foregroundStyle(StudioTheme.secondary)
                    Spacer()
                    Button("재연결") {
                        replacing = edge.id; query = ""
                        let incoming = edge.to.node == node?.id
                        ownPortID = incoming ? edge.to.portID : edge.from.portID
                        target = incoming ? edge.from : edge.to
                        let placement = store.project.portLayout?.placement(for: edge.id) ?? .init()
                        firstOctant = incoming ? placement.to : placement.from; secondOctant = incoming ? placement.from : placement.to
                    }
                    Button("해제") { let original = store.editOriginal; store.mutate("케이블 해제") { try CircleConnectionEditing.disconnect(edge.id, original: original, in: &$0) } }
                }
            }
            HStack {
                octantPicker("OUT 위치", value: Binding(get: { store.project.portLayout?.placement(for: edge.id).from ?? .east }, set: { store.moveConnection(edge.id, from: $0) }))
                octantPicker("IN 위치", value: Binding(get: { store.project.portLayout?.placement(for: edge.id).to ?? .west }, set: { store.moveConnection(edge.id, to: $0) }))
            }
            Divider()
        }
    }
    private func reset() {
        replacing = nil; target = nil; query = ""
        let port = ports.first { $0.direction == .output } ?? ports.first
        ownPortID = port?.id ?? ""; firstOctant = port?.defaultOctant ?? .east
        secondOctant = port?.direction == .input ? .east : .west
    }
    private func commit() {
        guard let own, let target else { return }
        let before = store.project, original = store.editOriginal
        store.mutate(replacing == nil ? "포트 연결" : "케이블 재연결") { p in
            try CircleConnectionEditing.connect(own, target, firstOctant: firstOctant, secondOctant: secondOctant,
                replacing: replacing, original: original, in: &p)
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
