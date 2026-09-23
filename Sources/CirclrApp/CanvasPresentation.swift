import AppKit
import CirclrCore

struct CanvasLabelText {
    let title:NSAttributedString
    let titleHeight:CGFloat
    let showsSubtitle:Bool
    let size:CGSize
    init(_ text:String,primary:Bool,showsSubtitle:Bool,availableWidth:CGFloat) {
        let font=NSFont.systemFont(ofSize:primary ? StudioTheme.canvasSelectedTitleSize:StudioTheme.canvasTitleSize,weight:primary ? .semibold:.medium)
        let width=min(availableWidth,primary ? 340:248,max(80,ceil((text as NSString).size(withAttributes:[.font:font]).width)+20))
        let style=NSMutableParagraphStyle();style.alignment = .center
        style.lineBreakMode = primary ? .byWordWrapping:.byTruncatingTail
        if primary {style.lineBreakStrategy = .hangulWordPriority}
        style.minimumLineHeight=20;style.maximumLineHeight=20
        title=NSAttributedString(string:text,attributes:[.font:font,.foregroundColor:StudioTheme.textNS,.paragraphStyle:style])
        let measured=title.boundingRect(with:CGSize(width:max(1,width-20),height:.greatestFiniteMagnitude),options:[.usesLineFragmentOrigin,.usesFontLeading]).height
        titleHeight=primary ? min(60,max(20,ceil(measured/20)*20)):20
        self.showsSubtitle=showsSubtitle
        size=CGSize(width:width,height:titleHeight+16+(showsSubtitle ? 18:0))
    }
}

struct CanvasLabelTextKey: Hashable {
    let address:CircleAddress
    let title:String
    let primary:Bool
    let showsSubtitle:Bool
    let availableWidth:Double
}

