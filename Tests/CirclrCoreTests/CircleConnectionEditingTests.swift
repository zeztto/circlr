import XCTest
@testable import CirclrCore

final class CircleConnectionEditingTests: XCTestCase {
    func fixture() throws -> Project {
        var p = Project(); _ = p.addTrack(name: "신스"); _ = p.addSection(name: "첫 섹션", at: Point(), bars: 1)
        _ = p.addSection(name: "둘째 섹션", at: Point(300,0), bars: 1)
        p.enableAlbum(); p = try SectionGraphMigration.migrate(p)
        for i in p.sections.indices { p.sections[i].graph!.nodes.append(MusicCircle(name:"라우터",content:.router(AudioRouter()))) }
        return p
    }
    func endpoint(_ p: Project, use: Int = 0, node: ID, port: String) -> CirclePortEndpoint {
        .init(node:.music(arrangementID:p.active.id,useID:p.active.uses[use].id,nodeID:node),portID:port)
    }
    func nodes(_ p: Project, use: Int = 0) throws -> [MusicCircle] {
        try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[use],use:p.active.uses[use])).nodes
    }
    func testReverseInputConnectionAndDuplicatePreserveIdentityAndPlacement() throws {
        var p = try fixture(); let ns = try nodes(p)
        let source = ns.first { if case .instrument = $0.content { return true }; return false }!
        let router = ns.first { if case .router = $0.content { return true }; return false }!
        let a = endpoint(p,node:source.id,port:CirclePort.audioOutput), b = endpoint(p,node:router.id,port:AudioRouter.input2)
        let id = try CircleConnectionEditing.connect(b,a,firstOctant:.north,secondOctant:.southwest,in:&p)
        XCTAssertEqual(id.from,a.node); XCTAssertEqual(id.to,b.node)
        XCTAssertEqual(p.portLayout?.placement(for:id),.init(from:.southwest,to:.north))
        let after = p
        XCTAssertEqual(try CircleConnectionEditing.connect(a,b,firstOctant:.east,secondOctant:.west,in:&p),id)
        XCTAssertEqual(p,after)
    }
    func testReconnectPreservesGainIDAndOtherBusAndRejectsCycleAtomically() throws {
        var p = try fixture(); let ns = try nodes(p)
        let router = ns.first { if case .router = $0.content { return true }; return false }!
        let output = ns.first { if case .output = $0.content { return true }; return false }!
        let instrument = ns.first { if case .instrument = $0.content { return true }; return false }!
        let a = endpoint(p,node:router.id,port:AudioRouter.output1), b = endpoint(p,node:output.id,port:CirclePort.audioInput)
        let id = try CircleConnectionEditing.connect(a,b,firstOctant:.north,secondOctant:.south,in:&p)
        var g = try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]))
        g.edges[g.edges.firstIndex { $0.id == id.edgeID }!].gain = 0.35
        let mix = ns.first { if case .mix = $0.content { return true }; return false }!
        try SectionGraphEditing.connect(from:router.id,to:mix.id,fromPortID:AudioRouter.output2,in:&g)
        let otherBus = g.edges.last!
        try SectionGraphEditing.set(g,useID:p.active.uses[0].id,original:false,in:&p)
        let alternate = endpoint(p,node:router.id,port:AudioRouter.output2)
        let sameID = try CircleConnectionEditing.connect(alternate,b,firstOctant:.northwest,secondOctant:.northeast,replacing:id,in:&p)
        let edge = try XCTUnwrap(CirclePortCatalog.connections(in:p).first { $0.id == sameID })
        XCTAssertEqual(sameID.edgeID,id.edgeID); XCTAssertEqual(edge.gain,0.35); XCTAssertEqual(edge.from.portID,AudioRouter.output2)
        XCTAssertTrue(try SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0])!.edges.contains(otherBus))
        let before = p
        let bad = endpoint(p,node:router.id,port:AudioRouter.input1)
        XCTAssertThrowsError(try CircleConnectionEditing.connect(alternate,bad,firstOctant:.north,secondOctant:.north,replacing:sameID,in:&p))
        XCTAssertEqual(p,before)
        let from = endpoint(p,node:instrument.id,port:CirclePort.audioOutput)
        let next = try CircleConnectionEditing.connect(from,b,firstOctant:.west,secondOctant:.east,replacing:sameID,in:&p)
        XCTAssertEqual(next.edgeID,id.edgeID); XCTAssertNotEqual(next.from,id.from)
        XCTAssertEqual(p.portLayout?.placement(for:next),.init(from:.west,to:.east))
        XCTAssertTrue(try CirclePortCatalog.connections(in:p).contains { $0.id == next && $0.gain == 0.35 })
    }
    func testMissingOrCrossUseReplacementIsAtomicAndSelectionDoesNotMove() throws {
        var p = try fixture(); let n = try nodes(p), other = try nodes(p,use:1)
        let source = n.first { if case .instrument = $0.content { return true }; return false }!
        let router = n.first { if case .router = $0.content { return true }; return false }!
        let a = endpoint(p,node:source.id,port:CirclePort.audioOutput), b = endpoint(p,node:router.id,port:AudioRouter.input1)
        let id = try CircleConnectionEditing.connect(a,b,firstOctant:.east,secondOctant:.west,in:&p)
        let otherSource = other.first { if case .instrument = $0.content { return true }; return false }!
        let otherRouter = other.first { if case .router = $0.content { return true }; return false }!
        let c = endpoint(p,use:1,node:otherSource.id,port:CirclePort.audioOutput), d = endpoint(p,use:1,node:otherRouter.id,port:AudioRouter.input1)
        let before = p
        XCTAssertThrowsError(try CircleConnectionEditing.connect(c,d,firstOctant:.north,secondOctant:.south,replacing:id,in:&p))
        XCTAssertEqual(p,before)
        let missing = CircleConnectionID(edgeID:"missing",from:a.node,to:b.node)
        XCTAssertThrowsError(try CircleConnectionEditing.connect(c,d,firstOctant:.north,secondOctant:.south,replacing:missing,in:&p)); XCTAssertEqual(p,before)
        try CircleConnectionEditing.disconnect(id,in:&p)
        XCTAssertEqual(p.activeArrangementID,before.activeArrangementID)
        XCTAssertFalse(try CirclePortCatalog.connections(in:p).contains { $0.id == id })
        let disconnected = p; XCTAssertThrowsError(try CircleConnectionEditing.disconnect(id,in:&p)); XCTAssertEqual(p,disconnected)
    }
    func testLayoutHistoryKeepsMusicAndMixedHistoryNeverRewindsLayoutRevision() throws {
        var p = try fixture(); let original = p
        let edge = try XCTUnwrap(CirclePortCatalog.connections(in:p).first)
        try CirclePortLayoutEditing.apply([.init(id:edge.id,placement:.init(from:.north,to:.south))],projectID:p.id,expectedMusicRevision:p.musicRevision,expectedLayoutRevision:0,in:&p)
        let moved = p
        p.musicRevision += 1; p.sections[0].lanes[0].notes.append(Note(beat:0,pitch:60))
        let undo = try CircleHistory.restore(original,layoutOnly:true,current:p)
        XCTAssertEqual(undo.sections,p.sections); XCTAssertEqual(undo.musicRevision,p.musicRevision); XCTAssertEqual(undo.portLayout?.revision,2)
        let redo = try CircleHistory.restore(moved,layoutOnly:true,current:undo)
        XCTAssertEqual(redo.sections,p.sections); XCTAssertEqual(redo.musicRevision,p.musicRevision); XCTAssertEqual(redo.portLayout?.revision,3)
        let musicalUndo = try CircleHistory.restore(original,layoutOnly:false,current:redo)
        XCTAssertEqual(musicalUndo.sections,original.sections); XCTAssertEqual(musicalUndo.musicRevision,redo.musicRevision+1); XCTAssertEqual(musicalUndo.portLayout?.revision,4)
        var other = original; other.id = newID()
        XCTAssertThrowsError(try CircleHistory.restore(other,layoutOnly:true,current:p))
    }
    func testSectionReconnectPreservesTransitionAndUnrelatedChosenBranch() throws {
        var p = try fixture(); let a = p.active.uses[0].id, b = p.active.uses[1].id
        let c = p.addSection(name:"셋째",at:Point(),bars:1), d = p.addSection(name:"넷째",at:Point(),bars:1)
        p = try SectionGraphMigration.migrate(p)
        func ep(_ id: ID, _ port: String) -> CirclePortEndpoint { .init(node:.section(arrangementID:p.active.id,useID:id),portID:port) }
        let id = try CircleConnectionEditing.connect(ep(a,CirclePort.flowOutput),ep(b,CirclePort.flowInput),firstOctant:.north,secondOctant:.south,in:&p)
        let edgeIndex = p.active.edges.firstIndex { $0.id == id.edgeID }!
        p.arrangements[p.activeIndex].edges[edgeIndex].transition.length = 0.25
        p.arrangements[p.activeIndex].edges[edgeIndex].transition.effect = Effect(.lowpass,amount:0.4)
        let transition = p.active.edges[edgeIndex].transition
        try ProjectEditing.connect(from:c,to:d,in:&p)
        let chosen = p.active.edges.first { $0.from == c && $0.to == d }!.id
        p.arrangements[p.activeIndex].chosenEdges[a] = id.edgeID; p.arrangements[p.activeIndex].chosenEdges[c] = chosen
        let out = try CircleConnectionEditing.connect(ep(c,CirclePort.flowOutput),ep(b,CirclePort.flowInput),firstOctant:.west,secondOctant:.east,replacing:id,in:&p)
        XCTAssertEqual(out.edgeID,id.edgeID); XCTAssertEqual(p.active.chosenEdges[c],chosen); XCTAssertNil(p.active.chosenEdges[a])
        XCTAssertEqual(p.active.edges.first { $0.id == out.edgeID }!.transition,transition)
        XCTAssertTrue(p.active.uses.first { $0.id == a }!.isEnd)
        let before = p
        XCTAssertThrowsError(try CircleConnectionEditing.connect(ep(b,CirclePort.flowOutput),ep(c,CirclePort.flowInput),firstOctant:.north,secondOctant:.south,in:&p))
        XCTAssertEqual(p,before)
    }
    func testGlobalSignalInputStartSidechainAndDisconnect() throws {
        var p = try fixture()
        let source = p.signal.nodes.first { $0.kind == .source }!
        var compressor = SignalNode(kind:.effect,name:"컴프레서"); compressor.effect = Effect(.compressor)
        p.signal.nodes.append(compressor)
        let a = CirclePortEndpoint(node:.signal(source.id),portID:CirclePort.audioOutput)
        let b = CirclePortEndpoint(node:.signal(compressor.id),portID:CirclePort.sidechainInput)
        let id = try CircleConnectionEditing.connect(b,a,firstOctant:.southwest,secondOctant:.northeast,in:&p)
        XCTAssertTrue(p.signal.edges.first { $0.id == id.edgeID }!.sidechain)
        let before = p.signal.edges.filter { $0.id != id.edgeID }
        try CircleConnectionEditing.disconnect(id,in:&p); XCTAssertEqual(p.signal.edges,before)
    }
}
