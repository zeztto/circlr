import Foundation

public struct ConnectionTargetChoice:Equatable {
    public let endpoint:CirclePortEndpoint
    public let title:String
    public let detail:String
    public let ordinal:Int?
}

/// Presentation and filtering never create endpoints or alter group bindings.
public enum ConnectionTargetSearch {
    public static func choice(_ endpoint:CirclePortEndpoint,name:String,port:String,in project:Project)->ConnectionTargetChoice {
        guard case .section(let ai,let ui)=endpoint.node,
              let arrangement=project.arrangements.first(where:{$0.id==ai}),
              let index=arrangement.uses.firstIndex(where:{$0.id==ui}) else {
            return .init(endpoint:endpoint,title:name,detail:port,ordinal:nil)
        }
        let owner=project.album?.owner(of:ai)
        let path=owner.flatMap{try? project.album?.path(to:$0.id).map(\.name).joined(separator:" › ")} ?? ""
        let scope=[path,arrangement.name].filter{!$0.isEmpty}.joined(separator:" › ")
        return .init(endpoint:endpoint,title:"#\(index+1) · "+arrangement.uses[index].name,
                     detail:port+" · "+scope,ordinal:index+1)
    }
    public static func search(_ choices:[ConnectionTargetChoice],query:String)->[ConnectionTargetChoice] {
        let terms=fold(query).split(whereSeparator:{$0.isWhitespace})
        return choices.filter {choice in terms.allSatisfy {term in
            if term.hasPrefix("#") {guard let ordinal=choice.ordinal,let value=Int(term.dropFirst()) else{return false};return ordinal==value}
            return fold(choice.title+" "+choice.detail).contains(term)
        }}
    }
    private static func fold(_ value:String)->String {
        value.folding(options:[.caseInsensitive,.diacriticInsensitive,.widthInsensitive],locale:Locale(identifier:"en_US_POSIX")).precomposedStringWithCanonicalMapping
    }
}