extension AlbumCanvasView {
    var workspaceViewport:CGRect {
        CanvasWorkspaceGeometry.viewport(width:bounds.width,height:bounds.height,console:!store.viewingMode && store.consoleBounds.height>0 ? store.consoleBounds:nil)
    }
    var labelContext:CircleSceneNode? {
        if isDrawingFrame { return drawingLabelContext }
        guard let scene else{return nil}
        if scene.isOrbit {
            var context=scene.node(playbackVisibilityFocus ?? store.hierarchySelection ?? .album) ?? scene.node(.album)
            if let node=context,node.role == .music || (node.role == .group && !node.ports.isEmpty),editorAddress != node.id {
                context=node.parent.flatMap{scene.node($0)} ?? node
            }
            while let node=context,let content=scene.contextBounds(of:node.id),max(content.width,content.height)*camera.zoom<120,let parent=node.parent.flatMap({scene.node($0)}) {context=parent}
            return context
        }
        let context=scene.path(to:playbackVisibilityFocus ?? store.hierarchySelection ?? .album)
            .last(where:{$0.radius*camera.zoom>min(workspaceViewport.width,workspaceViewport.height)*0.22}) ?? scene.node(.album)
        // Inspecting a circle's ports keeps its siblings and cables available until a precision editor opens.
        if let context,context.role == .music || (context.role == .group && !context.ports.isEmpty),
           editorAddress != context.id,let parent=context.parent {return scene.node(parent)}
        return context
    }
    var labelCircles:[CanvasLabelCircle] {
        guard let scene else{return []}
        return scene.nodes.compactMap{node in
            // Outward orbits occupy their own space: labels must also avoid song/section rings.
            // Expanded visual groups still surround their members, so exclude that enclosure.
            let blocksLabels = scene.isOrbit ? (node.role != .group || node.childCount == 0) : (node.childCount == 0 && (node.role == .music || node.role == .group))
            guard blocksLabels,isVisible(node),editorAddress != node.id else{return nil}
            let p=screen(node),r=node.radius*camera.zoom
            guard CGRect(x:p.x-r,y:p.y-r,width:r*2,height:r*2).intersects(workspaceViewport) else{return nil}
            return CanvasLabelCircle(id:node.id,center:p,radius:r)
        }
    }
    func readableLabelText(for node:CircleSceneNode)->CanvasLabelText {
        let primary=node.id==store.hierarchySelection ||
            (store.playback.playing && !visualFrame.stale && node.id==visualFrame.focus)
        let showsSubtitle=primary || node.radius*camera.zoom>=65
        let width=min(workspaceViewport.width,primary ? 340:248)
        let key=CanvasLabelTextKey(address:node.id,title:node.title,primary:primary,
            showsSubtitle:showsSubtitle,availableWidth:Double(width))
        if let cached=labelTextCache[key] {return cached}
        let text=CanvasLabelText(node.title,primary:primary,showsSubtitle:showsSubtitle,availableWidth:width)
        if labelTextCache.count>=512 {labelTextCache.removeAll(keepingCapacity:true)}
        labelTextCache[key]=text
        return text
    }
    var readableLabelObstacles:[CGRect] {
        var obstacles:[CGRect]=[]
        if let editor {obstacles.append(editor.frame.insetBy(dx:-8,dy:-8))}
        if let cableTools,!cableTools.isHidden {obstacles.append(cableTools.frame.insetBy(dx:-8,dy:-8))}
        if let portTools,!portTools.isHidden {obstacles.append(portTools.frame.insetBy(dx:-8,dy:-8))}
        if let point=store.selectedCircle.flatMap({visibleTimeHandle($0)}) {obstacles.append(CGRect(x:point.x-18,y:point.y-18,width:36,height:36))}
        let handles=cableEndpointHandles().map(\.1)+[selectedPortHandle()].compactMap{$0}
        obstacles += handles.map{CGRect(x:$0.point.x-12,y:$0.point.y-12,width:24,height:24)}
        return obstacles
    }
    func drawReadableLabels() {
        labelPlacements=[]
        guard !store.viewingMode else{return}
        guard let scene,let context=labelContext else{return}
        let ancestors=Set(scene.path(to:context.id).dropLast().map(\.id))
        let activeSection=store.playback.playing && !visualFrame.stale ? visualFrame.focus : nil
        var requests:[CanvasLabelRequest]=[],texts:[CircleAddress:CanvasLabelText]=[:]
        for node in scene.nodes where isVisible(node) && !ancestors.contains(node.id) && editorAddress != node.id {
            let activeFocus=node.id==activeSection
            let radius=node.radius*camera.zoom,p=screen(node),direct=node.parent==context.id
            let primary=node.id==store.hierarchySelection
            let emphasized=primary || activeFocus
            guard bounds.contains(p) || node.id==context.id || (emphasized && CanvasLabelCircle(id:node.id,center:p,radius:radius).intersects(workspaceViewport)) else{continue}
            guard activeFocus || node.id==context.id || direct || node.id==hoverAddress || (radius>=40 && node.depth<=context.depth+2) else{continue}
            let text=readableLabelText(for:node);texts[node.id]=text
            let expanded=node.childCount>0 && scene.children(of:node.id).contains(where:isVisible)
            // The playing section stays identifiable beside its orbit, ahead of selection and hover labels.
            requests.append(CanvasLabelRequest(id:node.id,anchor:p,size:text.size,radius:radius,expanded:expanded,priority:activeFocus ? 110:primary ? 100:node.id==hoverAddress ? 95:direct && ["MIDI","오디오"].contains(node.music?.content.label ?? "") ? 85:direct ? 70:20,allowsViewportAdjustment:emphasized))
        }
        labelPlacements=CanvasLabelLayout.place(requests,within:workspaceViewport,avoiding:readableLabelObstacles,circles:labelCircles)
        for placement in labelPlacements {
            guard let node=scene.node(placement.id),let text=texts[placement.id] else{continue}
            let rect=placement.rect,selected=store.hierarchySelections.contains(node.id),hovered=hoverAddress==node.id
            let activeFocus=node.id==activeSection
            if !rect.insetBy(dx:-8,dy:-8).contains(placement.anchor) {
                let end=CGPoint(x:max(rect.minX,min(rect.maxX,placement.anchor.x)),y:max(rect.minY,min(rect.maxY,placement.anchor.y)))
                let leader=NSBezierPath();leader.move(to:placement.anchor);leader.line(to:end)
                color(node).withAlphaComponent(selected || hovered || activeFocus ? 0.8:0.35).setStroke();leader.lineWidth=1;leader.stroke()
            }
            let path=NSBezierPath(roundedRect:rect,xRadius:6,yRadius:6)
            StudioTheme.surfaceNS.withAlphaComponent(0.98).setFill();path.fill()
            if selected || hovered || activeFocus {
                // Keep black custom accents legible without replacing the user's color.
                StudioTheme.textNS.withAlphaComponent(selected ? 0.75:activeFocus ? 0.68:0.55).setStroke()
                path.lineWidth=selected ? 4:activeFocus ? 3.5:3;path.stroke()
            }
            (selected || hovered || activeFocus ? color(node):StudioTheme.lineNS).setStroke();path.lineWidth=selected ? 2:activeFocus ? 1.8:1;path.stroke()
            text.title.draw(with:NSRect(x:rect.minX+10,y:rect.minY+6,width:max(1,rect.width-20),height:text.titleHeight),options:[.usesLineFragmentOrigin,.usesFontLeading,.truncatesLastVisibleLine])
            if text.showsSubtitle {drawText(node.subtitle+(node.repeatCount>1 ? " · ×\(node.repeatCount)":""),x:rect.midX,y:rect.minY+text.titleHeight+8,size:Double(StudioTheme.canvasSubtitleSize),color:StudioTheme.secondaryNS,maxWidth:rect.width-20)}
        }
    }
}
