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
            guard project.arrangements.filter({$0.id==id}).count==1,
                  project.album?.compositions.filter({$0.arrangementIDs.contains(id)}).count==1,
                  let arrangement=project.arrangements.first(where:{$0.id==id}),project.album?.owner(of:id)?.id==compositionID else{throw CirclrError("편곡안의 소유 곡·악장을 확인하세요")}
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
    private static func validatedName(_ name:String)throws->String {
        let value=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !value.isEmpty,value.count<=120 else{throw CirclrError("편곡안 이름은 1–120자로 입력하세요")}
        return value
    }
    @discardableResult public static func duplicate(_ sourceID:ID,compositionID:ID,name:String,in project:inout Project)throws->ID {
        guard try catalog(project,compositionID:compositionID).contains(where:{$0.id==sourceID}) else{throw CirclrError("같은 곡·악장의 편곡안을 복제하세요")}
        let name=try validatedName(name)
        var candidate=project;candidate.activeArrangementID=sourceID
        let source=candidate.active
        ProjectEditing.duplicateArrangement(in:&candidate,name:name)
        let id=candidate.activeArrangementID
        let uses=Dictionary(uniqueKeysWithValues:zip(source.uses,candidate.active.uses).map{($0.0.id,$0.1.id)})
        let groups=Dictionary(uniqueKeysWithValues:zip(source.layout.groups,candidate.active.layout.groups).map{($0.0.id,$0.1.id)})
        func remap(_ address:CircleAddress)->CircleAddress? {
            switch address {
            case .section(let arrangement,let use) where arrangement==sourceID:
                return uses[use].map{.section(arrangementID:id,useID:$0)}
            case .music(let arrangement,let use,let node) where arrangement==sourceID:
                return uses[use].map{.music(arrangementID:id,useID:$0,nodeID:node)}
            case .group(let parent,let group):
                if parent == .composition(compositionID),let copied=groups[group] {return .group(parent:parent,id:copied)}
                return remap(parent).map{.group(parent:$0,id:parent.creationContainer == .composition(compositionID) ? (groups[group] ?? group):group)}
            default:return nil
            }
        }
        for (address,color) in project.circleColors ?? [:] {
            if let copied=remap(address) {candidate.circleColors?[copied]=color}
        }
        project=candidate;return id
    }
    @discardableResult public static func rename(_ id:ID,compositionID:ID,name:String,in project:inout Project)throws->Bool {
        guard try catalog(project,compositionID:compositionID).contains(where:{$0.id==id}),
              let index=project.arrangements.firstIndex(where:{$0.id==id}) else{throw CirclrError("같은 곡·악장의 편곡안 이름을 변경하세요")}
        let name=try validatedName(name)
        guard project.arrangements[index].name != name else{return false}
        project.arrangements[index].name=name;return true
    }
    @discardableResult public static func select(_ id:ID,compositionID:ID,in project:inout Project)throws->Bool {
        guard try catalog(project,compositionID:compositionID).contains(where:{$0.id==id}) else{throw CirclrError("다른 곡·악장의 편곡안을 선택할 수 없습니다")}
        guard project.album?.composition(compositionID)?.selectedArrangementID != id else{return false}
        try AlbumEditing.selectArrangement(id,in:&project);return true
    }
}
