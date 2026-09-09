import Foundation

/// Structural output paths, independent of mute, gain and current audio content.
/// One reverse topological pass indexes every output, keeping router buses separate.
public struct SectionGraphReachability {
    public let orderedNodes:[MusicCircle]
    private struct Paths {
        var main=Set<ID>()
        var sidechain=Set<ID>()
        mutating func include(_ other:Paths,throughSidechain:Bool=false) {
            if throughSidechain {sidechain.formUnion(other.main)}
            else {main.formUnion(other.main)}
            sidechain.formUnion(other.sidechain)
        }
    }
    private let nodePaths:[ID:Paths]
    private let tracksByOutput:[ID:ID]

    public init(graph:SectionGraph)throws {
        let ordered=try SectionGraphValidator.sorted(graph)
        let outgoing=Dictionary(grouping:graph.edges.map(MusicBusConnection.init),by:\.from)
        var inputs:[MusicBusEndpoint:Paths]=[:],nodes:[ID:Paths]=[:],tracks:[ID:ID]=[:]
        for node in ordered.reversed() {
            let ports=CirclePort.ports(for:node.content)
            var outputs:[String:Paths]=[:],combined=Paths()
            if case .output(let trackID)=node.content {
                // Output circles have only an input port, but are terminal destinations.
                combined.main.insert(node.id);tracks[node.id]=trackID
            }
            for port in ports where port.direction == .output {
                let endpoint=MusicBusEndpoint(nodeID:node.id,portID:port.id)
                var paths=Paths()
                for edge in outgoing[endpoint] ?? [] {
                    paths.include(inputs[edge.to] ?? Paths(),throughSidechain:edge.sidechain)
                }
                outputs[port.id]=paths;combined.include(paths)
            }
            nodes[node.id]=combined
            for port in ports where port.direction == .input {
                let paths:Paths
                if case .router(let router)=node.content {
                    var routed=Paths()
                    for route in router.routes where route.input == port.id {
                        routed.include(outputs[route.output] ?? Paths())
                    }
                    paths=routed
                }else{paths=combined}
                inputs[.init(nodeID:node.id,portID:port.id)]=paths
            }
        }
        orderedNodes=ordered;nodePaths=nodes;tracksByOutput=tracks
    }
    public func containsNode(_ id:ID)->Bool {nodePaths[id] != nil}
    public func outputTracks(from nodeID:ID)->Set<ID> {
        Set((nodePaths[nodeID]?.main ?? []).compactMap{tracksByOutput[$0]})
    }
    public func reachesMainOutput(_ outputNodeID:ID,from nodeID:ID)->Bool {
        nodePaths[nodeID]?.main.contains(outputNodeID) == true
    }
    public func reachesSidechainOutput(_ outputNodeID:ID,from nodeID:ID)->Bool {
        nodePaths[nodeID]?.sidechain.contains(outputNodeID) == true
    }
}
