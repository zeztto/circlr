import Foundation

/// Source seconds. Windows preserve resampling/stretch history across a non-destructive cut.
public struct AudioFadeEnvelope:Codable,Equatable {
    public var start:Double
    public var duration:Double
    public var fadeIn:Double
    public var fadeOut:Double
    public init(start:Double,duration:Double,fadeIn:Double,fadeOut:Double){self.start=start;self.duration=duration;self.fadeIn=fadeIn;self.fadeOut=fadeOut}
    public func gain(at source:Double)->Double {
        let input=fadeIn>0 ? min(1,max(0,(source-start)/fadeIn)):1
        let output=fadeOut>0 ? min(1,max(0,(start+duration-source)/fadeOut)):1
        return input*output
    }
}
public struct AudioRenderWindow:Codable,Equatable {
    public var sourceStart:Double
    public var duration:Double
    public var cycleBeat:Double
    public var automaticEdges:Bool
    public var envelopes:[AudioFadeEnvelope]
}
public extension AudioClip {
    var loopSourceDuration:Double {renderWindow?.duration ?? duration}
    var explicitEnvelope:AudioFadeEnvelope? {
        guard fadeIn != nil || fadeOut != nil else{return nil}
        return AudioFadeEnvelope(start:sourceStart,duration:duration,fadeIn:fadeIn ?? 0,fadeOut:fadeOut ?? 0)
    }
    func validateEditing(asset:Asset,checkBounds:Bool=true)throws {
        let tolerance=1/max(1,asset.sampleRate)
        if checkBounds {guard sourceStart+duration<=asset.duration+tolerance else {throw CirclrError("오디오 구간이 원본 파일 길이를 넘습니다")}}
        func envelope(_ e:AudioFadeEnvelope)throws {
            guard e.start.isFinite,e.start>=0,e.duration.isFinite,e.duration>0,
                  e.fadeIn.isFinite,e.fadeOut.isFinite,e.fadeIn>=0,e.fadeOut>=0,e.fadeIn+e.fadeOut<=e.duration+1e-8 else {throw CirclrError("페이드 길이는 0 이상이며 두 페이드의 합이 오디오 구간을 넘을 수 없습니다")}
        }
        if let e=explicitEnvelope {try envelope(e)}
        if let w=renderWindow {
            guard w.sourceStart.isFinite,w.sourceStart>=0,w.duration.isFinite,w.duration>0,w.cycleBeat.isFinite,abs(w.cycleBeat)<=1_048_576,
                  w.sourceStart+w.duration<=asset.duration+tolerance,w.sourceStart<=sourceStart+tolerance,
                  sourceStart+duration<=w.sourceStart+w.duration+tolerance,w.envelopes.count<=128 else {throw CirclrError("분할 오디오의 원본 처리 구간을 확인하세요")}
            for e in w.envelopes {try envelope(e);guard e.start>=w.sourceStart-tolerance,e.start+e.duration<=w.sourceStart+w.duration+tolerance else {throw CirclrError("보존된 페이드가 원본 처리 구간을 넘습니다")}}
        }
    }
}

