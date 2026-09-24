import AppKit
import SwiftUI
import CirclrCore

struct PortToolsView: View {
    let title: String
    let edit: () -> Void
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(title).lineLimit(1); Spacer(); Button("연결 편집", action: edit); Button("닫기", action: close) }
            Text("클릭 / P 포트 선택 · 끌어서 연결 · Return 편집 · K 케이블 · Esc 해제")
                .foregroundStyle(StudioTheme.secondary).fixedSize(horizontal: false, vertical: true)
        }.font(.system(size: 12)).buttonStyle(.plain).padding(12)
            .background(StudioTheme.surface).clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(StudioTheme.accent.opacity(0.7)))
    }
}

extension AlbumCanvasView {
    func handleConnectionKey(_ event: NSEvent) -> Bool {
        guard !event.modifierFlags.contains(.option), connecting == nil, cableDrag == nil else { return false }
        let forward = !event.modifierFlags.contains(.shift)
        if event.keyCode == 40 { selectNeighborCable(forward: forward); return true } // K
        if event.keyCode == 35 { selectNeighborPort(forward: forward); return true } // P
        guard selectedCable != nil || selectedCanvasPort != nil else { return false }
        switch event.keyCode {
        case 53: clearCableSelection(); return true
        case 36, 76, 37: editConnectionSelection(); return true // Return / L
        case 48:
            if selectedCable != nil { chooseCableEnd(selectedCableEnd == .output ? .input : .output) }
            else { selectNeighborPort(forward: forward) }
            return true
        case 123, 124:
            if selectedCable != nil {
                if !event.isARepeat { rotateCableEnd(forward: event.keyCode == 124) }
            } else { selectNeighborPort(forward: event.keyCode == 124) }
            return true
        case 125, 126:
            if selectedCable != nil { selectNeighborCable(forward: event.keyCode == 125) }
            else { selectNeighborPort(forward: event.keyCode == 125) }
            return true
        case 51, 117:
            if selectedCable != nil { disconnectSelectedCable() }
            // A port is an engine endpoint, not a deletable music circle.
            return true
        default: return false
        }
    }

    func navigationCables() -> [CircleSceneEdge] {
        guard let scene, let selected = store.hierarchySelection else { return [] }
        let available = scene.edges.filter { $0.connectionID != nil }
        let incident = available.filter { $0.from == selected || $0.to == selected || $0.connectionID?.from == selected || $0.connectionID?.to == selected }
        if !incident.isEmpty, selectedCable == nil || incident.contains(where: { $0.connectionID == selectedCable }) { return incident }
        let anchor = selectedSceneCable?.from ?? selected
        let context = scene.node(anchor)?.role == .music ? scene.node(anchor)?.parent : anchor
        return available.filter { edge in
            guard let context else { return false }
            return scene.path(to: edge.from).contains { $0.id == context } && scene.path(to: edge.to).contains { $0.id == context }
        }
    }

    func selectNeighborCable(forward: Bool) {
        prepareConnectionNavigation()
        let candidates = navigationCables()
        guard !candidates.isEmpty else { store.status = "선택한 서클의 연결이 없습니다. P로 포트를 선택하세요"; return }
        let index = candidates.firstIndex { $0.connectionID == selectedCable } ?? (forward ? -1 : 0)
        let next = candidates[(index+(forward ? 1 : -1)+candidates.count)%candidates.count]
        let end = selectedCableEnd
        selectCable(next); selectedCableEnd = end
        revealCable(next)
        refreshCableTools(); announceConnectionSelection()
    }

    func selectNeighborPort(forward: Bool) {
        guard let node = store.selectedCircle, !node.ports.isEmpty else { store.status = "이 서클에는 노출된 IN/OUT 포트가 없습니다"; return }
        let ports = node.ports
        let index = ports.firstIndex { $0.id == selectedCanvasPort?.portID && node.id == selectedCanvasPort?.node } ?? (forward ? -1 : 0)
        selectCanvasPort(.init(node: node.id, portID: ports[(index+(forward ? 1 : -1)+ports.count)%ports.count].id))
    }

