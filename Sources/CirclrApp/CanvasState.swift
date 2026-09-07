import SwiftUI
import CirclrCore

enum CanvasFocus: Equatable {
    case section(ID), signal(ID), edge(ID), global, pattern(ID), track(ID), group(ID)
    var nodeID: ID? { switch self { case .section(let id), .signal(let id):return id; default:return nil } }
}
struct CanvasCommand: Equatable {
    enum Action { case fit, zoomIn, zoomOut }
    let id = UUID()
    let action: Action
}
@MainActor final class TransportMeter: ObservableObject {
    @Published private(set) var seconds = 0.0
    @Published private(set) var playing = false
    func update(seconds:Double,playing:Bool) {
        if self.seconds != seconds { self.seconds = seconds }
        if self.playing != playing { self.playing = playing }
    }
}
extension AppStore {
    func openCircle(_ id:ID) {
        select(id); embeddedPlugin = nil
        requestEditor(soundView ? .signal(id):.section(id))
    }
    func requestEditor(_ target:CanvasFocus) {focus=target;editorActivation=UUID()}
    func selectNodes(_ ids:Set<ID>) {
        selection=ids;edgeSelection=nil;selectedNoteID=nil;selectedClipID=nil;selectedBeat=0;editPatternID=nil
        if focus != nil {
            embeddedPlugin=nil
            if ids.count==1,let id=ids.first {focus=soundView ? .signal(id):.section(id)}
            else {closeFocus()}
        }
    }
    func focusExists(_ value:CanvasFocus)->Bool {
        switch value {
        case .section(let id):return project.active.uses.contains{$0.id==id}
        case .signal(let id):return project.signal.nodes.contains{$0.id==id}
        case .edge(let id):return soundView ? project.signal.edges.contains{$0.id==id}:project.active.edges.contains{$0.id==id}
        case .pattern(let id):return project.patterns.contains{$0.id==id}
        case .track(let id):return project.tracks.contains{$0.id==id}
        case .group(let id):return layout.groups.contains{$0.id==id}
        case .global:return true
        }
    }
    func focusTitle(_ value:CanvasFocus)->String {
        switch value {
        case .section(let id):return project.active.uses.first{$0.id==id}?.name ?? "서클"
        case .signal(let id):return project.signal.nodes.first{$0.id==id}?.name ?? "사운드"
        case .edge:return "섹션 사이 전환"
        case .pattern(let id):return project.patterns.first{$0.id==id}?.name ?? "리듬 패턴"
        case .track(let id):return project.tracks.first{$0.id==id}?.name ?? "트랙"
        case .group(let id):return layout.groups.first{$0.id==id}?.name ?? "그룹"
        case .global:return "곡의 기본 설정"
        }
    }
    func openPattern(_ id:ID) {
        guard let pattern = project.patterns.first(where:{$0.id == id}) else { return }
        editPatternID = id; selectedTrackID = pattern.trackID; selectedNoteID = nil; selectedClipID = nil; selectedBeat = 0; embeddedPlugin = nil; requestEditor(.pattern(id))
    }
    func openTrack(_ id:ID) { editPatternID=nil; selectedNoteID=nil;selectedClipID=nil; selectedTrackID = id; embeddedPlugin = nil; requestEditor(.track(id)) }
    func openEdge(_ id:ID) { editPatternID=nil; selectedNoteID=nil;selectedClipID=nil; edgeSelection = id; selection = []; embeddedPlugin = nil; requestEditor(.edge(id)) }
    func closeFocus() { cancelAudition(); embeddedPlugin = nil; focus = nil; editPatternID = nil; selectedNoteID = nil; selectedClipID = nil }
    func switchGraph(_ sound:Bool) { closeFocus(); soundView = sound; selection = []; edgeSelection = nil }
    func editViewport(_ change:(inout CirclrCore.Layout)->Void) {
        var candidate = layout; change(&candidate)
        guard candidate != layout else { return }
        if soundView { project.signal.layout = candidate } else { project.arrangements[project.activeIndex].layout = candidate }
        dirty = true; scheduleViewportRecovery()
    }
    func fitCanvas() { canvasCommand = CanvasCommand(action:.fit) }
}