public struct AudioClipTiming {
    public let node:MusicCircle
    public let context:MusicContext
    public let clock:MusicClock
    public init(node:MusicCircle,context:MusicContext,clock:MusicClock){self.node=node;self.context=context;self.clock=clock}
    public var ownTempo:Bool {node.settings.tempo.source != .inherit}
    public func time(_ beat:Double)->Double {ownTempo ? clock.seconds(at:node.startBeat)+beat*60/context.tempo:clock.seconds(at:node.startBeat+beat)}
    public func beat(at time:Double)->Double {ownTempo ? (time-clock.seconds(at:node.startBeat))*context.tempo/60:clock.beat(atSeconds:time)-node.startBeat}
    public func rate(_ clip:AudioClip)->Double {clip.followsTempo ? (ownTempo ? context.tempo:clock.bpm(at:node.startBeat+clip.beat))/clip.sourceBPM:1}
    /// The renderer uses one stretch rate for every repetition. Only audible,
    /// half-open source spans must share that rate; tempo changes in silence do not matter.
    public func validateTempoFollowing(_ clip:AudioClip,renderEndSeconds:Double?=nil)throws {
        guard clip.followsTempo,!ownTempo,clock.tempos.count>1 else{return}
        let speed=rate(clip),baseBPM=clock.bpm(at:node.startBeat+clip.beat)
        guard speed.isFinite,speed>0,clip.duration.isFinite,clip.duration>0,
              (1...256).contains(node.repeatCount) else{throw CirclrError("오디오 템포와 반복 구간을 확인하세요")}
        let renderedEnd=renderEndSeconds ?? clock.seconds
        guard renderedEnd.isFinite,renderedEnd>=0 else{throw CirclrError("오디오 재생 구간을 확인하세요")}
        let epsilon=1e-9 // Numerical boundary tolerance, far below one 48 kHz frame.
        let changes=clock.tempos.map{(seconds:clock.seconds(at:$0.beat),bpm:$0.bpm)}
        for iteration in 0..<node.repeatCount {
            if let length=node.lengthBeats,clip.beat>=length {break}
            let start=position(clip,iteration:iteration)
            guard start.isFinite else{throw CirclrError("오디오 재생 구간을 확인하세요")}
            if start>=clock.seconds {break}
            let limit:Double
            if let length=node.lengthBeats {limit=min(clock.seconds,time(Double(iteration+1)*length))}
            else {limit=clip.preservesTail == true ? renderedEnd:clock.seconds}
            let end=min(limit,start+clip.duration/speed)
            if end<=start {continue}
            let bpm=changes.last(where:{$0.seconds<=start+epsilon})?.bpm ?? baseBPM
            guard bpm==baseBPM,!changes.contains(where:{$0.seconds>start+epsilon && $0.seconds<end-epsilon && $0.bpm != baseBPM}) else {
                throw CirclrError("오디오 재생 구간이나 반복 사이의 템포가 바뀝니다. 개별 서클 템포를 지정하세요")
            }
        }
    }
    /// Shared preflight for UI and mutation; source duration, repeats and explicit loop length agree.
    public func duplicateBeat(_ clip:AudioClip,offset:Double?=nil)throws->Double {
        let speed=rate(clip)
        guard speed.isFinite,speed>0 else{throw CirclrError("오디오 템포를 확인하세요")}
        let delta:Double
        if let offset {guard offset.isFinite else{throw CirclrError("복제 이동 박을 확인하세요")};delta=offset}
        else if let length=node.lengthBeats {delta=Double(node.repeatCount)*length}
        else {delta=beat(at:time(clip.beat)+(Double(node.repeatCount-1)*clip.loopSourceDuration+clip.duration)/speed)-clip.beat}
        let start=clip.beat+delta
        guard start>=0,time(start)<clock.seconds else{throw CirclrError("복제할 공간이 없습니다. 섹션 길이를 늘리거나 이동 박을 줄이세요")}
        return start
    }
    public func position(_ clip:AudioClip,iteration:Int)->Double {
        if let length=node.lengthBeats {
            guard let origin=clip.renderWindow?.cycleBeat else{return time(Double(iteration)*length+clip.beat)}
            return time(Double(iteration)*length+origin)+time(clip.beat)-time(origin)
        }
        return time(clip.beat)+Double(iteration)*clip.loopSourceDuration/rate(clip)
    }
}