    func selectCanvasPort(_ endpoint: CirclePortEndpoint) {
        guard let node = scene?.node(endpoint.node), let port = node.ports.first(where: { $0.id == endpoint.portID }) else { return }
        clearCableSelection(); interruptPlaybackFollow()
        if store.hierarchySelection != endpoint.node { store.selectHierarchy(endpoint.node) }
        prepareConnectionNavigation()
        selectedCanvasPort = endpoint; selectedCableProjectID = store.project.id
        let viewport = workspaceViewport
        let bottomClearance = portToolsCanFit(in: viewport) ? portToolsHeight(in: viewport) + 20 : 20
        let safe = CGRect(x: viewport.minX + 24, y: viewport.minY + bottomClearance,
                          width: viewport.width - 48, height: viewport.height - bottomClearance - 24)
        let alreadyVisibleInLowerRight:Bool = {
            guard let console=consoleObstruction,node.radius*camera.zoom>45 else{return false}
            let circle=CanvasLabelCircle(id:node.id,center:CGPoint(x:node.center.x,y:node.center.y),radius:node.outerRadius)
            guard CanvasWorkspaceGeometry.circlesVisible([circle],through:camera,within:canvasViewport,
                                                         avoiding:console) else{return false}
            let center=camera.screen(node.center)
            guard let point=try? CirclePortGeometry.anchor(center:center,radius:node.outerRadius*camera.zoom,
                                                             port:port,octant:port.defaultOctant) else{return false}
            return CanvasWorkspaceGeometry.containsInteractivePoint(CGPoint(x:point.x,y:point.y),
                within:canvasViewport.insetBy(dx:12,dy:12),avoiding:console.insetBy(dx:-14,dy:-14))
        }()
        if !alreadyVisibleInLowerRight,
           let target = CirclePortPresentation.cameraRevealingSelected(port, on: node, current: camera, within: safe) {
            // Keyboard selection must remain actionable immediately, including while the
            // orbit is tiny. Animated focus could leave the selected control hidden mid-flight.
            setCamera(target)
        } else if animation != nil {
            setCamera(camera)
        }
        refreshPortTools(); window?.makeFirstResponder(self); needsDisplay = true; announceConnectionSelection()
    }

    func portToolsHeight(in viewport: CGRect) -> CGFloat {
        min(650, viewport.width - 16) < 560 ? 86 : 72
    }

    func portToolsCanFit(in viewport: CGRect) -> Bool {
        viewport.width > 320 && viewport.height > portToolsHeight(in: viewport) + 84
    }

    func prepareConnectionNavigation() {
        guard let node = store.selectedCircle, editor != nil || node.radius*camera.zoom >= 325 else { return }
        store.connectionsOpen = false; store.hierarchySettingsOpen = false
        editor?.removeFromSuperview(); editor = nil; editorAddress = nil
        let zoom = min(camera.zoom, 110/max(node.radius, 1e-12))
        setCamera(.init(pan: .init(workspaceViewport.midX-node.center.x*zoom, workspaceViewport.midY-node.center.y*zoom), zoom: zoom))
    }

    func revealCable(_ edge: CircleSceneEdge) {
        guard let curve = connectionCurve(edge) else { return }
        if let console=consoleObstruction {
            if CanvasWorkspaceGeometry.curveVisible(curve,within:canvasViewport,avoiding:console) {return}
        }
        let safe = workspaceViewport.insetBy(dx: 70, dy: 70)
        guard !CanvasWorkspaceGeometry.curveVisible(curve,within:workspaceViewport,margin:70) else { return }
        let points=[curve.from,curve.control1,curve.control2,curve.to]
        guard points.allSatisfy({$0.x.isFinite && $0.y.isFinite}) else{return}
        let minX=points.map(\.x).min()!,maxX=points.map(\.x).max()!
        let minY=points.map(\.y).min()!,maxY=points.map(\.y).max()!
        let factor=max(0.01,min(1,safe.width/max(1,maxX-minX),safe.height/max(1,maxY-minY)))
        let center=Point((minX+maxX)/2,(minY+maxY)/2)
        var next = camera.zoomed(to: camera.zoom*factor, around: center)
        next.pan.x += safe.midX-center.x; next.pan.y += safe.midY-center.y
        setCamera(next)
    }

