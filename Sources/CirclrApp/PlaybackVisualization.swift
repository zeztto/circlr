import AppKit
import Combine
import CirclrCore
import CirclrAudio

struct PlaybackVisualFrame {
    var seconds = 0.0
    var levels: [CircleAddress: Double] = [:]
    var phases: [CircleAddress: Double] = [:]
    var edgeLevels: [String: Double] = [:]
    var activeSections = Set<CircleAddress>()
    var focus: CircleAddress?
    var caption = ""
    var stale = false
}

@MainActor extension AlbumCanvasView {
    var reducePlaybackMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func installPlaybackObservers() {
        guard let window else { return }
        for name in [NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification, NSWindow.didChangeOcclusionStateNotification] {
            playbackNotifications.append(NotificationCenter.default.publisher(for: name, object: window).sink { [weak self] _ in
                self?.refreshPlaybackAnimation()
            })
        }
        // Precision editors receive mouse events directly; interrupt before their gesture starts.
        interactionMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, event.window === self.window,
                  let content = self.window?.contentView,
                  let hit = content.hitTest(content.convert(event.locationInWindow, from: nil)),
                  hit === self || hit.isDescendant(of: self) else { return event }
            self.interruptPlaybackFollow()
            return event
        }
        refreshPlaybackAnimation()
    }

    func refreshPlaybackAnimation(playing: Bool? = nil) {
        let playing = playing ?? store.playback.playing
        let visible = store.movieWriter != nil || (window.map { !$0.isMiniaturized && $0.occlusionState.contains(.visible) } ?? false)
        if playing && visible {
            guard playbackAnimation == nil else { return }
            lastVisualFrameTime = 0
            followedSection = nil // A hidden window may have interrupted a camera transition.
            let timer = Timer(timeInterval: 1/60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updatePlaybackFrame() }
            }
            timer.tolerance = 0.002
            playbackAnimation = timer; RunLoop.main.add(timer, forMode: .common)
            updatePlaybackFrame()
        } else {
            if playbackAnimation != nil || followedSection != nil { animation?.invalidate(); animation = nil }
            playbackAnimation?.invalidate(); playbackAnimation = nil
            if !playing {
                visualFrame = PlaybackVisualFrame(); followedSection = nil
                if !store.playbackLocation.isEmpty { store.playbackLocation = "" }
                placeEditor(); needsDisplay = true
            }
        }
    }

    func interruptPlaybackFollow() {
        let mode = store.playbackFollow.interrupted(playing: store.playback.playing)
        if mode != store.playbackFollow {
            // Consume our own mode change before a click starts its manual focus animation.
            // A later SwiftUI update must not mistake that animation for the old follow transition.
            lastFollowMode = mode
            store.playbackFollow = mode
            animation?.invalidate(); animation = nil
            followedSection = nil
        }
    }

    func updatePlaybackFrame() {
        let started=ProcessInfo.processInfo.systemUptime
        defer { visualUpdateTiming.record(start:started,end:ProcessInfo.processInfo.systemUptime) }
        guard store.playback.playing else { refreshPlaybackAnimation(playing: false); return }
        guard let scene, let prepared = store.playback.prepared else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if lastVisualFrameTime > 0 { maximumFrameGap = max(maximumFrameGap, now-lastVisualFrameTime) }
        lastVisualFrameTime = now; frameCount += 1
        let frame=makePlaybackVisualFrame(at:store.playback.seconds,scene:scene,prepared:prepared)
        visualFrame=frame
        if frame.stale { animation?.invalidate(); animation = nil; needsDisplay = true; return }
        if store.playbackLocation != frame.caption { store.playbackLocation = frame.caption }
        followPlaybackSection()
        needsDisplay = true
    }

    /// Movie pixels and their PTS use the same estimated hardware instant.
    /// Leave the normal 60 Hz observer in charge of follow, captions, camera
    /// transitions and display callback diagnostics.
    func updateMoviePlaybackFrame(at elapsedSeconds:Double) {
        guard let scene else{return}
        let state=store.playback.visualState(atElapsed:elapsedSeconds)
        guard let prepared=state.prepared else{return}
        visualFrame=makePlaybackVisualFrame(at:state.seconds,scene:scene,prepared:prepared)
    }

    private func makePlaybackVisualFrame(at seconds:Double,scene:HierarchyScene,prepared:PreparedAudio)->PlaybackVisualFrame {
        var frame = PlaybackVisualFrame()
        frame.seconds = seconds
        frame.stale = prepared.plan.revision != store.project.musicRevision
        guard !frame.stale else {
            frame.caption = "편집한 음악은 다시 재생하면 반영됩니다"
            return frame
        }
        let plan = prepared.plan
        let owners = Dictionary(store.project.arrangements.flatMap { arrangement in arrangement.uses.map { ($0.id, arrangement.id) } }, uniquingKeysWith: { first, _ in first })
        if let current = PlaybackPosition.followOccurrence(in: plan, at: seconds), let arrangement = owners[current.use.id] {
            frame.focus = .section(arrangementID: arrangement, useID: current.use.id)
            let bar = current.clock.bar(at: current.clock.beat(atSeconds: max(0, seconds-current.start)))+1
            frame.caption = seconds >= plan.duration ? "\(current.use.name) · 잔향" : "\(current.use.name) · \(bar)마디 · \(current.iteration+1)회"
        }
        for node in scene.nodes {
            if let local = PlaybackPosition.localSeconds(for: node, at: seconds, plan: plan, album: albumPlan, albumID: store.project.album?.id), let timeline = node.timeline {
                frame.phases[node.id] = local/timeline.duration
                if node.role == .section { frame.activeSections.insert(node.id) }
            }
        }
        if let analysis = prepared.visualization {
            for occurrence in plan.occurrences where occurrence.start <= seconds && seconds < occurrence.end+prepared.tailSeconds {
                guard let data = analysis.occurrences[occurrence.id], let arrangement = owners[occurrence.use.id] else { continue }
                let local = seconds-occurrence.start, section = CircleAddress.section(arrangementID: arrangement, useID: occurrence.use.id)
                let level = data.section?.level(at: local) ?? 0
                frame.levels[section] = max(frame.levels[section] ?? 0,level)
                for parent in scene.path(to: section) { frame.levels[parent.id] = max(frame.levels[parent.id] ?? 0, level) }
                for (id, envelope) in data.nodes {
                    let address = CircleAddress.music(arrangementID: arrangement, useID: occurrence.use.id, nodeID: id)
                    let value = envelope.level(at: local)*occurrence.use.gain
                    frame.levels[address] = max(frame.levels[address] ?? 0, value)
                    for parent in scene.path(to: address) where parent.role == .group { frame.levels[parent.id] = max(frame.levels[parent.id] ?? 0, value) }
                }
            }
            for (id, envelope) in analysis.signals { frame.levels[.signal(id)] = envelope.level(at: seconds) }
            frame.levels[.album] = analysis.master?.level(at: seconds) ?? 0
            frame.levels[.sound] = frame.levels[.album]
        }
        for node in scene.nodes where node.role == .music && frame.levels[node.id] == nil {
            frame.phases.removeValue(forKey: node.id)
        }
        for edge in scene.edges {
            let logicalFrom=edge.connectionID?.from ?? edge.from,logicalTo=edge.connectionID?.to ?? edge.to
            // A collapsed group's displayed endpoint still represents the hidden engine node.
            if logicalFrom != edge.from {frame.levels[edge.from]=max(frame.levels[edge.from] ?? 0,frame.levels[logicalFrom] ?? 0)}
            if logicalTo != edge.to {frame.levels[edge.to]=max(frame.levels[edge.to] ?? 0,frame.levels[logicalTo] ?? 0)}
            if edge.kind == .flow {
                if plan.transitions.contains(where: { $0.edgeID == edge.id && $0.start <= seconds && seconds < $0.start+max(0.35, $0.duration) }) {
                    frame.edgeLevels[edge.id] = max(0.3, frame.levels[edge.from] ?? 0, frame.levels[edge.to] ?? 0)
                } else if case .section(_, let source) = logicalFrom, case .section(_, let target) = logicalTo,
                          plan.occurrences.enumerated().contains(where: { i, occurrence in
                              i > 0 && occurrence.use.id == target && plan.occurrences[i-1].use.id == source &&
                              occurrence.start <= seconds && seconds < occurrence.start+0.35
                          }) {
                    frame.edgeLevels[edge.id] = 0.6
                }
            } else if let connection = edge.connectionID, case .music = connection.from {
                frame.edgeLevels[edge.id] = prepared.visualization?.edgeLevel(connection, at: seconds, plan: plan, tail: prepared.tailSeconds) ?? 0
            } else if frame.levels[edge.to] != nil {
                frame.edgeLevels[edge.id] = (frame.levels[edge.from] ?? 0)*edge.gain
            }
        }
        return frame
    }

    func followPlaybackSection() {
        guard store.playbackFollow == .following, bounds.width > 100 else { return }
        let settings=store.playbackFollowSettings
        if settings.target == .pinned,let pin=settings.pinned,(visualFrame.stale || scene?.node(pin) == nil),
           let revealed=try? HierarchySceneBuilder.build(store.project,revealing:pin) { scene=revealed }
        guard let scene else { return }
        let resolution=PlaybackFollowResolver.resolve(settings,currentSection:visualFrame.focus,
            activeCircles:settings.target == .pinned ? participatingFollowCircles(in:scene) : [],in:scene)
        // A stale render may still reveal a removed pin. Suspend it immediately,
        // but never move the camera using playback positions from old music.
        if visualFrame.stale,resolution != .missingPinnedTarget {
            if animation?.isValid == true {followedSection=nil}
            animation?.invalidate();animation=nil;animationDestination=nil
            return
        }
        let target:CircleAddress
        switch resolution {
        case .inactive:
            // Resume an interrupted arrival when this pin participates again.
            // A completed arrival keeps its cache, avoiding redundant loop zooms.
            if animation?.isValid == true {followedSection=nil}
            animation?.invalidate();animation=nil;animationDestination=nil
            return
        case .missingPinnedTarget:
            animation?.invalidate();animation=nil;animationDestination=nil
            store.playbackFollow = .suspended
            store.status="고정한 서클을 찾을 수 없습니다. 팔로우 대상을 다시 선택하세요"
            followedSection=nil
            return
        case .target(let address): target=address
        }
        let viewport=canvasViewport,console=consoleObstruction
        guard target != followedSection || viewport != playbackFollowViewport ||
              console != playbackFollowConsole || settings != lastFollowSettings else { return }
        var framingCamera=camera
        if settings.framing == .keepZoom,animation?.isValid == true,let destination=animationDestination {framingCamera.zoom=destination.zoom}
        guard let next=PlaybackFollowResolver.camera(for:target,settings:settings,current:framingCamera,
                                                      scene:scene,viewport:viewport,avoiding:console) else { return }
        // Only real section-use changes get the excursion, never initial focus or a loop of one use.
        let changesSection=settings.target == .section && followedSection != nil && target != followedSection && lastFollowSettings.target == .section
        followedSection=target;lastFollowSettings=settings
        contextFitAddress=nil;contextFitViewport=nil;contextFitConsole=nil
        playbackVisibilityFocus=target;playbackFollowViewport=viewport;playbackFollowConsole=console
        animatePlaybackFollow(to:next,changesSection:changesSection)
    }

    func displayStrength(_ level: Double) -> Double {
        guard level.isFinite, level > 0.0001 else { return 0 }
        return min(1, log1p(level*24)/log(25))
    }

    func drawPlaybackCircle(_ node: CircleSceneNode) {
        guard !visualFrame.stale, store.playback.playing else { return }
        let center = screen(node), radius = node.radius*camera.zoom
        guard radius > 6, radius < max(bounds.width, bounds.height)*3,
              NSRect(x: center.x-radius-20, y: center.y-radius-20, width: radius*2+40, height: radius*2+40).intersects(bounds) else { return }
        let strength = displayStrength(visualFrame.levels[node.id] ?? 0), active = visualFrame.activeSections.contains(node.id)
        let tint = node.music?.content.output == .audio ? NSColor(srgbRed: 0.62, green: 0.75, blue: 0.94, alpha: 1) : StudioTheme.accentNS
        if strength > 0 || active {
            let ring = NSBezierPath(ovalIn: NSRect(x: center.x-radius, y: center.y-radius, width: 2*radius, height: 2*radius))
            tint.withAlphaComponent(active ? 0.65 : 0.2+strength*0.6).setStroke()
            ring.lineWidth = 1.2+strength*2.2; ring.stroke()
            if !reducePlaybackMotion, strength > 0 {
                let expansion = 3+strength*9
                let halo = NSBezierPath(ovalIn: NSRect(x: center.x-radius-expansion, y: center.y-radius-expansion, width: 2*(radius+expansion), height: 2*(radius+expansion)))
                tint.withAlphaComponent(strength*0.19).setStroke(); halo.lineWidth = 2+strength*3; halo.stroke()
            }
        }
        let phase = visualFrame.phases[node.id] ?? (strength > 0 ? (visualFrame.seconds*node.context.tempo/120).truncatingRemainder(dividingBy: 1) : nil)
        if let phase, !reducePlaybackMotion {
            for segment in 0..<7 {
                let end = phase-Double(segment)*0.008
                let trail = OrbitDrawing.arc(center, radius: radius, from: end-0.009, to: end)
                tint.withAlphaComponent((1-Double(segment)/7)*(0.25+strength*0.65)).setStroke()
                trail.lineWidth = 2+strength*2; trail.stroke()
            }
            if visualFrame.phases[node.id] == nil, strength > 0 {
                OrbitDrawing.dot(OrbitDrawing.point(center, radius: radius, phase: phase), radius: 2+strength*2, color: tint)
            }
        }
        drawPlayhead(node)
        if store.viewingMode, node.id == visualFrame.focus {
            // Four quiet brackets identify the followed section without putting text in the visualizer.
            let markerRadius = radius+9
            let halfSpan = max(0.006, min(0.026, 7/(2*Double.pi*markerRadius)))
            StudioTheme.textNS.withAlphaComponent(0.9).setStroke()
            for quarter in 0..<4 {
                let phase = Double(quarter)/4+0.125
                let bracket = OrbitDrawing.arc(center, radius: markerRadius, from: phase-halfSpan, to: phase+halfSpan)
                bracket.lineWidth = 2.4; bracket.stroke()
            }
        }
    }

    func drawPlaybackEdge(_ edge: CircleSceneEdge, curve: CirclePortCurve, tint: NSColor, fade: Double, drawGlowWire: Bool) {
        let strength = displayStrength(visualFrame.edgeLevels[edge.id] ?? 0)
        guard strength > 0, !visualFrame.stale, store.playback.playing else { return }
        if drawGlowWire {
            wire(curve, color: tint.withAlphaComponent((0.3+strength*0.55)*(1-0.82*fade)), dashed: edge.kind == .sidechain)
        }
        guard !reducePlaybackMotion else { return }
        func point(_ t: Double) -> NSPoint {
            let p = (try? curve.point(at: t)) ?? curve.from
            return NSPoint(x: p.x, y: p.y)
        }
        let pulseCount = fade >= 0.5 ? 1 : 3
        for index in 0..<pulseCount {
            let phase = (visualFrame.seconds*0.65+Double(index)/Double(pulseCount)).truncatingRemainder(dividingBy: 1)
            let path = NSBezierPath()
            for step in 0...6 {
                let p = point(max(0, phase-0.05+Double(step)*0.05/6))
                if step == 0 { path.move(to: p) } else { path.line(to: p) }
            }
            tint.withAlphaComponent((0.45+strength*0.5)*(1-0.3*fade)).setStroke(); path.lineWidth = 1.5+strength*2; path.lineCapStyle = .round; path.stroke()
            OrbitDrawing.dot(point(phase), radius: 1.4+strength*1.8, color: StudioTheme.textNS.withAlphaComponent((0.4+strength*0.6)*(1-0.25*fade)))
        }
    }

    func drawPlaybackCaption() {
        guard store.playback.playing, !visualFrame.caption.isEmpty else { return }
        drawText(visualFrame.caption, x: bounds.midX, y: 61, size: 12, color: visualFrame.stale ? StudioTheme.secondaryNS : StudioTheme.accentNS, maxWidth: max(150, bounds.width-400))
    }

    func playbackDiagnostics() -> [String: Any] {
        ["playing": store.playback.playing, "seconds": store.playback.seconds, "displaySeconds": visualFrame.seconds,
         "follow": store.playbackFollow.rawValue, "followSettings":store.json(store.playbackFollowSettings), "followedTarget":store.json(followedSection), "focusedSection": store.json(followedSection),
         "currentSection": store.json(visualFrame.focus), "caption": visualFrame.caption,
         "stale": visualFrame.stale, "animated": playbackAnimation != nil,
         "windowAttached": window != nil, "windowVisible": window?.isVisible ?? false,
         "windowOccluded": !(window?.occlusionState.contains(.visible) ?? false),
         "meterPlaying": store.meter.playing,
         "frameCount": frameCount, "maximumFrameGap": maximumFrameGap, "reduceMotion": reducePlaybackMotion,
         "connectionDensityFade":densePlaybackFade,
         "timing": ["visualUpdate":visualUpdateTiming.diagnostics, "screenDraw":screenDrawTiming.diagnostics,
                    "movieDraw":movieDrawTiming.diagnostics, "movieCapture":movieCaptureTiming.diagnostics,
                    "movieTick":store.movieTickTiming.diagnostics],
         "movie":store.movieWriter.map { recorder in
             ["submitted":recorder.submittedFrameCount,"encoded":recorder.frameCount,
              "skipped":recorder.skippedCaptureCount,"dropped":recorder.droppedFrames,
              "pending":recorder.pendingFrameCount,"maximumEncodeMilliseconds":recorder.maximumEncodeSeconds*1000,
              "directCaptures":movieDirectCaptureCount,"subviewCaptures":movieSubviewCaptureCount,
              "previewDraws":moviePreviewDrawCount] as [String:Any]
         } ?? [:],
         "camera": store.json(camera), "canvasSize": [bounds.width, bounds.height],
         "orbitContext":store.json(labelContext?.id),
         "visibleCircles":(scene?.nodes ?? []).filter(isVisible).map { node -> [String:Any] in
             let p=screen(node)
             return ["address":store.json(node.id),"center":[p.x,p.y],"radius":node.radius*camera.zoom,
                     "hollow":isTimelineRing(node),"centerHit":store.json(hit(p)?.id),
                     "timeHandle":visibleTimeHandle(node).map{[$0.x,$0.y]} ?? []]
         },
         "ports":cableDiagnostics(),
         "editorAddress":store.json(editorAddress), "editorFrame":editor.map{[$0.frame.minX,$0.frame.minY,$0.frame.width,$0.frame.height]} ?? [],
         "canvasKeyboardFocus":window?.firstResponder === self,
         "workspaceViewport":[workspaceViewport.minX,workspaceViewport.minY,workspaceViewport.width,workspaceViewport.height],
         "labels":labelPlacements.map{["address":store.json($0.id),"rect":[$0.rect.minX,$0.rect.minY,$0.rect.width,$0.rect.height],
                                       "anchor":[$0.anchor.x,$0.anchor.y],"selected":store.hierarchySelections.contains($0.id),
                                       "title":scene?.node($0.id)?.title ?? ""]},
         "labelCircles":labelCircles.map{["address":store.json($0.id),"center":[$0.center.x,$0.center.y],"radius":$0.radius]},
         "followViewport": [playbackFollowViewport.minX, playbackFollowViewport.minY, playbackFollowViewport.width, playbackFollowViewport.height],
         "nodes": visualFrame.levels.filter { $0.value > 0.0001 }.map { ["address": store.json($0.key), "level": $0.value] },
         "edges": visualFrame.edgeLevels.filter { $0.value > 0.0001 },
         "phases": visualFrame.phases.map { ["address": store.json($0.key), "phase": $0.value] }]
    }
}