public enum AudioEditing {
    public enum Change {case split(sourceOffset:Double),duplicate(beatOffset:Double?),fade(input:Double,output:Double),replace(AudioClip),delete}
    @discardableResult public static func apply(_ change:Change,nodeID:ID,useID:ID,original:Bool=false,in project:inout Project)throws->ID? {
        var p=project
        guard let use=p.active.uses.first(where:{$0.id==useID}) else{throw CirclrError("오디오 섹션을 찾을 수 없습니다")}
        let (section,context,clock)=try ArrangementCompiler.context(project:p,use:use)
        guard var graph=try original ? section.graph:SectionGraphEditing.effective(section:section,use:use),
              let index=graph.nodes.firstIndex(where:{$0.id==nodeID}),case .audio(let laneID,let clipID)=graph.nodes[index].content,
              var lane=(original ? section.lanes:try ArrangementCompiler.effectiveLanes(section:section,use:use)).first(where:{$0.id==laneID}),
              let ci=lane.audio.firstIndex(where:{$0.id==clipID}),let asset=p.assets.first(where:{$0.id==lane.audio[ci].assetID}) else {throw CirclrError("편집할 오디오 서클을 선택하세요")}
        var clip=lane.audio[ci],node=graph.nodes[index]
        try clip.validateEditing(asset:asset)
        let resolved=try ContextResolver.inheriting(global:p.global,parent:context,settings:node.settings)
        let timing=AudioClipTiming(node:node,context:resolved,clock:clock),rate=timing.rate(clip)
        guard rate.isFinite,rate>0 else{throw CirclrError("오디오 템포를 확인하세요")}
        let shared=graph.nodes.filter{if case .audio(let l,let c)=$0.content{return l==laneID && c==clipID};return false}.count>1
        var result:ID?=nodeID
        switch change {
        case .replace(let replacement):
            guard replacement.id==clip.id,replacement.assetID==clip.assetID else{throw CirclrError("편집할 오디오 원본이 변경되었습니다")}
            try replacement.validateEditing(asset:asset)
            guard replacement != clip else{return nodeID}
            clip=replacement
            if shared {clip.id=newID();lane.audio.append(clip);graph.nodes[index].content = .audio(laneID:laneID,clipID:clip.id)}else{lane.audio[ci]=clip}
        case .delete:
            SectionGraphEditing.remove([nodeID],from:&graph)
            if !shared {lane.audio.remove(at:ci)}
            result=nil
        case .fade(let input,let output):
            clip.fadeIn=input;clip.fadeOut=output;try clip.validateEditing(asset:asset)
            if clip==lane.audio[ci] {return nodeID}
            if shared {clip.id=newID();lane.audio.append(clip);graph.nodes[index].content = .audio(laneID:laneID,clipID:clip.id)}else{lane.audio[ci]=clip}
        case .split(let offset):
            guard offset.isFinite,offset>0,offset<clip.duration else{throw CirclrError("분할 위치를 선택 구간 안에 지정하세요")}
            try timing.validateTempoFollowing(clip)
            let seconds=(offset/rate*48000).rounded()/48000,cut=seconds*rate
            guard cut>0,cut<clip.duration,timing.time(clip.beat)+seconds<clock.seconds,
                  node.lengthBeats.map({timing.time(clip.beat)+seconds<timing.time($0)}) ?? true else{throw CirclrError("분할 위치가 서클의 재생 구간 밖입니다")}
            var window=clip.renderWindow ?? AudioRenderWindow(sourceStart:clip.sourceStart,duration:clip.duration,cycleBeat:clip.beat,automaticEdges:clip.explicitEnvelope==nil && clip.preservesTail != true,envelopes:[])
            if let e=clip.explicitEnvelope,e.fadeIn>0 || e.fadeOut>0 {window.envelopes.append(e)}
            var right=clip;right.id=newID();right.sourceStart+=cut;right.duration-=cut;right.beat=timing.beat(at:timing.time(clip.beat)+seconds)
            clip.duration=cut
            clip.renderWindow=window;right.renderWindow=window;clip.fadeIn=0;clip.fadeOut=0;right.fadeIn=0;right.fadeOut=0
            if shared {clip.id=newID();lane.audio.append(clip)}else{lane.audio[ci]=clip}
            lane.audio.append(right);node.content = .audio(laneID:laneID,clipID:clip.id)
            if var bounce=node.bounce {bounce.familyID=bounce.familyID ?? node.id;node.bounce=bounce}
            graph.nodes[index]=node
            var other=node;other.id=newID();other.name += " · 뒤";other.content = .audio(laneID:laneID,clipID:right.id)
            append(other,after:node,in:&graph);result=other.id
        case .duplicate(let offset):
            let start=try timing.duplicateBeat(clip,offset:offset),delta=start-clip.beat
            var copy=clip;copy.id=newID();copy.beat=start
            if copy.renderWindow != nil {copy.renderWindow?.cycleBeat += delta}
            lane.audio.append(copy)
            if var bounce=node.bounce {bounce.familyID=bounce.familyID ?? node.id;node.bounce=bounce;graph.nodes[index]=node}
            var other=node;other.id=newID();other.name += " · 복제";other.content = .audio(laneID:laneID,clipID:copy.id)
            if node.lengthBeats==nil,other.automation != nil {
                for l in other.automation!.indices {for p in other.automation![l].points.indices {other.automation![l].points[p].beat += delta}}
            }
            // Duplicating an explicitly looped circle moves its origin, retaining local clip placement.
            if node.lengthBeats != nil {other.startBeat=timing.clock.beat(atSeconds:timing.time(delta));copy.beat=clip.beat;copy.renderWindow=clip.renderWindow;lane.audio[lane.audio.count-1]=copy}
            append(other,after:node,in:&graph);result=other.id
        }
        try ArrangementCompiler.validateLanes([lane],project:p)
        try ProjectEditing.setLane(lane,for:useID,original:original,in:&p)
        try SectionGraphEditing.set(graph,useID:useID,original:original,in:&p)
        try ProjectStore.validateStructure(p);project=p;return result
    }
    private static func append(_ node:MusicCircle,after source:MusicCircle,in graph:inout SectionGraph) {
        let outputs=graph.edges.filter{$0.from==source.id}
        graph.nodes.append(node)
        for edge in outputs {var e=edge;e.id=newID();e.from=node.id;graph.edges.append(e)}
        let point=graph.layout.positions[source.id] ?? Point();graph.layout.positions[node.id]=Point(point.x+90,point.y+130)
        for i in graph.layout.groups.indices where graph.layout.groups[i].members.contains(source.id) {graph.layout.groups[i].members.append(node.id)}
    }
}
