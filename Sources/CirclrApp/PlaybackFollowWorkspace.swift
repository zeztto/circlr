import AppKit
import CirclrCore

@MainActor extension AppStore {
    var playbackFollowSettings: PlaybackFollowSettings { project.hierarchyView?.playbackFollowSettings ?? .init() }

    /// Workspace preference changes do not enter the musical Undo stack or invalidate playback.
    func setPlaybackFollowSettings(_ settings: PlaybackFollowSettings) {
        guard settings != playbackFollowSettings else { return }
        var viewport=project.hierarchyView ?? captureHierarchyViewport?() ?? HierarchyViewport(camera:.init(),width:1024,height:740,selection:hierarchySelection ?? .album)
        viewport.playbackFollowSettings=settings
        updatingHierarchyViewport=true
        project.hierarchyView=viewport
        updatingHierarchyViewport=false
        dirty=true
    }

    func choosePlaybackFollowTarget(_ target: PlaybackFollowTarget) {
        var settings=playbackFollowSettings
        if target == .pinned {
            guard let selected=hierarchySelection else { status="고정할 서클을 먼저 선택하세요"; return }
            settings.pinned=selected
        }
        settings.target=target
        setPlaybackFollowSettings(settings)
        playbackFollow = .following
    }

    func choosePlaybackFollowFraming(_ framing: PlaybackFollowFraming) {
        var settings=playbackFollowSettings;settings.framing=framing;setPlaybackFollowSettings(settings)
    }

    func choosePlaybackFollowTransition(_ transition: PlaybackFollowTransition) {
        var settings=playbackFollowSettings;settings.transition=transition;setPlaybackFollowSettings(settings)
    }
}

@MainActor extension AlbumCanvasView {
    /// Participation comes from the prepared graph, including silent processors, not its meters.
    func participatingFollowCircles(in scene: HierarchyScene) -> Set<CircleAddress> {
        guard let prepared=store.playback.prepared else { return [] }
        let seconds=store.playback.seconds
        let owners=Dictionary(store.project.arrangements.flatMap { arrangement in arrangement.uses.map { ($0.id,arrangement.id) } },uniquingKeysWith:{first,_ in first})
        var active=Set<CircleAddress>()
        for occurrence in prepared.plan.occurrences where occurrence.start <= seconds && seconds < occurrence.end {
            guard let owner=owners[occurrence.use.id] else { continue }
            active.insert(.section(arrangementID:owner,useID:occurrence.use.id))
            for node in occurrence.signalPlan?.orderedNodes ?? [] where !node.muted {
                let address=CircleAddress.music(arrangementID:owner,useID:occurrence.use.id,nodeID:node.id)
                // Source circles follow their scheduled spans; processors participate for the section.
                if node.content.input == nil, let visual=scene.node(address), visual.timeline != nil {
                    guard PlaybackPosition.localSeconds(for:visual,at:seconds,plan:prepared.plan,album:albumPlan,albumID:store.project.album?.id) != nil else { continue }
                }
                active.insert(address)
            }
        }
        if !active.isEmpty {
            // The album output graph processes the playing arrangement regardless of current level.
            for node in scene.nodes where node.signal != nil { active.insert(node.id) }
            for address in Array(active) { for parent in scene.path(to:address) { active.insert(parent.id) } }
        }
        return active
    }

    func animatePlaybackFollow(to next: HierarchyCamera, changesSection: Bool) {
        animation?.invalidate();animation=nil;animationDestination=next
        let settings=store.playbackFollowSettings
        let occurrence=store.playback.prepared.flatMap { PlaybackPosition.followOccurrence(in:$0.plan,at:store.playback.seconds) }
        let remaining=occurrence.map { max(0,$0.end-store.playback.seconds) }
        let curve=PlaybackFollowCameraCurve(start:camera,destination:next,viewport:workspaceViewport,
            transition:settings.transition,changesSection:changesSection,remainingSectionSeconds:remaining,reduceMotion:reducePlaybackMotion)
        guard curve.duration>0 else {camera=next;store.hierarchyZoom=next.zoom;placeEditor();needsDisplay=true;return}
        let began=ProcessInfo.processInfo.systemUptime
        animation=Timer(timeInterval:1/60,repeats:true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self,self.store.playback.playing,self.store.playbackFollow == .following else {timer.invalidate();return}
                let elapsed=ProcessInfo.processInfo.systemUptime-began
                self.camera=curve.camera(at:elapsed);self.placeEditor();self.needsDisplay=true
                if elapsed>=curve.duration {timer.invalidate();self.animation=nil;self.animationDestination=nil;self.store.hierarchyZoom=self.camera.zoom}
            }
        }
        if let animation { RunLoop.main.add(animation,forMode:.common) }
    }
}
