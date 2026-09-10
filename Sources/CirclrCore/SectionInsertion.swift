import Foundation

public enum SectionInsertionIssue:String,Equatable {
    case missingArrangement,missingSection,ambiguousBranch,loop,transition,invalidStructure
    public var message:String {
        switch self {
        case .missingArrangement:return "삽입할 편곡안을 다시 선택하세요"
        case .missingSection:return "새 섹션을 넣을 위치의 섹션을 선택하세요"
        case .ambiguousBranch:return "분기 또는 합류 연결을 먼저 정리한 뒤 섹션을 넣으세요"
        case .loop:return "순환 연결을 먼저 정리한 뒤 섹션을 넣으세요"
        case .transition:return "다음 연결의 전환을 먼저 정리한 뒤 섹션을 넣으세요"
        case .invalidStructure:return "섹션의 시작·끝과 연결을 확인한 뒤 다시 넣으세요"
        }
    }
}
public struct SectionInsertionAssessment:Equatable {
    public let issue:SectionInsertionIssue?
    public let successorID:ID?
    public var canInsert:Bool {issue == nil}
}

public enum SectionInsertion {
    public static func assess(arrangementID:ID,afterUseID:ID,in project:Project)->SectionInsertionAssessment {
        func fail(_ issue:SectionInsertionIssue)->SectionInsertionAssessment {.init(issue:issue,successorID:nil)}
        guard project.arrangements.filter({$0.id==arrangementID}).count==1,
              let arrangement=project.arrangements.first(where:{$0.id==arrangementID}) else{return fail(.missingArrangement)}
        guard arrangement.uses.filter({$0.id==afterUseID}).count==1,
              let source=arrangement.uses.first(where:{$0.id==afterUseID}),
              project.sections.filter({$0.id==source.sectionID}).count==1 else{return fail(.missingSection)}
        guard (1...3).contains(project.schemaVersion) else{return fail(.invalidStructure)}
        let ids=Set(arrangement.uses.map(\.id))
        guard ids.count==arrangement.uses.count,let start=arrangement.startID,ids.contains(start),
              Set(arrangement.edges.map(\.id)).count==arrangement.edges.count,
              arrangement.edges.allSatisfy({ids.contains($0.from) && ids.contains($0.to)}) else{return fail(.invalidStructure)}
        let outgoing=Dictionary(grouping:arrangement.edges,by:\.from)
        let incoming=Dictionary(grouping:arrangement.edges,by:\.to)
        // Inspect the connected component, including dormant edges behind an end marker.
        var component=Set<ID>(),pending=[afterUseID]
        while let id=pending.popLast() {
            guard component.insert(id).inserted else{continue}
            pending += (outgoing[id] ?? []).map(\.to)+(incoming[id] ?? []).map(\.from)
        }
        if component.contains(where:{(outgoing[$0]?.count ?? 0)>1 || (incoming[$0]?.count ?? 0)>1}) {return fail(.ambiguousBranch)}
        var seen=Set<ID>(),cursor:ID?=afterUseID
        while let id=cursor {
            guard seen.insert(id).inserted else{return fail(.loop)}
            cursor=outgoing[id]?.first?.to
        }
        guard component.contains(start) else{return fail(.invalidStructure)}
        for use in arrangement.uses where component.contains(use.id) {
            let edges=outgoing[use.id] ?? []
            guard use.isEnd == edges.isEmpty else{return fail(.invalidStructure)}
            if let chosen=arrangement.chosenEdges[use.id],!edges.contains(where:{$0.id==chosen}) {return fail(.invalidStructure)}
        }
        var path=Set<ID>(),current:ID?=start
        while let id=current,path.insert(id).inserted {current=outgoing[id]?.first?.to}
        guard path.contains(afterUseID) else{return fail(.invalidStructure)}
        let next=outgoing[afterUseID]?.first
        guard next?.transition == nil || next?.transition == Transition() else{return fail(.transition)}
        return .init(issue:nil,successorID:next?.to)
    }

    @discardableResult public static func insert(arrangementID:ID,afterUseID:ID,name:String,bars:Int,at:Point,in project:inout Project)throws->ID {
        let name=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty,name.count<=120 else{throw CirclrError("섹션 이름은 1–120자로 입력하세요")}
        guard (1...4096).contains(bars) else{throw CirclrError("섹션 길이는 1–4096마디로 입력하세요")}
        guard at.x.isFinite,at.y.isFinite,abs(at.x)<1e7,abs(at.y)<1e7 else{throw CirclrError("새 섹션의 Canvas 좌표를 확인하세요")}
        let assessment=assess(arrangementID:arrangementID,afterUseID:afterUseID,in:project)
        if let issue=assessment.issue {throw CirclrError(issue.message)}
        guard let ai=project.arrangements.firstIndex(where:{$0.id==arrangementID}),
              let ui=project.arrangements[ai].uses.firstIndex(where:{$0.id==afterUseID}) else{throw CirclrError("삽입 위치가 변경되었습니다")}
        var candidate=project
        var section=Section(name:name,bars:bars)
        section.lanes=project.tracks.map{Lane(trackID:$0.id)}
        section.graph=SectionGraphMigration.graph(lanes:section.lanes,tracks:project.tracks,effects:[])
        candidate.schemaVersion=max(2,candidate.schemaVersion)
        candidate.sections.append(section)
        var use=SectionUse(sectionID:section.id,name:name)
        use.isEnd=assessment.successorID == nil
        candidate.arrangements[ai].uses.insert(use,at:ui+1)
        candidate.arrangements[ai].uses[ui].isEnd=false
        candidate.arrangements[ai].layout.positions[use.id]=at
        if let successor=assessment.successorID,
           let edgeIndex=candidate.arrangements[ai].edges.firstIndex(where:{$0.from==afterUseID && $0.to==successor}) {
            // Keep the source edge ID and any explicit chosen-edge reference stable.
            candidate.arrangements[ai].edges[edgeIndex].to=use.id
            candidate.arrangements[ai].edges.append(FlowEdge(from:use.id,to:successor))
        }else{candidate.arrangements[ai].edges.append(FlowEdge(from:afterUseID,to:use.id))}
        try ProjectStore.validateStructure(candidate)
        _ = try ArrangementCompiler.compile(candidate,arrangementID:arrangementID)
        project=candidate
        return use.id
    }
}
