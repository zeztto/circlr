import XCTest
@testable import CirclrCore

final class HierarchyAutoLayoutTests:XCTestCase {
    private func fixture()throws->Project {
        var p=Project()
        _=p.addTrack(name:"피아노");_=p.addTrack(name:"패드")
        _=p.addSection(name:"첫 구간",at:Point(),bars:4)
        p.enableAlbum()
        return try SectionGraphMigration.migrate(p)
    }
    private func children(_ project:Project)throws->[CircleSceneNode] {
        let scene=try HierarchySceneBuilder.build(project)
        let section=try XCTUnwrap(scene.nodes.first{$0.role == .section})
        return scene.children(of:section.id)
    }
    private func assertSeparated(_ nodes:[CircleSceneNode],file:StaticString=#filePath,line:UInt=#line) {
        for (index,node) in nodes.enumerated() {
            for other in nodes.dropFirst(index+1) {
                XCTAssertGreaterThanOrEqual(hypot(node.center.x-other.center.x,node.center.y-other.center.y),node.outerRadius+other.outerRadius+99.99,file:file,line:line)
            }
        }
    }
    func testAllModesPreserveMusicAndHaveNoOverlap()throws {
        for mode in HierarchyAutoLayoutMode.allCases {
            var p=try fixture();let before=p,nodes=try children(p),addresses=Set(nodes.map(\.id))
            let plan=try ArrangementCompiler.compile(p)
            try HierarchyAutoLayout.apply(mode,addresses:addresses,in:&p)
            let after=try children(p)
            assertSeparated(after)
            XCTAssertEqual(p.musicRevision,before.musicRevision)
            XCTAssertEqual(p.tracks,before.tracks)
            XCTAssertEqual(p.patterns,before.patterns)
            XCTAssertEqual(p.active.edges,before.active.edges)
            XCTAssertEqual(try ArrangementCompiler.compile(p).duration,plan.duration)
            for node in nodes {
                let moved=try XCTUnwrap(after.first{$0.id==node.id})
                XCTAssertEqual(moved.music,node.music)
                XCTAssertEqual(moved.orbit,node.orbit)
                XCTAssertEqual(moved.parent,node.parent)
            }
        }
    }
    func testDeterministicAndIdempotentAcrossInputOrders()throws {
        for mode in HierarchyAutoLayoutMode.allCases {
            let p=try fixture(),ids=try children(p).map(\.id)
            var a=p,b=p
            try HierarchyAutoLayout.apply(mode,addresses:Set(ids),in:&a)
            try HierarchyAutoLayout.apply(mode,addresses:Set(ids.reversed()),in:&b)
            XCTAssertEqual(a,b)
            let first=try children(a)
            try HierarchyAutoLayout.apply(mode,addresses:Set(ids),in:&a)
            let second=try children(a)
            for node in first {
                let repeated=try XCTUnwrap(second.first{$0.id==node.id})
                XCTAssertEqual(repeated.center.x,node.center.x,accuracy:1e-7)
                XCTAssertEqual(repeated.center.y,node.center.y,accuracy:1e-7)
            }
        }
    }
    func testSubsetAvoidsUnmanagedSiblingsWithoutMovingThem()throws {
        for mode in HierarchyAutoLayoutMode.allCases {
            var p=try fixture();let before=try children(p)
            let selected=Set(before.prefix(2).map(\.id))
            try HierarchyAutoLayout.apply(mode,addresses:selected,in:&p)
            let after=try children(p)
            for node in before where !selected.contains(node.id) {
                XCTAssertEqual(after.first{$0.id==node.id}?.center,node.center)
            }
            for node in after where selected.contains(node.id) {
                for other in after where other.id != node.id {
                    XCTAssertGreaterThanOrEqual(hypot(node.center.x-other.center.x,node.center.y-other.center.y),node.outerRadius+other.outerRadius+99.99)
                }
            }
        }
    }
    func testInvalidSelectionIsAtomic()throws {
        var p=try fixture();let before=p,ids=try children(p).map(\.id)
        for selection:Set<CircleAddress> in [[],[ids[0]],[ids[0],.album],[ids[0],.composition("missing")]] {
            XCTAssertThrowsError(try HierarchyAutoLayout.apply(.horizontal,addresses:selection,in:&p))
            XCTAssertEqual(p,before)
        }
    }
    func testFreeformRemainsFreeformAndSeparatesWorldGeometry()throws {
        var p=try fixture();p.circleLayout = .freeform
        let ids=Set(try children(p).map(\.id))
        try HierarchyAutoLayout.apply(.vertical,addresses:ids,in:&p)
        XCTAssertFalse(p.usesOrbits)
        assertSeparated(try children(p))
    }
    func testGroupedMembersKeepMembershipAndTiming()throws {
        var p=try fixture();let selected=Set(try children(p).prefix(2).map(\.id))
        let group=try HierarchyEditing.group(selected,name:"묶음",in:&p)
        let scope=try HierarchyEditing.scope(of:group,in:p)
        let groups=try HierarchyEditing.layout(for:scope,in:p).groups
        try HierarchyAutoLayout.apply(.horizontal,addresses:selected,in:&p)
        XCTAssertEqual(try HierarchyEditing.layout(for:scope,in:p).groups,groups)
        let scene=try HierarchySceneBuilder.build(p,revealing:group)
        XCTAssertTrue(selected.allSatisfy{scene.node($0)?.parent==group})
        assertSeparated(scene.children(of:group))
    }
    func testRadialSequentialSectionsOccupyAllQuadrants()throws {
        var p=Project();_=p.addTrack(name:"피아노")
        var uses:[ID]=[]
        for index in 0..<7 {uses.append(p.addSection(name:"구간 \(index)",at:Point(),bars:4))}
        for i in p.arrangements[0].uses.indices {p.arrangements[0].uses[i].isEnd=i==6}
        p.arrangements[0].edges=zip(uses,uses.dropFirst()).map{FlowEdge(from:$0.0,to:$0.1)}
        p.enableAlbum();p=try SectionGraphMigration.migrate(p)
        let scene=try HierarchySceneBuilder.build(p),song=try XCTUnwrap(scene.nodes.first{$0.role == .song})
        let ids=Set(scene.children(of:song.id).map(\.id))
        try HierarchyAutoLayout.apply(.radial,addresses:ids,in:&p)
        let after=try HierarchySceneBuilder.build(p)
        let quadrants=Set(after.children(of:song.id).map{node in (node.center.x>=song.center.x ? 1:0)+(node.center.y>=song.center.y ? 2:0)})
        XCTAssertEqual(quadrants.count,4)
        assertSeparated(after.children(of:song.id))
    }
    func testActualDemoRadialHasCompactAspectAndReadableDiameter()throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var p=try JSONDecoder().decode(Project.self,from:Data(contentsOf:root.appendingPathComponent("Resources/Demos/f0r-h3r.circlr/manifest.json")))
        let scene=try HierarchySceneBuilder.build(p),section=try XCTUnwrap(scene.nodes.first{$0.role == .section})
        let ids=Set(scene.children(of:section.id).map(\.id))
        XCTAssertGreaterThan(ids.count,40)
        try HierarchyAutoLayout.apply(.radial,addresses:ids,in:&p)
        let after=try HierarchySceneBuilder.build(p),bounds=try XCTUnwrap(after.contextBounds(of:section.id))
        assertSeparated(after.children(of:section.id))
        XCTAssertGreaterThan(bounds.width/bounds.height,0.6)
        XCTAssertLessThan(bounds.width/bounds.height,1.7)
        let zoom=min(1340/bounds.width,800/bounds.height)
        let minimumDiameter=after.children(of:section.id).map{$0.radius*2*zoom}.min()!
        XCTAssertGreaterThan(minimumDiameter,18)
        print("actual demo auto radial: \(ids.count) nodes, bounds \(bounds.width)x\(bounds.height), minimum screen diameter \(minimumDiameter)")
    }

    func testLinearLanesKeepIndependentChainsStraightAndIgnoreSidechain() {
        let a=(0..<4).map{CircleAddress.signal("a-\($0)")}
        let b=(0..<4).map{CircleAddress.signal("b-\($0)")}
        let ordered=[a[0],b[0],b[1],a[1],a[2],b[2],b[3],a[3]]
        var edges:[CircleSceneEdge]=[]
        for chain in [a,b] {for i in 0..<3 {edges.append(CircleSceneEdge(id:"\(chain[i])",from:chain[i],to:chain[i+1],kind:.audio))}}
        let baseline=HierarchyAutoLayout.flowStructure(ordered:ordered,edges:edges)
        for chain in [a,b] {
            for i in 0..<4 {
                XCTAssertEqual(baseline.ranks[chain[i]],i)
                XCTAssertEqual(baseline.lanes[chain[i]],baseline.lanes[chain[0]])
            }
        }
        edges.append(CircleSceneEdge(id:"sidechain",from:b[3],to:a[1],kind:.sidechain))
        let sidechain=HierarchyAutoLayout.flowStructure(ordered:ordered,edges:edges)
        XCTAssertEqual(sidechain.ranks,baseline.ranks)
        XCTAssertEqual(sidechain.lanes,baseline.lanes)
    }
    func testLinearForkSeparatesAndMergeConvergesCycleTerminates() {
        let ids=(0..<5).map{CircleAddress.signal("node-\($0)")}
        let edges=[(0,1),(0,2),(1,3),(2,3),(3,4)].enumerated().map{index,pair in CircleSceneEdge(id:"\(index)",from:ids[pair.0],to:ids[pair.1],kind:.audio)}
        let flow=HierarchyAutoLayout.flowStructure(ordered:ids,edges:edges)
        XCTAssertGreaterThanOrEqual(abs(flow.lanes[ids[1]]!-flow.lanes[ids[2]]!),1)
        XCTAssertEqual(flow.lanes[ids[3]]!,(flow.lanes[ids[1]]!+flow.lanes[ids[2]]!)/2)
        XCTAssertEqual(flow.lanes[ids[4]],flow.lanes[ids[3]])
        let cycle=edges+[CircleSceneEdge(id:"cycle",from:ids[4],to:ids[0],kind:.audio)]
        let broken=HierarchyAutoLayout.flowStructure(ordered:ids,edges:cycle)
        XCTAssertEqual(broken.ranks.count,ids.count)
        XCTAssertEqual(broken.lanes.count,ids.count)
    }
    func testActualDemoLinearModesPreservePrimaryChainLanes()throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let project=try JSONDecoder().decode(Project.self,from:Data(contentsOf:root.appendingPathComponent("Resources/Demos/f0r-h3r.circlr/manifest.json")))
        let before=try HierarchySceneBuilder.build(project),section=try XCTUnwrap(before.nodes.first{$0.role == .section})
        let ids=Set(before.children(of:section.id).map(\.id))
        let edges=before.edges.filter{$0.kind != .sidechain && ids.contains($0.from) && ids.contains($0.to)}
        for mode in [HierarchyAutoLayoutMode.horizontal,.vertical] {
            var p=project
            try HierarchyAutoLayout.apply(mode,addresses:ids,in:&p)
            let scene=try HierarchySceneBuilder.build(p)
            assertSeparated(scene.children(of:section.id))
            var straightCount=0
            for edge in edges where edges.filter({$0.from==edge.from}).count==1 && edges.filter({$0.to==edge.to}).count==1 {
                let a=try XCTUnwrap(scene.node(edge.from)),b=try XCTUnwrap(scene.node(edge.to))
                let delta=mode == .horizontal ? abs(a.center.y-b.center.y):abs(a.center.x-b.center.x)
                if delta<0.01 {straightCount+=1}
            }
            XCTAssertGreaterThan(straightCount,20)
            print("actual demo \(mode.rawValue): \(straightCount) straight primary chain edges")
        }
    }

}
