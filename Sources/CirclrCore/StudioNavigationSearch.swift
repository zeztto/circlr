import Foundation

public enum StudioNavigationRole:String,CaseIterable,Identifiable {
    case section,midi,audio,instrument,effect,router,mix,output
    public var id:Self {self}
    public var label:String {
        switch self {case .section:return "섹션";case .midi:return "MIDI";case .audio:return "오디오"
        case .instrument:return "음색";case .effect:return "이펙트";case .router:return "라우터"
        case .mix:return "믹스";case .output:return "출력"}
    }
    public init?(source:String) {
        switch source {case "MIDI":self = .midi;case "오디오":self = .audio;case "악기":self = .instrument
        case "이펙터":self = .effect;case "오디오 라우터":self = .router;case "믹스":self = .mix
        case "출력":self = .output;default:return nil}
    }
    var aliases:String {
        switch self {case .instrument:return "악기 음색";case .effect:return "이펙터 이펙트"
        case .router:return "오디오 라우터";default:return label}
    }
}

public struct StudioNavigationEntryID:Hashable {
    public var destination:CircleAddress
    public var trackID:ID?
}
public struct StudioNavigationEntry:Identifiable {
    public var target:CircleAddress
    public var sectionID:CircleAddress
    public var trackID:ID?
    public var title:String
    public var path:String
    public var role:StudioNavigationRole
    public var ordinal:Int
    public var count:Int
    public var connected:Bool
    var sectionNumber:Int
    var trackNumber:Int?
    var searchText:String
    public var id:StudioNavigationEntryID {.init(destination:target,trackID:trackID)}
    public var detail:String {
        role.label+(count>1 ? " \(ordinal)/\(count)":"")+" · "+path+(connected ? "":" · 미연결")
    }
}

/// Results are actual destinations, so searching an effect and pressing Return opens that effect.
public enum StudioNavigationSearch {
    public static func catalog(_ routes:[StudioSectionRoute],trackOrder:[ID])->[StudioNavigationEntry] {
        let numbers=Dictionary(trackOrder.enumerated().map{($0.element,$0.offset+1)},uniquingKeysWith:{first,_ in first})
        var result:[StudioNavigationEntry]=[]
        for (index,section) in routes.enumerated() {
            let sectionPath=section.path+" › \(index+1) · "+section.name
            let sectionText=sectionPath+" \(index+1)번 섹션"
            result.append(.init(target:section.id,sectionID:section.id,trackID:nil,title:section.name,path:sectionPath,
                                role:.section,ordinal:1,count:1,connected:true,sectionNumber:index+1,trackNumber:nil,searchText:folded(sectionText+" 섹션")))
            for track in section.tracks {
                let number=numbers[track.id].map{"\($0)"}
                let path=sectionPath+" › "+(number.map{$0+" · "} ?? "")+track.name
                var ordinals:[StudioNavigationRole:Int]=[:]
                let counts=Dictionary(grouping:track.destinations.compactMap{StudioNavigationRole(source:$0.role)},by:{$0}).mapValues(\.count)
                for destination in track.destinations {
                    guard let role=StudioNavigationRole(source:destination.role) else{continue}
                    ordinals[role,default:0]+=1
                    let text=sectionText+" "+track.name+" "+(number.map{$0+"번 트랙"} ?? "")+" "+destination.name+" "+role.aliases
                    result.append(.init(target:destination.id,sectionID:section.id,trackID:track.id,title:destination.name,path:path,
                                        role:role,ordinal:ordinals[role]!,count:counts[role]!,connected:destination.connected,
                                        sectionNumber:index+1,trackNumber:numbers[track.id],searchText:folded(text)))
                }
            }
        }
        return result
    }
    public static func search(_ entries:[StudioNavigationEntry],query:String,sectionID:CircleAddress?=nil,trackID:ID?=nil,role:StudioNavigationRole?=nil)->[StudioNavigationEntry] {
        let terms=folded(query).split(whereSeparator:{$0.isWhitespace})
        return entries.filter {entry in
            guard sectionID==nil || entry.sectionID==sectionID,trackID==nil || entry.trackID==trackID,role==nil || entry.role==role else{return false}
            let text=entry.searchText
            return terms.allSatisfy {term in
                if term.hasSuffix("번트랙"),let number=Int(term.dropLast(3)) {return entry.trackNumber==number}
                if term.hasSuffix("번섹션"),let number=Int(term.dropLast(3)) {return entry.sectionNumber==number}
                return text.contains(term)
            }
        }
    }
    private static func folded(_ text:String)->String {
        text.folding(options:[.caseInsensitive,.diacriticInsensitive,.widthInsensitive],locale:Locale(identifier:"en_US_POSIX"))
            .precomposedStringWithCanonicalMapping.replacingOccurrences(of:#"(\d+)\s*번\s*(트랙|섹션)"#,with:"$1번$2",options:.regularExpression)
    }
}
