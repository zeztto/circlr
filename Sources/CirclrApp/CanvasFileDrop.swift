import AppKit
import CirclrCore
import CirclrAudio

struct CanvasFileDropPreview {
    let urls:[URL]
    let section:CircleSceneNode
    let beat:Double
    let position:Point
    let cursor:NSPoint
    let midi:Bool
}

extension AlbumCanvasView {
    func fileDropTarget(_ sender:NSDraggingInfo)->CanvasFileDropPreview? {
        let point=convert(sender.draggingLocation,from:nil)
        guard store.canStartMediaImport,sender.draggingSourceOperationMask.contains(.copy),workspaceViewport.contains(point),
              ![editor?.frame,portTools?.frame,cableTools?.frame].compactMap({$0}).contains(where:{$0.contains(point)}),
              let hit=hit(point),let section=scene?.path(to:hit.id).last(where:{$0.role == .section}),
              let clock=section.clock else{return nil}
        guard let urls=sender.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL],!urls.isEmpty,urls.count<=64 else{return nil}
        let midi=urls.count==1 && ["mid","midi"].contains(urls[0].pathExtension.lowercased())
        guard midi || urls.allSatisfy({AudioFileImport.extensions.contains($0.pathExtension.lowercased())}) else {
            store.status="오디오 여러 개 또는 MIDI 한 개를 따로 끌어 놓으세요";return nil
        }
        let beat:Double
        if store.project.usesOrbits {
            let center=screen(section)
            let seconds=OrbitTimeline(clock:clock).seconds(at:Point(point.x-center.x,point.y-center.y))
            beat=OrbitEditing.snappedBeat(seconds:seconds,clock:clock,subdivisions:store.midiQuantizeSubdivision)
        } else {beat=store.selectedUse?.id == sectionUseID(section.id) ? min(max(0,store.selectedBeat),max(0,clock.beats-0.25)):0}
        return CanvasFileDropPreview(urls:urls,section:section,beat:beat,position:localCreationPoint(point,owner:section.id),cursor:point,midi:midi)
    }
    private func sectionUseID(_ address:CircleAddress)->ID? {if case .section(_,let u)=address{return u};return nil}
    override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation {draggingUpdated(sender)}
    override func draggingUpdated(_ sender:NSDraggingInfo)->NSDragOperation {
        fileDropPreview=fileDropTarget(sender);needsDisplay=true
        return fileDropPreview==nil ? []:.copy
    }
    override func draggingExited(_ sender:NSDraggingInfo?) {fileDropPreview=nil;needsDisplay=true}
    override func prepareForDragOperation(_ sender:NSDraggingInfo)->Bool {fileDropTarget(sender) != nil}
    override func performDragOperation(_ sender:NSDraggingInfo)->Bool {
        defer{fileDropPreview=nil;needsDisplay=true}
        guard let drop=fileDropTarget(sender),case .section(let a,let u)=drop.section.id else{return false}
        if drop.midi {
            return store.previewMIDIImport(drop.urls[0],projectID:store.project.id,revision:store.project.musicRevision,generation:store.mediaImportGeneration,arrangementID:a,useID:u,beat:drop.beat,position:drop.position)
        }
        let destination=AudioImportDestination.section(arrangementID:a,useID:u,trackID:nil,beat:drop.beat,position:drop.position,original:store.editOriginal)
        store.beginAudioImport(drop.urls,request:store.mediaImportRequest(destination))
        return store.mediaImportTask != nil
    }
    func drawFileDropPreview() {
        guard let drop=fileDropPreview,store.canStartMediaImport else{return}
        let center=screen(drop.section),radius=drop.section.radius*camera.zoom
        StudioTheme.accentNS.setStroke()
        let ring=NSBezierPath(ovalIn:NSRect(x:center.x-radius,y:center.y-radius,width:radius*2,height:radius*2));ring.lineWidth=2;ring.stroke()
        let title="\(drop.section.title) · "+(drop.midi ? "MIDI 트랙 선택":"오디오 \(drop.urls.count)개")+" · \(BeatPosition.text(drop.beat))박"
        let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:13,weight:.semibold),.foregroundColor:NSColor.white]
        let width=min(workspaceViewport.width-16,(title as NSString).size(withAttributes:attrs).width+24)
        let rect=NSRect(x:max(workspaceViewport.minX+8,min(drop.cursor.x+16,workspaceViewport.maxX-width-8)),y:max(workspaceViewport.minY+8,min(drop.cursor.y+18,workspaceViewport.maxY-40)),width:width,height:32)
        NSColor(white:0.13,alpha:1).setFill();NSBezierPath(roundedRect:rect,xRadius:6,yRadius:6).fill()
        let style=NSMutableParagraphStyle();style.lineBreakMode = .byTruncatingTail
        var textAttrs=attrs;textAttrs[.paragraphStyle]=style
        (title as NSString).draw(in:rect.insetBy(dx:12,dy:7),withAttributes:textAttrs)
    }
}