    func chooseCableEnd(_ direction: CirclePortDirection) {
        selectedCableEnd = direction; cableDrag = nil; connectionToken = nil
        refreshCableTools(); window?.makeFirstResponder(self); needsDisplay = true; announceConnectionSelection()
    }

    func rotateCableEnd(forward: Bool) {
        guard selectedCableProjectID == store.project.id, let id = selectedCable, selectedSceneCable != nil else { clearCableSelection(); return }
        let placement = store.project.portLayout?.placement(for: id) ?? .init()
        let current = selectedCableEnd == .output ? placement.from : placement.to
        guard let next = PortOctant(rawValue: (current.rawValue+(forward ? 1 : 7))%8) else { return }
        cableMode = .placement
        store.moveConnection(id, from: selectedCableEnd == .output ? next : nil, to: selectedCableEnd == .input ? next : nil)
        scene = store.hierarchyScene; refreshCableTools(); needsDisplay = true; announceConnectionSelection()
    }

    func editConnectionSelection() {
        guard selectedCableProjectID == store.project.id else { clearCableSelection(); return }
        if let port = selectedCanvasPort {
            clearCableSelection(); store.selectHierarchy(port.node); store.showConnections(portID: port.portID)
        } else if let edge = selectedSceneCable, let id = edge.connectionID {
            let desired = selectedCableEnd == .output ? edge.from : edge.to
            let other = selectedCableEnd == .output ? edge.to : edge.from
            guard let address = [desired, other].first(where: { scene?.node($0)?.ports.isEmpty == false }) else {
                store.status = "연결 위치는 방향키로 바꿀 수 있습니다. 내부 포트를 편집하려면 그룹을 펼치세요"; return
            }
            clearCableSelection(); store.selectHierarchy(address); store.showConnections(replacing: id)
        }
    }

    func refreshPortTools() {
        if let endpoint = selectedCanvasPort,
           selectedCableProjectID != store.project.id || endpoint.node != store.hierarchySelection ||
           scene?.node(endpoint.node)?.ports.contains(where: { $0.id == endpoint.portID }) != true {
            clearCableSelection()
        }
        guard selectedCableProjectID == store.project.id, let endpoint = selectedCanvasPort,
              let node = scene?.node(endpoint.node), endpoint.node == store.hierarchySelection,
              let port = node.ports.first(where: { $0.id == endpoint.portID }), portToolsCanFit(in: workspaceViewport),
              store.movieWriter == nil, !store.connectionsOpen else {
            portTools?.removeFromSuperview(); portTools = nil
            if selectedCableProjectID != store.project.id || selectedCanvasPort?.node != store.hierarchySelection { selectedCanvasPort = nil }
            return
        }
        let view = PortToolsView(title: node.title+" · "+port.name, edit: { [weak self] in self?.editConnectionSelection() }, close: { [weak self] in self?.clearCableSelection() })
        if let portTools { portTools.rootView = view } else { let host = NSHostingView(rootView: view); addSubview(host); portTools = host }
        let width = min(650, workspaceViewport.width-16), height = portToolsHeight(in: workspaceViewport)
        portTools?.frame = NSRect(x: workspaceViewport.midX-width/2, y: workspaceViewport.minY+8, width: width, height: height)
        portTools?.isHidden = connecting != nil || cableDrag != nil
    }

    func selectedPortHandle() -> CirclePortHandle? {
        guard let endpoint = selectedCanvasPort else { return nil }
        let handles = visiblePortHandles().filter { $0.endpoint == endpoint }
        let direction = scene?.node(endpoint.node)?.ports.first { $0.id == endpoint.portID }?.defaultOctant
        return handles.first { $0.octant == direction } ?? handles.first
    }

    func announceConnectionSelection() {
        updateAccessibility()
        NSAccessibility.post(element: self, notification: .selectedChildrenChanged)
    }

