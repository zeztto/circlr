import Foundation

public struct ArrangementChoice:Identifiable,Equatable {
    public let id:ID
    public let ordinal:Int
    public let name:String
    public let sectionCount:Int
    public var title:String {"#\(ordinal) · "+name}
    public var detail:String {"\(sectionCount)개 섹션"}
}

public enum ArrangementSelection {
    public static func catalog(_ project:Project,compositionID:ID)throws->[ArrangementChoice] {
        guard let owner=project.album?.composition(compositionID),!owner.arrangementIDs.isEmpty,
              Set(owner.arrangementIDs).count==owner.arrangementIDs.count else{throw CirclrError("편곡안을 소유한 곡·악장을 선택하세요")}
        return try owner.arrangementIDs.enumerated().map {index,id in
            guard let arrangement=project.arrangements.first(where:{$0.id==id}),project.album?.owner(of:id)?.id==compositionID else{throw CirclrError("편곡안의 소유 곡·악장을 확인하세요")}
            return ArrangementChoice(id:id,ordinal:index+1,name:arrangement.name,sectionCount:arrangement.uses.count)
        }
    }
    public static func search(_ choices:[ArrangementChoice],query:String)->[ArrangementChoice] {
        let terms=fold(query).split(whereSeparator:{$0.isWhitespace})
        return choices.filter {choice in
            terms.allSatisfy {term in
                if term.hasPrefix("#") {return Int(term.dropFirst())==choice.ordinal}
                return fold(choice.name+" "+choice.detail).contains(term)
            }
        }
    }
    private static func fold(_ value:String)->String {value.folding(options:[.caseInsensitive,.diacriticInsensitive,.widthInsensitive],locale:Locale(identifier:"en_US_POSIX")).precomposedStringWithCanonicalMapping}
    @discardableResult public static func select(_ id:ID,compositionID:ID,in project:inout Project)throws->Bool {
        guard try catalog(project,compositionID:compositionID).contains(where:{$0.id==id}) else{throw CirclrError("다른 곡·악장의 편곡안을 선택할 수 없습니다")}
        guard project.album?.composition(compositionID)?.selectedArrangementID != id else{return false}
        try AlbumEditing.selectArrangement(id,in:&project);return true
    }
}
