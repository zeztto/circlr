import SwiftUI
import AppKit
import CirclrCore
import CirclrAudio

struct HierarchyCommand: Equatable {
    enum Action: Equatable { case focus(CircleAddress, Bool), parent, fit, restore, zoom(Double) }
    let id = UUID()
    let action: Action
}

extension AppStore {
    var hierarchyScene: HierarchyScene? {
        if hierarchyCacheRevision != hierarchyRevision {
            hierarchyCacheRevision = hierarchyRevision
            hierarchyCache = try? HierarchySceneBuilder.build(project)
        }
        return hierarchyCache
    }
    var selectedCircle: CircleSceneNode? { hierarchySelection.flatMap { hierarchyScene?.node($0) } }
    var selectedMusic: MusicCircle? { selectedCircle?.music }
    var selectedLaneID: ID? {
        switch selectedMusic?.content {
        case .midi(let id), .audio(let id, _): return id
        default: return nil
        }
    }
    var selectedGraph: SectionGraph? {
        guard let use = selectedUse, let section = project.sections.first(where: { $0.id == use.sectionID }) else { return nil }
        return try? SectionGraphEditing.effective(section: section, use: use)
    }
    func selectHierarchy(_ address: CircleAddress, additive: Bool = false) {
        if address != hierarchySelection { connectionsOpen = false; connectionEditorIntent = nil }
        if address != hierarchySelection {midiImportDraft=nil;audioSplitOffset=nil;selectedAutomationPointID=nil;cancelRecordingRequest()}
        if hierarchySelection != address, midiRecording || audioRecording { stopRecording() }
        if hierarchySelection != address { hierarchyTransitionID=nil; cancelAudition(); embeddedPlugin = nil; selectedNoteID = nil; selectedClipID = nil; editPatternID = nil; selectedBeat = 0; focus = nil }
        hierarchySelection = address
        edgeSelection = nil
        soundView = address == .sound || { if case .signal = address { return true }; return false }()
        if additive, hierarchyScene?.node(address)?.parent == hierarchySelections.first.flatMap({ hierarchyScene?.node($0)?.parent }) {
            if hierarchySelections.contains(address) { hierarchySelections.remove(address) } else { hierarchySelections.insert(address) }
        } else { hierarchySelections = [address] }
        switch address {
        case .album, .sound: selection = []
        case .signal(let id): selection = [id]; selectedTrackID = project.signal.nodes.first { $0.id == id }?.trackID
        case .group(let parent, _):
            // Resolving a group's music scope must not close its own inline connection editor.
            let chosen = hierarchySelections, open = connectionsOpen, intent = connectionEditorIntent
            selectHierarchy(parent); hierarchySelection = address; hierarchySelections = chosen
            connectionsOpen = open; connectionEditorIntent = intent
        case .composition(let id):
            selection = []
            if let arrangement = project.album?.composition(id)?.selectedArrangementID { project.activeArrangementID = arrangement }
        case .section(let arrangement, let use), .music(let arrangement, let use, _):
            project.activeArrangementID = arrangement; selection = [use]
        }
        if let content = selectedMusic?.content {
            switch content {
            case .midi(let lane), .audio(let lane, _):
                if let use = selectedUse, let section = project.sections.first(where: { $0.id == use.sectionID }) {
                    selectedTrackID = (try? ArrangementCompiler.effectiveLanes(section: section, use: use))?.first { $0.id == lane }?.trackID
                }
                if case .audio(_, let clip) = content { selectedClipID = clip }
            case .instrument(let track), .output(let track): selectedTrackID = track
            case .rhythmMIDI(let track), .rhythmAudio(let track): selectedTrackID = track; editPatternID = selectedCircle?.context.rhythm.patternID
            case .effect,.mix,.router:
                let tracks=selectedMusic.flatMap{node in selectedGraph.map{StudioNavigation.outputTracks(from:node.id,graph:$0)}} ?? []
                if selectedTrackID.map({tracks.contains($0)}) != true {selectedTrackID=tracks.count==1 ? tracks.first:nil}
            }
        }
    }
    func focusHierarchy(_ address: CircleAddress, detail: Bool = false) {
        selectHierarchy(address); hierarchyCommand = HierarchyCommand(action: .focus(address, detail))
    }
    func hierarchyParent() { hierarchyCommand = HierarchyCommand(action: .parent) }
    func updateMusic(_ label: String, _ edit: (inout MusicCircle) -> Void) {
        guard let node = selectedMusic, var graph = selectedGraph, let index = graph.nodes.firstIndex(where: { $0.id == node.id }) else { return }
        edit(&graph.nodes[index]); setGraph(label, graph)
    }
    func setGraph(_ label: String, _ graph: SectionGraph, musical: Bool = true) {
        guard let use = selectedUse else { return }; let original = editOriginal
        mutate(label, musical: musical) { try SectionGraphEditing.set(graph, useID: use.id, original: original, in: &$0) }
    }
    func moveHierarchy(_ address: CircleAddress, to point: Point) {
        mutate("서클 이동", musical: false) { try HierarchyEditing.move(address, to: point, in: &$0) }
    }
    func moveHierarchySelection(_ positions: [CircleAddress: Point], delta: Point) {
        mutate("서클 이동", musical: false) { project in
            for (address, point) in positions { try HierarchyEditing.move(address, to: Point(point.x+delta.x,point.y+delta.y), in: &project) }
        }
    }
    func hierarchyLocalPosition(_ node: CircleSceneNode) -> Point { (try? HierarchyEditing.position(node.id, in: project)) ?? Point() }
    func makeHierarchyGroup() {
        let addresses = hierarchySelections
        var address: CircleAddress?
        mutate("그룹 만들기", musical: false) { address = try HierarchyEditing.group(addresses, name: "그룹", in: &$0) }
        if let address { status = "원형 그룹 생성 · \(addresses.count)개 서클"; focusHierarchy(address) }
    }
    func alignHierarchy(_ mode: Int) {
        let addresses = hierarchySelections
        mutate("서클 정렬", musical: false) { try HierarchyEditing.align(addresses, mode: mode, in: &$0) }
    }
    func updateHierarchyGroup(_ edit: (inout CanvasGroup) -> Void) {
        guard case .group(let parent,let id) = hierarchySelection else { return }
        mutate("그룹 편집", musical: false) { project in
            try HierarchyEditing.editLayout(parent, in: &project) { layout in if let i=layout.groups.firstIndex(where:{$0.id==id}) { edit(&layout.groups[i]) } }
        }
    }
    func ungroupHierarchy() {
        guard case .group(let parent,let id) = hierarchySelection else { return }
        mutate("그룹 해제", musical: false) { project in try HierarchyEditing.editLayout(parent, in: &project) { $0.groups.removeAll { $0.id == id } } }
        hierarchySettingsOpen=false;focusHierarchy(parent)
    }
    var selectedHierarchyGroup: CanvasGroup? {
        guard case .group(let parent,let id) = hierarchySelection else { return nil }
        return (try? HierarchyEditing.layout(for: parent, in: project))?.groups.first { $0.id == id }
    }
    func connectHierarchy(_ from: CircleAddress, _ to: CircleAddress, sidechain: Bool = false) {
        switch (from, to) {
        case (.signal(let a), .signal(let b)): selectHierarchy(from); connect(a,b,sidechain:sidechain)
        case (.music(let a, let u, let n), .music(let b, let v, let m)) where a == b && u == v:
            selectHierarchy(from)
            guard var graph = selectedGraph else { return }
            do { try SectionGraphEditing.connect(from: n, to: m, sidechain: sidechain, in: &graph); setGraph("음악 서클 연결", graph) } catch { fail(error) }
        case (.section(let a, let u), .section(let b, let v)) where a == b:
            selectHierarchy(from); mutate("섹션 연결") { try ProjectEditing.connect(from: u, to: v, in: &$0) }
        case (.composition(let a), .composition(let b)):
            guard let album = project.album, album.parent(of: a) == album.parent(of: b) else { status = "같은 부모 안의 곡·악장을 연결하세요"; return }
            let parent = album.parent(of: a), ids = parent.flatMap { album.composition($0)?.children } ?? album.children
            let remaining = ids.filter { $0 != b }
            guard let index = remaining.firstIndex(of: a) else { return }
            mutate("곡·악장 순서 연결") { try AlbumEditing.move(b, to: parent, index: index+1, in: &$0) }
        default: status = "같은 그룹 안에서 호환되는 입력과 출력을 연결하세요"
        }
    }
    func addComposition(_ kind: CompositionKind, at point:Point? = nil) {
        var id: ID?
        let parent: ID? = kind == .movement ? selectedCompositionID : nil
        mutate(kind == .song ? "곡 만들기" : "악장 만들기") { p in
            if let parent, let composition = p.album?.composition(parent), !composition.arrangementIDs.isEmpty {
                _ = try AlbumEditing.wrapContents(of: parent, name: "악장 1", in: &p)
            }
            let children = parent.flatMap { p.album?.composition($0)?.children } ?? p.album?.children ?? []
            id = try AlbumEditing.add(name: "\(kind.label) \(children.count+1)", kind: kind, parentID: parent,
                                      at: point ?? Point(Double(children.count)*650, 0), in: &p)
        }
        if let id { focusHierarchy(.composition(id)) }
    }
    var selectedCompositionID: ID? {
        guard let selected = hierarchySelection else { return nil }
        return hierarchyScene?.path(to: selected).reversed().compactMap { n -> ID? in if case .composition(let id) = n.id { return id }; return nil }.first
    }
    func addMIDICircle(at point:Point? = nil) {
        guard let use = selectedUse else { status = "MIDI를 담을 섹션을 먼저 선택하세요"; return }
        var laneID: ID?
        let original = editOriginal
        mutate("MIDI 서클 만들기") { p in
            let track = p.addTrack(name: "악기 \(p.tracks.count+1)")
            let lane = Lane(trackID: track); laneID = lane.id
            try ProjectEditing.setLane(lane, for: use.id, original: original, in: &p)
            if let point { try HierarchyEditing.move(.music(arrangementID:p.activeArrangementID,useID:use.id,nodeID:"midi:\(lane.id)"),to:point,in:&p) }
        }
        if let laneID { focusHierarchy(.music(arrangementID: project.activeArrangementID, useID: use.id, nodeID: "midi:\(laneID)"), detail: true) }
    }
    func addMusicEffect(_ kind: EffectKind, at point:Point? = nil) {
        guard var graph = selectedGraph, let use = selectedUse else { return }
        let node = MusicCircle(name: Self.effectName(kind), content: .effect(Effect(kind, amount: kind == .gain ? 1 : 0.5, secondary: 0.3)))
        let source = selectedMusic?.content.output == .audio ? selectedMusic?.id : graph.nodes.first { if case .mix = $0.content { return true }; return false }?.id
        let position = source.flatMap { graph.layout.positions[$0] } ?? Point()
        graph.layout.positions[node.id] = point ?? Point(position.x+210, position.y+160)
        if let source {
            do { try SectionGraphEditing.insertEffect(node, from: source, in: &graph) }
            catch { fail(error); return }
        } else { graph.nodes.append(node) }
        setGraph("이펙터 서클 만들기", graph)
        if selectedGraph?.nodes.contains(where: { $0.id == node.id }) == true { focusHierarchy(.music(arrangementID: project.activeArrangementID, useID: use.id, nodeID: node.id), detail: true) }
    }
    func removeHierarchy() {
        guard let address = hierarchySelection else { return }
        switch address {
        case .music:
            guard let music = selectedMusic, var graph = selectedGraph else { return }
            SectionGraphEditing.remove([music.id], from: &graph); setGraph("음악 서클 삭제", graph)
        case .section, .signal: removeSelection()
        case .composition(let id):
            mutate("곡·악장 삭제") { p in
                guard var album = p.album else { return }
                let descendants = Set(try album.compositions.filter { try album.path(to: $0.id).contains(where: { $0.id == id }) }.map(\.id))
                let arrangements = Set(album.compositions.filter { descendants.contains($0.id) }.flatMap(\.arrangementIDs))
                album.children.removeAll { descendants.contains($0) }
                for i in album.compositions.indices { album.compositions[i].children.removeAll { descendants.contains($0) } }
                album.compositions.removeAll { descendants.contains($0.id) }
                p.arrangements.removeAll { arrangements.contains($0.id) }
                if arrangements.contains(p.activeArrangementID), let first = p.arrangements.first { p.activeArrangementID = first.id }
                try album.validate(arrangements: p.arrangements); p.album = album
            }
        case .album, .sound: return
        case .group: ungroupHierarchy(); return
        }
        hierarchyCommand = HierarchyCommand(action: .parent)
    }
    func renameHierarchy(_ name: String) {
        guard let address = hierarchySelection else { return }
        switch address {
        case .sound: break
        case .signal: updateSignal("사운드 서클 이름") { $0.name = name }
        case .album: mutate("앨범 이름") { $0.name = name }
        case .composition(let id): mutate("곡·악장 이름") { p in if let i = p.album?.compositions.firstIndex(where: { $0.id == id }) { p.album?.compositions[i].name = name } }
        case .section: updateUse("섹션 이름") { $0.name = name }
        case .music: updateMusic("음악 서클 이름") { $0.name = name }
        case .group: updateHierarchyGroup { $0.name = name }
        }
    }
    func updateHierarchySettings(_ settings: ContextSettings) {
        guard let address = hierarchySelection else { return }
        switch address {
        case .composition(let id): mutate("곡·악장 음악 설정") { p in if let i = p.album?.compositions.firstIndex(where: { $0.id == id }) { p.album?.compositions[i].settings = settings }; _ = try AlbumCompiler.compile(p) }
        case .section: updateUse("섹션 음악 설정") { $0.settings = settings }
        case .music: updateMusic("음악 서클 설정") { $0.settings = settings }
        case .album, .group, .sound, .signal: break
        }
    }
    var hierarchySettings: ContextSettings {
        switch hierarchySelection {
        case .composition(let id): return project.album?.composition(id)?.settings ?? ContextSettings()
        case .section: return selectedUse?.settings ?? ContextSettings()
        case .music: return selectedMusic?.settings ?? ContextSettings()
        default: return ContextSettings()
        }
    }
    func requestWaveform(_ asset: Asset) {
        guard waveforms[asset.id] == nil, !waveformLoading.contains(asset.id) else { return }
        let root = mediaRoot, generation = waveformGeneration
        waveformLoading.insert(asset.id)
        Task { [weak self] in
            do {
                let result = try await Task.detached(priority: .utility) {
                    let url = try ProjectStore.assetURL(asset, root: root)
                    return try WaveformOverview.read(url)
                }.value
                guard let self, generation == self.waveformGeneration else { return }
                self.waveforms[asset.id] = result; self.waveformLoading.remove(asset.id)
            } catch { guard let self, generation == self.waveformGeneration else { return }; self.status = "파형 읽기 실패: \(error.localizedDescription)" }
        }
    }
}

