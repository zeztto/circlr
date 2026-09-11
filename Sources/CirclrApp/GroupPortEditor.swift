import SwiftUI
import CirclrCore

struct GroupPortEditor: View {
    @ObservedObject var store: AppStore
    let group: CircleAddress
    let keyboard: PortKeyboardFocus
    let select: (String) -> Void
    @State private var query = ""
    @State private var name = ""
    @State private var target: CirclePortEndpoint?
    @State private var editingID: String?
    private var bindings: [GroupPortBinding] { GroupPortEditing.bindings(at: group, in: store.project) }
    private var candidates: [(CirclePortEndpoint, String)] {
        ((try? GroupPortEditing.members(of: group, in: store.project)) ?? []).flatMap { node in
            ((try? CirclePortCatalog.ports(at: node, in: store.project)) ?? []).compactMap { port in
                let endpoint = CirclePortEndpoint(node: node, portID: port.id), title = targetTitle(endpoint)
                return query.isEmpty || title.localizedCaseInsensitiveContains(query) ? (endpoint, title) : nil
            }
        }
    }
    private func targetTitle(_ endpoint: CirclePortEndpoint) -> String {
        var title = "내부 서클"
        switch endpoint.node {
        case .music(let ai, let ui, let ni):
            if let use=store.project.arrangements.first(where:{$0.id==ai})?.uses.first(where:{$0.id==ui}),
               let section=store.project.sections.first(where:{$0.id==use.sectionID}),
               let graph=try? SectionGraphEditing.effective(section:section,use:use) {title=graph.nodes.first{$0.id==ni}?.name ?? title}
        case .signal(let id): title = store.project.signal.nodes.first { $0.id == id }?.name ?? title
        case .composition(let id): title = store.project.album?.composition(id)?.name ?? title
        case .section(let ai,let ui): title = store.project.arrangements.first { $0.id == ai }?.uses.first { $0.id == ui }?.name ?? title
        default: break
        }
        let port = (try? CirclePortCatalog.ports(at: endpoint.node, in: store.project))?.first { $0.id == endpoint.portID }
        return title + " · " + (port?.name ?? "대상 포트 없음")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("그룹 밖에서 연결할 내부 포트를 고르세요").fontWeight(.semibold)
            PortSearchField(text: $query, keyboard: keyboard, order: -60, label: "내부 서클·포트 검색")
            PortChoice(label: "노출할 내부 포트", selection: $target,
                       options: [(Optional<CirclePortEndpoint>.none, "내부 포트 선택")] + candidates.map { (Optional($0.0), $0.1) }, keyboard: keyboard, order: -50)
                .disabled(editingID != nil)
            HStack {
                PortSearchField(text: $name, keyboard: keyboard, order: -40, label: "노출 포트 이름")
                PortActionButton(title: editingID == nil ? "포트 노출" : "이름 적용", keyboard: keyboard, order: -30) { apply() }
                    .frame(width: 100).disabled(target == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if editingID != nil { PortActionButton(title: "취소", keyboard: keyboard, order: -20) { editingID = nil; target = nil; name = "" }.frame(width: 70) }
            }
            Text("IN/OUT과 신호는 내부 포트를 따릅니다. 노출을 해제해도 음악 연결은 유지됩니다.")
                .font(.system(size: 11)).foregroundStyle(StudioTheme.secondary)
            ForEach(Array(bindings.enumerated()), id: \.element.id) { index, binding in
                let descriptor = try? GroupPortEditing.descriptor(for: binding, in: store.project)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text((descriptor.map { $0.direction == .input ? "IN · " : "OUT · " } ?? "대상 없음 · ")+binding.name).fontWeight(.semibold)
                        Spacer()
                        PortActionButton(title: "연결", keyboard: keyboard, order: 2000+index*10, label: "연결 · "+binding.name) { select(binding.id) }.frame(width: 60).disabled(descriptor == nil)
                        PortActionButton(title: "이름", keyboard: keyboard, order: 2001+index*10, label: "이름 변경 · "+binding.name) {
                            query = ""; editingID = binding.id; target = binding.target; name = binding.name; keyboard.focus(-40)
                        }.frame(width: 60).disabled(descriptor == nil)
                        PortActionButton(title: "노출 해제", keyboard: keyboard, order: 2002+index*10, label: "노출 해제 · "+binding.name) {
                            store.mutate("그룹 포트 노출 해제", musical: false, portLayoutOnly: true) { p in
                                try GroupPortEditing.remove(group: group, portID: binding.id, projectID: p.id, expectedMusicRevision: p.musicRevision,
                                                            expectedLayoutRevision: p.portLayout?.revision ?? 0, in: &p)
                            }
                        }.frame(width: 90)
                    }
                    Text(targetTitle(binding.target)).foregroundStyle(StudioTheme.secondary).lineLimit(2)
                }
                Divider()
            }
        }
        .onChange(of: target) { _, value in
            if editingID == nil, let value, let port=(try? CirclePortCatalog.ports(at:value.node,in:store.project))?.first(where:{$0.id==value.portID}) {
                name=String(port.name.dropFirst(port.direction == .input ? 3:4))
            }
        }
    }
    private func apply() {
        guard let target else { return }
        var id: String?
        store.mutate(editingID == nil ? "그룹 포트 노출" : "그룹 포트 이름", musical: false, portLayoutOnly: true) { p in
            id = try GroupPortEditing.set(group: group, target: target, name: name, id: editingID, projectID: p.id,
                                          expectedMusicRevision: p.musicRevision, expectedLayoutRevision: p.portLayout?.revision ?? 0, in: &p)
        }
        if let id { select(id) }
    }
}
