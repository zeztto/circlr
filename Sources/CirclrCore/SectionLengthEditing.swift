import Foundation

/// Changes a section use's length without changing its shared source or active arrangement.
public enum SectionLengthEditing {
    public struct Snapshot:Codable,Equatable {
        public let arrangementID:ID
        public let useID:ID
        public let sectionID:ID
        public let sourceBars:Int
        public let effectiveBars:Int
        public let barsOverride:Int?
    }
    public static func snapshot(arrangementID:ID,useID:ID,in project:Project)throws->Snapshot {
        guard let arrangement=project.arrangements.first(where:{$0.id==arrangementID}),
              let use=arrangement.uses.first(where:{$0.id==useID}) else{throw CirclrError("길이를 편집할 편곡안과 섹션 사용을 찾을 수 없습니다")}
        let (section,_,clock)=try ArrangementCompiler.context(project:project,use:use,arrangementID:arrangementID)
        return Snapshot(arrangementID:arrangementID,useID:useID,sectionID:section.id,sourceBars:section.bars,effectiveBars:clock.meters.count,barsOverride:use.barsOverride)
    }
    /// Nil explicitly restores inheritance. Validation failure leaves the complete project unchanged.
    @discardableResult public static func set(bars:Int?,arrangementID:ID,useID:ID,in project:inout Project)throws->Snapshot {
        if let bars {guard (1...4096).contains(bars) else{throw CirclrError("섹션 길이는 1–4096마디로 지정하세요")}}
        let before=try snapshot(arrangementID:arrangementID,useID:useID,in:project)
        guard before.barsOverride != bars else{return before}
        var candidate=project
        guard let ai=candidate.arrangements.firstIndex(where:{$0.id==arrangementID}),
              let ui=candidate.arrangements[ai].uses.firstIndex(where:{$0.id==useID}) else{throw CirclrError("길이를 편집할 섹션 사용이 변경되었습니다")}
        candidate.arrangements[ai].uses[ui].barsOverride=bars
        try ProjectStore.validateStructure(candidate)
        let result=try snapshot(arrangementID:arrangementID,useID:useID,in:candidate)
        project=candidate
        return result
    }
}