extension AppStore {
    func showMusicPluginEditor() {
        guard let address=hierarchySelection,case .effect(let effect)=selectedMusic?.content,let descriptor=effect.plugin else{return}
        Task {
            do {
                let unit=try await AudioUnitHost.instantiate(descriptor)
                guard let controller=await unit.auAudioUnit.requestViewController() else{status="이 Audio Unit은 편집 화면을 제공하지 않습니다";return}
                guard hierarchySelection==address,case .effect(let current)=selectedMusic?.content,current.plugin?.id==descriptor.id else{return}
                embeddedPlugin=PluginEditorController(plugin:controller,unit:unit,onApply:{[weak self] in
                    guard let self,self.hierarchySelection==address,case .effect(var effect)=self.selectedMusic?.content,effect.plugin?.id==descriptor.id else{return}
                    do{effect.plugin?.state=try AudioUnitHost.capture(unit);self.updateMusic("Audio Unit 설정"){$0.content = .effect(effect)}}catch{self.fail(error)}
                })
            }catch{if hierarchySelection==address{fail(error)}}
        }
    }
    func makeHierarchyPattern() {
        guard let use=selectedUse,let track=project.tracks.first(where:{$0.instrument.drums}) ?? selectedTrack else{return}
        var pattern=RhythmPattern(name:"리듬 \(project.patterns.count+1)",trackID:track.id)
        pattern.meter=currentContext.meter;pattern.length=currentContext.meter.quarters
        mutate("리듬 패턴 만들기"){p in
            p.patterns.append(pattern)
            if let i=p.arrangements[p.activeIndex].uses.firstIndex(where:{$0.id==use.id}){var assignment=RhythmAssignment();assignment.patternID=pattern.id;p.arrangements[p.activeIndex].uses[i].settings.rhythm = .local(assignment)}
        }
        hierarchySettingsOpen=false
        focusHierarchy(.music(arrangementID:project.activeArrangementID,useID:use.id,nodeID:"rhythm-midi:\(track.id)"),detail:true)
    }
}

