import AppKit
import CirclrCore

struct CanvasLabelText {
    let title:NSAttributedString
    let titleHeight:CGFloat
    let titleFits:Bool
    let showsSubtitle:Bool
    let subtitle:String
    let size:CGSize
    init(_ text:String,primary:Bool,showsSubtitle:Bool,subtitle:String,availableWidth:CGFloat,wrapTitle:Bool=false) {
        let font=NSFont.systemFont(ofSize:primary ? StudioTheme.canvasSelectedTitleSize:StudioTheme.canvasTitleSize,weight:primary ? .semibold:.medium)
        let subtitleFont=NSFont.systemFont(ofSize:StudioTheme.canvasSubtitleSize,weight:.medium)
        let titleWidth=ceil((text as NSString).size(withAttributes:[.font:font]).width)+20
        let subtitleWidth=showsSubtitle ? ceil((subtitle as NSString).size(withAttributes:[.font:subtitleFont]).width)+20:0
        let width=min(availableWidth,max(80,max(titleWidth,subtitleWidth)))
        let style=NSMutableParagraphStyle();style.alignment = .center
        style.lineBreakMode = primary || wrapTitle ? .byWordWrapping:.byTruncatingTail
        if primary || wrapTitle {style.lineBreakStrategy = .hangulWordPriority}
        style.minimumLineHeight=20;style.maximumLineHeight=20
        title=NSAttributedString(string:text,attributes:[.font:font,.foregroundColor:StudioTheme.textNS,.paragraphStyle:style])
        let measured=title.boundingRect(with:CGSize(width:max(1,width-20),height:.greatestFiniteMagnitude),options:[.usesLineFragmentOrigin,.usesFontLeading]).height
        let measuredHeight=max(20,ceil(measured/20)*20)
        titleHeight=primary ? min(60,measuredHeight):wrapTitle ? min(40,measuredHeight):20
        titleFits = !wrapTitle || measuredHeight<=40
        self.showsSubtitle=showsSubtitle
        self.subtitle=subtitle
        size=CGSize(width:width,height:titleHeight+16+(showsSubtitle ? 18:0))
    }
}

struct CanvasLabelTextKey: Hashable {
    let address:CircleAddress
    let title:String
    let primary:Bool
    let showsSubtitle:Bool
    let subtitle:String
    let availableWidth:Double
    let wrapTitle:Bool
}

/// Song-form order comes from compiled orbit intervals, not the satellites' free positions.
struct CanvasSongSegment: Equatable {
    let section: CircleAddress
    let order: Int
    let interval: OrbitInterval
    let songDuration: Double
    let orderLabel: String

    var duration: Double { interval.end-interval.start }
    init(section:CircleAddress,order:Int,interval:OrbitInterval,songDuration:Double) {
        self.section=section;self.order=order;self.interval=interval;self.songDuration=songDuration
        orderLabel=String(format:"%02d",order)
    }

    func hasRoomForOrder(at radius: Double) -> Bool {
        radius >= 48 && duration/songDuration * 2 * .pi * (radius-12) >= 20
    }
}

struct CanvasSongTimeline {
    private(set) var byOwner: [CircleAddress: [CanvasSongSegment]] = [:]
    private(set) var bySection: [CircleAddress: [CanvasSongSegment]] = [:]
    private var orderText: [CircleAddress: String] = [:]
    private var timingText: [CircleAddress: String] = [:]
    private var badgeTimingText: [CircleAddress: String] = [:]

    init() {}
    init(scene: HierarchyScene) {
        guard scene.isOrbit else { return }
        for owner in scene.nodes where owner.role == .song || owner.role == .movement {
            guard let total=owner.timeline?.duration, total.isFinite, total>0 else { continue }
            let candidates=scene.nodes.enumerated().flatMap { index, node -> [(Int, CircleAddress, OrbitInterval)] in
                guard node.role == .section, node.orbit?.owner == owner.id else { return [] }
                return (node.orbit?.intervals ?? []).compactMap { interval in
                    guard interval.start.isFinite, interval.end.isFinite,
                          interval.start>=0, interval.end>interval.start,
                          interval.end<=total+0.0001 else { return nil }
                    return (index,node.id,interval)
                }
            }.sorted { a,b in
                if a.2.start != b.2.start { return a.2.start < b.2.start }
                if a.2.end != b.2.end { return a.2.end < b.2.end }
                return a.0 < b.0
            }
            let segments=candidates.enumerated().map { position,item in
                CanvasSongSegment(section:item.1,order:position+1,interval:item.2,songDuration:total)
            }
            byOwner[owner.id]=segments
            for segment in segments { bySection[segment.section,default:[]].append(segment) }
        }
        for (section,segments) in bySection {
            orderText[section]=segments.count<=3 ? segments.map(\.orderLabel).joined(separator:", "):
                "\(segments[0].orderLabel) 외 \(segments.count-1)회"
            timingText[section]=segments.map { segment in
                "\(segment.orderLabel) · \(Self.time(segment.interval.start))–\(Self.time(segment.interval.end)) · 길이 \(Self.time(segment.duration))"
            }.joined(separator:" / ")
            if segments.count == 1 { badgeTimingText[section]=timingText[section] }
            else if let first=segments.first,let last=segments.last {
                badgeTimingText[section]="\(segments.count)회 · \(first.orderLabel) \(Self.time(first.interval.start))–\(Self.time(first.interval.end)) / \(last.orderLabel) \(Self.time(last.interval.start))–\(Self.time(last.interval.end))"
            }
        }
    }