    func connectionAccessibilityChildren() -> [NSAccessibilityElement] {
        guard let scene, window != nil else { return [] }
        var result: [NSAccessibilityElement] = [], portIDs = Set<CirclePortEndpoint>(), cableIDs = Set<CircleConnectionID>()
        let handles = visiblePortHandles()
        for handle in handles where portIDs.insert(handle.endpoint).inserted {
            guard let node = scene.node(handle.endpoint.node), let port = node.ports.first(where: { $0.id == handle.endpoint.portID }) else { continue }
            let point = handles.first { $0.endpoint == handle.endpoint && $0.octant == port.defaultOctant }?.point ?? handle.point
            let element = portAccessibility[handle.endpoint] ?? PortAccessibility(parent: self, endpoint: handle.endpoint)
            portAccessibility[handle.endpoint] = element
            element.setAccessibilityLabel(node.title+" · "+port.name)
            element.setAccessibilityHelp("포트 선택 · Return 연결 편집 · Tab 다음 포트 · Esc 해제")
            element.setAccessibilitySelected(selectedCanvasPort == handle.endpoint)
            element.setFrameInView(NSRect(x:point.x-10,y:point.y-10,width:20,height:20),view:self)
            result.append(element)
        }
        for edge in scene.edges {
            guard let id = edge.connectionID, let a = scene.node(edge.from), let b = scene.node(edge.to), isVisible(a), isVisible(b),
                  let point = try? connectionCurve(edge)?.point(at: 0.5), cablePointAvailable(point) else { continue }
            cableIDs.insert(id)
            let element = cableAccessibility[id] ?? CableAccessibility(parent: self, connection: id)
            cableAccessibility[id] = element
            let from = (try? CirclePortCatalog.ports(at: edge.from, in: store.project))?.first { $0.id == edge.fromPortID }?.name ?? edge.fromPortID
            let to = (try? CirclePortCatalog.ports(at: edge.to, in: store.project))?.first { $0.id == edge.toPortID }?.name ?? edge.toPortID
            element.setAccessibilityLabel("케이블 · "+a.title+" · "+from+" → "+b.title+" · "+to)
            element.setAccessibilityValue("OUT \(edge.placement.from.label) · IN \(edge.placement.to.label)")
            element.setAccessibilityHelp("선택 후 Tab 끝점 · 좌우 위치 · Return 편집 · Delete 해제")
            element.setAccessibilitySelected(selectedCable == id)
            element.setFrameInView(NSRect(x:point.x-10,y:point.y-10,width:20,height:20),view:self)
            result.append(element)
        }
        portAccessibility = portAccessibility.filter { portIDs.contains($0.key) }
        cableAccessibility = cableAccessibility.filter { cableIDs.contains($0.key) }
        return result
    }
}

@MainActor final class PortAccessibility: NSAccessibilityElement {
    weak var canvas: AlbumCanvasView?
    let endpoint: CirclePortEndpoint
    let projectID: ID
    init(parent: AlbumCanvasView, endpoint: CirclePortEndpoint) {
        canvas = parent; self.endpoint = endpoint; projectID = parent.store.project.id; super.init()
        setAccessibilityParent(parent); setAccessibilityRole(.button); setAccessibilityEnabled(true)
    }
    override func accessibilityPerformPress() -> Bool {
        guard let canvas, canvas.store.project.id == projectID,
              canvas.scene?.node(endpoint.node)?.ports.contains(where: { $0.id == endpoint.portID }) == true else { return false }
        canvas.selectCanvasPort(endpoint); return true
    }
}

@MainActor final class CableAccessibility: NSAccessibilityElement {
    weak var canvas: AlbumCanvasView?
    let connection: CircleConnectionID
    let projectID: ID
    init(parent: AlbumCanvasView, connection: CircleConnectionID) {
        canvas = parent; self.connection = connection; projectID = parent.store.project.id; super.init()
        setAccessibilityParent(parent); setAccessibilityRole(.button); setAccessibilityEnabled(true)
    }
    override func accessibilityPerformPress() -> Bool {
        guard let canvas, canvas.store.project.id == projectID, let edge = canvas.scene?.edges.first(where: { $0.connectionID == connection }) else { return false }
        canvas.selectCable(edge); canvas.announceConnectionSelection(); return true
    }
}