extension AppStore {
    func disconnectHierarchy(_ address: CircleAddress, edgeID: ID? = nil) {
        selectHierarchy(address)
        switch address {
        case .signal(let node): mutate("사운드 연결 해제") { $0.signal.edges.removeAll { $0.from == node && (edgeID == nil || $0.id == edgeID) } }
        case .music(_,_,let node):
            guard var graph=selectedGraph else{return}
            graph.edges.removeAll { $0.from==node && (edgeID == nil || $0.id==edgeID) }
            setGraph("음악 연결 해제",graph)
        case .section(_,let use):
            mutate("섹션 연결 해제") { p in
                let i=p.activeIndex
                p.arrangements[i].edges.removeAll { $0.from==use && (edgeID == nil || $0.id==edgeID) }
                p.arrangements[i].chosenEdges=p.active.chosenEdges.filter { pair in p.active.edges.contains{$0.id==pair.value && $0.from==pair.key} }
                if !p.active.edges.contains(where:{$0.from==use}),let ui=p.arrangements[i].uses.firstIndex(where:{$0.id==use}) { p.arrangements[i].uses[ui].isEnd=true }
            }
        default: break
        }
    }
    func chooseHierarchyEdge(_ address: CircleAddress, edgeID: ID) {
        selectHierarchy(address)
        guard case .section(_,let use)=address else{return}
        mutate("재생할 분기 선택") { p in p.arrangements[p.activeIndex].chosenEdges[use]=edgeID; if let i=p.arrangements[p.activeIndex].uses.firstIndex(where:{$0.id==use}){p.arrangements[p.activeIndex].uses[i].isEnd=false} }
    }
    func openHierarchyTransition(_ address: CircleAddress, edgeID: ID) {
        focusHierarchy(address,detail:true); self.edgeSelection=edgeID; hierarchyTransitionID=edgeID; hierarchySettingsOpen=true
    }
}

