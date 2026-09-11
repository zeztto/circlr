import Foundation

public enum CircleHistory {
    /// Visual history must not invalidate prepared playback or revert newer music.
    public static func restore(_ saved: Project, layoutOnly: Bool, current: Project, colorsOnly: Bool = false) throws -> Project {
        guard saved.id == current.id else { throw CirclrError("다른 프로젝트의 실행 취소 기록입니다") }
        if colorsOnly {
            // Colors have no playback or port-layout revision of their own.
            var result = current
            result.circleColors = saved.circleColors
            return result
        }
        if layoutOnly {
            var result = current
            _ = try CirclePortLayoutEditing.restore(saved.portLayout, projectID: current.id,
                expectedMusicRevision: current.musicRevision, expectedLayoutRevision: current.portLayout?.revision ?? 0, in: &result)
            return result
        }
        var result = saved; result.musicRevision = current.musicRevision + 1
        // Viewing preferences are saved with the document, independently of edit history.
        result.circleLayout = current.circleLayout
        result.hierarchyView = current.hierarchyView
        if let album = current.album, result.album?.id == album.id {
            result.album?.layout.grid = album.layout.grid
            result.album?.layout.snap = album.layout.snap
        }
        if saved.portLayout != current.portLayout {
            var layout = saved.portLayout ?? CirclePortLayout()
            layout.revision = (current.portLayout?.revision ?? 0) + 1
            try layout.validate(); result.portLayout = layout
        }
        return result
    }
}
