import AppKit
import Combine
import CirclrCore

extension CircleColor {
    var nsColor: NSColor {
        NSColor(srgbRed: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, alpha: 1)
    }
}

extension AlbumCanvasView {
    func installCircleColorObserver() {
        colorSubscription = store.$project.sink { [weak self] project in
            guard let self, let target = self.colorTarget else { return }
            // Observe the incoming project rather than the canvas's previous rendered scene.
            // Invalidating on deletion also prevents a later Undo from reviving the panel target.
            guard project.id == target.projectID,
                  let scene = try? HierarchySceneBuilder.build(project, revealing: target.address),
                  scene.node(target.address) != nil else {
                self.colorTarget = nil
                return
            }
        }
    }

    func setCircleColor(_ value: CircleColor?, for address: CircleAddress) {
        // A shared color panel can outlive its original project or circle.
        guard let currentScene = try? HierarchySceneBuilder.build(store.project, revealing: address),
              currentScene.node(address) != nil,
              store.project.circleColors?[address] != value else { return }
        store.mutate("서클 색상", musical: false, circleColorsOnly: true) { project in
            var colors = project.circleColors ?? [:]
            colors[address] = value
            project.circleColors = colors.isEmpty ? nil : colors
        }
        store.status = value == nil ? "종류별 기본 색상으로 복원했습니다" : "서클 색상을 변경했습니다"
        needsDisplay = true
    }

    func chooseCircleColor(_ node: CircleSceneNode) {
        guard let currentScene = try? HierarchySceneBuilder.build(store.project, revealing: node.id),
              let currentNode = currentScene.node(node.id) else { return }
        colorTarget = nil
        let panel = NSColorPanel.shared
        panel.setAction(nil)
        panel.setTarget(nil)
        panel.color = (store.project.circleColors?[node.id] ?? currentNode.baseColor).nsColor
        panel.showsAlpha = false
        panel.isContinuous = false
        panel.title = "서클 색상 · \(currentNode.title)"
        colorTarget = (store.project.id, node.id)
        panel.setTarget(self)
        panel.setAction(#selector(applyCircleColor(_:)))
        panel.makeKeyAndOrderFront(nil)
    }

    @objc func applyCircleColor(_ sender: NSColorPanel) {
        guard let target = colorTarget, target.projectID == store.project.id,
              let currentScene = try? HierarchySceneBuilder.build(store.project, revealing: target.address),
              let currentNode = currentScene.node(target.address),
              let rgb = sender.color.usingColorSpace(.sRGB) else { return }
        func byte(_ component: CGFloat) -> UInt8 { UInt8((min(1, max(0, component)) * 255).rounded()) }
        let color = CircleColor(red: byte(rgb.redComponent), green: byte(rgb.greenComponent), blue: byte(rgb.blueComponent))
        // Opening the shared panel can emit an action after its target is restored.
        // An unchanged displayed default must remain inherited, without an override or Undo entry.
        guard color != (store.project.circleColors?[target.address] ?? currentNode.baseColor) else { return }
        setCircleColor(color, for: target.address)
    }
}