extension AppStore {
    func addHierarchySignalEffect(_ kind: EffectKind, at point:Point? = nil) {
        addEffect(kind,at:point)
        if let id=selectedSignal?.id { focusHierarchy(.signal(id),detail:true) }
    }
    func addHierarchyBus(at point:Point? = nil) {
        addBus(at:point)
        if let id=selectedSignal?.id { focusHierarchy(.signal(id),detail:true) }
    }
}

extension AppStore {
    func captureViewport() {
        guard let viewport=captureHierarchyViewport?() else{return}
        updatingHierarchyViewport=true;project.hierarchyView=viewport;updatingHierarchyViewport=false
    }
    var recordingClock: MusicClock? {
        guard let parent=sectionClock,let music=selectedMusic else{return sectionClock}
        var context=currentContext
        var changes:[TempoChange]=[]
        let length=music.lengthBeats ?? parent.beats
        if music.settings.tempo.source == .inherit {
            context.tempo=parent.bpm(at:music.startBeat)
            changes=parent.tempos.filter{$0.beat>music.startBeat && $0.beat<music.startBeat+length}.map{TempoChange(beat:$0.beat-music.startBeat,bpm:$0.bpm)}
        }
        return try? MusicClock(beats:length,context:context,tempoChanges:changes)
    }
}

