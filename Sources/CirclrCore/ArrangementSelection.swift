import Foundation

public struct ArrangementChoice:Identifiable,Equatable {
    public let id:ID
    public let ordinal:Int
    public let name:String
    public let sectionCount:Int
    public var title:String {"#\(ordinal) · "+name}
    public var detail:String {"\(sectionCount)개 섹션"}
}

public struct ArrangementDuplicateResult: Equatable {
    public let arrangementID: ID
    /// Exact addresses from the source model; absent addresses must not be guessed.
    public let addressMap: [CircleAddress: CircleAddress]
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
        try duplicateWithMapping(sourceID,compositionID:compositionID,name:name,in:&project).arrangementID
    }
    @discardableResult public static func duplicateWithMapping(_ sourceID:ID,compositionID:ID,name:String,in project:inout Project)throws->ArrangementDuplicateResult {
        guard try catalog(project,compositionID:compositionID).contains(where:{$0.id==sourceID}) else{throw CirclrError("같은 곡·악장의 편곡안을 복제하세요")}
        let name=try validatedName(name)
        var candidate=project;candidate.activeArrangementID=sourceID
        let source=candidate.active
        ProjectEditing.duplicateArrangement(in:&candidate,name:name)
        let id=candidate.activeArrangementID
        var addresses: [CircleAddress: CircleAddress] = [:]
        for (original, copied) in zip(source.uses, candidate.active.uses) {
            let from = CircleAddress.section(arrangementID:sourceID,useID:original.id)
            let to = CircleAddress.section(arrangementID:id,useID:copied.id)
            addresses[from] = to
            guard let section = project.sections.first(where:{$0.id == original.sectionID}) else {
                throw CirclrError("복제할 섹션 원본을 찾을 수 없습니다")
            }
            if let graph = try SectionGraphEditing.effective(section:section,use:original) {
                for node in graph.nodes {
                    addresses[.music(arrangementID:sourceID,useID:original.id,nodeID:node.id)] =
                        .music(arrangementID:id,useID:copied.id,nodeID:node.id)
                }
                // Group addresses use their layout's section scope, including grouped groups.
                for group in graph.layout.groups {
                    addresses[.group(parent:from,id:group.id)] = .group(parent:to,id:group.id)
                }
            }
        }
        for (original, copied) in zip(source.layout.groups, candidate.active.layout.groups) {
            addresses[.group(parent:.composition(compositionID),id:original.id)] =
                .group(parent:.composition(compositionID),id:copied.id)
        }
        for (address,color) in project.circleColors ?? [:] {
            if let copied = addresses[address] { candidate.circleColors?[copied] = color }
        }
        project = candidate
        return ArrangementDuplicateResult(arrangementID:id,addressMap:addresses)
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