    func segments(on owner: CircleAddress) -> [CanvasSongSegment] { byOwner[owner] ?? [] }
    func orderLabel(for section: CircleAddress) -> String? { orderText[section] }
    func timing(for section: CircleAddress) -> String? { timingText[section] }
    func badgeTiming(for section:CircleAddress)->String? { badgeTimingText[section] }
    static func isCurrent(_ interval:OrbitInterval,at seconds:Double,sectionActive:Bool)->Bool {
        sectionActive && seconds.isFinite && interval.start<=seconds && seconds<interval.end
    }
    private static func time(_ seconds: Double) -> String {
        let tenths=Int((seconds*10).rounded())
        return String(format:"%d:%02d.%d",tenths/600,(tenths/10)%60,tenths%10)
    }
}

/// Small processing satellites remain visible as circles during dense playback;
/// their labels return as soon as playback stops, the view zooms in, or editing begins.
enum CanvasPlaybackLabelLOD {
    static let denseProcessingCount=6

    static func isProcessing(_ content:MusicCircleContent?)->Bool {
        switch content {
        case .effect, .mix, .router, .output:return true
        default:return false
        }
    }

    static func compactPlayback(playing:Bool,stale:Bool,processingChildCount:Int,editing:Bool)->Bool {
        playing && !stale && !editing && processingChildCount>=denseProcessingCount
    }

    static func shows(_ content:MusicCircleContent?, screenRadius:Double,
                      direct:Bool, compactPlayback:Bool, emphasized:Bool)->Bool {
        guard compactPlayback,direct,screenRadius<32,!emphasized else{return true}
        return !isProcessing(content)
    }
}