extension AppStore {
    func chooseHierarchyArrangement(_ id: ID) {
        guard let owner=project.album?.owner(of:id)?.id else{return}
        mutate("편곡안 선택") { try AlbumEditing.selectArrangement(id,in:&$0) }
        hierarchySettingsOpen=false;focusHierarchy(.composition(owner))
    }
    func duplicateHierarchyArrangement() {
        guard let owner=project.album?.owner(of:project.activeArrangementID)?.id else{return}
        duplicateArrangement();hierarchySettingsOpen=false;focusHierarchy(.composition(owner))
    }
}

extension AppStore {
    func normalizeHierarchySelection() {
        guard let address=hierarchySelection,hierarchyScene?.node(address)==nil else{return}
        let parent:CircleAddress
        switch address {
        case .music(let arrangement,let use,_):
            let section=CircleAddress.section(arrangementID:arrangement,useID:use)
            parent=hierarchyScene?.node(section) != nil ? section:(project.album?.owner(of:arrangement).map{.composition($0.id)} ?? .album)
        case .section(let arrangement,_): parent=project.album?.owner(of:arrangement).map{.composition($0.id)} ?? .album
        case .group(let scope,_): parent=hierarchyScene?.node(scope) != nil ? scope:.album
        case .signal: parent = .sound
        default: parent = .album
        }
        hierarchySettingsOpen=false;focusHierarchy(parent)
    }
}
