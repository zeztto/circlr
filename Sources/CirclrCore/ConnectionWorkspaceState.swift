import Foundation

/// UI intentions, validated again before reuse. Only the selected workspace is saved with the view.
public struct ConnectionWorkspaceState:Codable,Equatable {
    public var ownPortID=""
    public var target:CirclePortEndpoint?
    public var firstOctant=PortOctant.east
    public var secondOctant=PortOctant.west
    public var replacing:CircleConnectionID?
    public var replacementSource:CirclePortEndpoint?
    public var replacementDestination:CirclePortEndpoint?
    public var query=""
    public var currentPortOnly=false
    public var managingGroupPorts=false
    public init() {}

    /// Resolve remembered intentions against current visible endpoints and exact cable identities.
    public func restored(ports:[CirclePort],targets:[ConnectionTargetChoice],connections:[CirclePortConnection])->Self {
        var next=self
        guard ports.contains(where:{$0.id==ownPortID}) else {
            let port=ports.first{$0.direction == .output} ?? ports.first
            next.ownPortID=port?.id ?? "";next.firstOctant=port?.defaultOctant ?? .east
            next.secondOctant=port?.direction == .input ? .east:.west
            next.target=nil;next.replacing=nil;next.replacementSource=nil;next.replacementDestination=nil;return next
        }
        if let replacing,!connections.contains(where:{$0.id==replacing && $0.from==replacementSource && $0.to==replacementDestination}) {
            next.replacing=nil;next.target=nil;next.replacementSource=nil;next.replacementDestination=nil
        }
        if let target,!ConnectionTargetSearch.search(targets,query:query).contains(where:{$0.endpoint==target}) {next.target=nil}
        return next
    }
}