extension AlbumCanvasView {
    var canvasViewport:CGRect {
        CanvasWorkspaceGeometry.viewport(width:bounds.width,height:bounds.height)
    }
    var consoleObstruction:CGRect? {
        !store.viewingMode && store.consoleBounds.height>0 ? store.consoleBounds:nil
    }
    var workspaceViewport:CGRect {
        CanvasWorkspaceGeometry.viewport(width:bounds.width,height:bounds.height,
            console:consoleObstruction)
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
            guard CGRect(x:p.x-r,y:p.y-r,width:r*2,height:r*2).intersects(canvasViewport) else{return nil}
            return CanvasLabelCircle(id:node.id,center:p,radius:r)
        }
    }
    func readableLabelText(for node:CircleSceneNode,title:String,subtitle:String,
                           maxWidth:CGFloat?=nil,wrapTitle:Bool=false,stableCompact:Bool=false)->CanvasLabelText {
        let primary = !stableCompact && (store.hierarchySelections.contains(node.id) ||
            (store.playback.playing && !visualFrame.stale &&
             (node.id==visualFrame.focus || visualFrame.activeSections.contains(node.id))))
        let hovered = !stableCompact && node.id==hoverAddress
        // Reserve the same subtitle row at every state so hover can show
        // timing without moving a compact badge away from the pointer.
        let showsSubtitle = stableCompact || primary || hovered || node.radius*camera.zoom>=65
        let width=min(canvasViewport.width,maxWidth ?? (primary || hovered ? 340:248))
        let key=CanvasLabelTextKey(address:node.id,title:title,primary:primary,
            showsSubtitle:showsSubtitle,subtitle:subtitle,availableWidth:Double(width),wrapTitle:wrapTitle)
        if let cached=labelTextCache[key] {return cached}
        let text=CanvasLabelText(title,primary:primary,showsSubtitle:showsSubtitle,subtitle:subtitle,
            availableWidth:width,wrapTitle:wrapTitle)
        if labelTextCache.count>=512 {labelTextCache.removeAll(keepingCapacity:true)}
        labelTextCache[key]=text
        return text
    }
    var readableLabelObstacles:[CGRect] {
        var obstacles:[CGRect]=[]
        if let console=consoleObstruction {obstacles.append(console.insetBy(dx:-14,dy:-14))}
        if !store.viewingMode,store.navigationBounds.height>0 {
            obstacles.append(store.navigationBounds.insetBy(dx:-8,dy:-8))
        }
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
        let activeSections=store.playback.playing && !visualFrame.stale ? visualFrame.activeSections : []
        // Count the context's own processing circles, not currently visible cables:
        // follow-camera movement must not flip every badge at a viewport edge.
        let processingChildCount=scene.children(of:context.id).reduce(0) {
            $0 + (CanvasPlaybackLabelLOD.isProcessing($1.music?.content) ? 1 : 0)
        }
        let compactPlayback=CanvasPlaybackLabelLOD.compactPlayback(
            playing:store.playback.playing,stale:visualFrame.stale,
            processingChildCount:processingChildCount,
            editing:editorAddress != nil || connecting != nil || cableDrag != nil ||
                dragNode != nil || orbitDrag != nil)
        let selectedEdge=selectedSceneCable
        var requests:[CanvasLabelRequest]=[],texts:[CircleAddress:CanvasLabelText]=[:]
        for node in scene.nodes where isVisible(node) && !ancestors.contains(node.id) && editorAddress != node.id {
            let activeFocus=activeSections.contains(node.id) || node.id==visualFrame.focus && store.playback.playing && !visualFrame.stale
            let radius=node.radius*camera.zoom,p=screen(node),direct=node.parent==context.id
            let primary=node.id==store.hierarchySelection
            let selected=store.hierarchySelections.contains(node.id)
            let emphasized=primary || selected || activeFocus
            guard bounds.contains(p) || node.id==context.id || (emphasized && CanvasLabelCircle(id:node.id,center:p,radius:radius).intersects(canvasViewport)) else{continue}
            guard activeFocus || node.id==context.id || direct || node.id==hoverAddress || (radius>=40 && node.depth<=context.depth+2) else{continue}
            let editingFocus=emphasized || node.id==hoverAddress || selectedCanvasPort?.node==node.id ||
                selectedEdge?.from==node.id || selectedEdge?.to==node.id
            guard CanvasPlaybackLabelLOD.shows(node.music?.content,screenRadius:radius,
                direct:direct,compactPlayback:compactPlayback,emphasized:editingFocus) else{continue}
            let order=songTimeline.orderLabel(for:node.id)
            let timing=(selected || node.id==hoverAddress || activeFocus) ? songTimeline.badgeTiming(for:node.id):nil
            let subtitle=timing ?? node.subtitle+(node.repeatCount>1 ? " · ×\(node.repeatCount)":"")
            let title=order.map{"\($0)  \(node.title)"} ?? node.title
            var text=readableLabelText(for:node,title:title,subtitle:subtitle)
            let portraitSongSection=direct && node.role == .section && canvasViewport.width<900
            // Keep the compact badge's dimensions stable under hover/selection:
            // otherwise it jumps away before the user can click it.
            if portraitSongSection && p.x>canvasViewport.midX {
                let rightSpace=canvasViewport.maxX-(p.x+radius+9)
                if rightSpace>=120 {
                    let plain=readableLabelText(for:node,title:title,subtitle:"",stableCompact:true)
                    if plain.size.width>180 {
                        let compact=readableLabelText(for:node,title:title,subtitle:subtitle,
                            maxWidth:min(132,rightSpace),wrapTitle:true,stableCompact:true)
                        if compact.titleFits {text=compact}
                    }
                }
            }
            texts[node.id]=text
            let expanded=node.childCount>0 && scene.children(of:node.id).contains(where:isVisible)
            // The playing section stays identifiable beside its orbit, ahead of selection and hover labels.
            requests.append(CanvasLabelRequest(id:node.id,anchor:p,size:text.size,radius:radius,expanded:expanded,priority:activeFocus ? 110:primary ? 100:node.id==hoverAddress ? 95:direct && ["MIDI","오디오"].contains(node.music?.content.label ?? "") ? 85:direct ? 70:20,allowsViewportAdjustment:emphasized || portraitSongSection,avoidsOwnRing:isTimelineRing(node)))
        }
        labelPlacements=CanvasLabelLayout.place(requests,within:canvasViewport,avoiding:readableLabelObstacles,circles:labelCircles)
        for placement in labelPlacements {
            guard let node=scene.node(placement.id),let text=texts[placement.id] else{continue}
            let rect=placement.rect,selected=store.hierarchySelections.contains(node.id),hovered=hoverAddress==node.id
            let activeFocus=activeSections.contains(node.id) || node.id==visualFrame.focus && store.playback.playing && !visualFrame.stale
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
            if text.showsSubtitle {
                drawText(text.subtitle,x:rect.midX,y:rect.minY+text.titleHeight+8,size:Double(StudioTheme.canvasSubtitleSize),color:StudioTheme.secondaryNS,maxWidth:rect.width-20)
            }
        }
    }
}
