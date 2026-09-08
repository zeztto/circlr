import AppKit
import CirclrCore

extension AlbumCanvasView {
    var workspaceViewport:CGRect {
        CanvasWorkspaceGeometry.viewport(width:bounds.width,height:bounds.height,console:store.consoleOpen && store.consoleBounds.height>0 ? store.consoleBounds:nil)
    }
    var labelContext:CircleSceneNode? {
        guard let scene else{return nil}
        let context=scene.path(to:playbackVisibilityFocus ?? store.hierarchySelection ?? .album)
            .last(where:{$0.radius*camera.zoom>min(workspaceViewport.width,workspaceViewport.height)*0.22}) ?? scene.node(.album)
        // Inspecting a circle's ports keeps its siblings and cables available until a precision editor opens.
        if let context,context.role == .music || (context.role == .group && !context.ports.isEmpty),
           editorAddress != context.id,let parent=context.parent {return scene.node(parent)}
        return context
    }
    func drawReadableLabels() {
        labelPlacements=[]
        guard let scene,let context=labelContext else{return}
        let ancestors=Set(scene.path(to:context.id).dropLast().map(\.id))
        var requests:[CanvasLabelRequest]=[]
        for node in scene.nodes where isVisible(node) && !ancestors.contains(node.id) && editorAddress != node.id {
            let radius=node.radius*camera.zoom,p=screen(node),direct=node.parent==context.id
            guard bounds.contains(p) || node.id==context.id else{continue}
            guard node.id==context.id || direct || node.id==hoverAddress || (radius>=40 && node.depth<=context.depth+2) else{continue}
            let titleSize=(node.title as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:13,weight:.medium)])
            let width=min(230,max(72,titleSize.width+20)),height=radius>=65 ? 46.0:30.0
            let expanded=node.childCount>0 && scene.children(of:node.id).contains(where:isVisible)
            requests.append(CanvasLabelRequest(id:node.id,anchor:p,size:CGSize(width:width,height:height),radius:radius,expanded:expanded,priority:node.id==store.hierarchySelection ? 100:direct && ["MIDI","오디오"].contains(node.music?.content.label ?? "") ? 85:direct ? 70:20))
        }
        labelPlacements=CanvasLabelLayout.place(requests,within:workspaceViewport,avoiding:editor.map{[$0.frame.insetBy(dx:-8,dy:-8)]} ?? [])
        for placement in labelPlacements {
            guard let node=scene.node(placement.id) else{continue}
            let rect=placement.rect,selected=store.hierarchySelections.contains(node.id),hovered=hoverAddress==node.id
            if !rect.insetBy(dx:-8,dy:-8).contains(placement.anchor) {
                let end=CGPoint(x:max(rect.minX,min(rect.maxX,placement.anchor.x)),y:max(rect.minY,min(rect.maxY,placement.anchor.y)))
                let leader=NSBezierPath();leader.move(to:placement.anchor);leader.line(to:end)
                color(node).withAlphaComponent(selected || hovered ? 0.8:0.35).setStroke();leader.lineWidth=1;leader.stroke()
            }
            let path=NSBezierPath(roundedRect:rect,xRadius:6,yRadius:6)
            StudioTheme.canvasNS.withAlphaComponent(0.95).setFill();path.fill()
            (selected || hovered ? color(node):StudioTheme.lineNS.withAlphaComponent(0.5)).setStroke();path.lineWidth=1;path.stroke()
            drawText(node.title,x:rect.midX,y:rect.minY+7,size:13,color:StudioTheme.textNS,maxWidth:rect.width-16)
            if rect.height>35 {drawText(node.subtitle+(node.repeatCount>1 ? " · ×\(node.repeatCount)":""),x:rect.midX,y:rect.minY+26,size:11,color:StudioTheme.secondaryNS,maxWidth:rect.width-16)}
        }
    }
}
