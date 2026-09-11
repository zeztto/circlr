import XCTest
@testable import CirclrCore

final class SectionSignalSelectionTests:XCTestCase {
    func testRouterEndpointSelectionKeepsMIDIAndSidechainWithoutOtherOutput() throws {
        let midi=MusicCircle(name:"MIDI",content:.midi(laneID:"lane"))
        let instrument=MusicCircle(name:"악기",content:.instrument(trackID:"a"))
        let side=MusicCircle(name:"키",content:.audio(laneID:"side",clipID:"clip"))
        let router=MusicCircle(name:"router",content:.router(AudioRouter()))
        let effect=MusicCircle(name:"duck",content:.effect(Effect(.compressor)))
        let a=MusicCircle(name:"A",content:.output(trackID:"a")),b=MusicCircle(name:"B",content:.output(trackID:"b"))
        var graph=SectionGraph();graph.nodes=[midi,instrument,side,router,effect,a,b]
        try SectionGraphEditing.connect(from:midi.id,to:instrument.id,in:&graph)
        try SectionGraphEditing.connect(from:instrument.id,to:router.id,toPortID:AudioRouter.input1,in:&graph)
        try SectionGraphEditing.connect(from:side.id,to:router.id,toPortID:AudioRouter.input2,in:&graph)
        try SectionGraphEditing.connect(from:router.id,to:effect.id,fromPortID:AudioRouter.output1,in:&graph)
        try SectionGraphEditing.connect(from:router.id,to:effect.id,fromPortID:AudioRouter.output2,toPortID:CirclePort.sidechainInput,in:&graph)
        try SectionGraphEditing.connect(from:effect.id,to:a.id,in:&graph)
        try SectionGraphEditing.connect(from:router.id,to:b.id,fromPortID:AudioRouter.output2,in:&graph)
        let plan=SectionSignalPlan(graph:graph,orderedNodes:try SectionGraphValidator.sorted(graph),contexts:[:],midi:[midi.id:[Note(beat:0,length:1,pitch:60,velocity:90)]],audio:[:],connections:graph.edges.map(MusicBusConnection.init))
        let selected=try plan.selectingOutput(a.id)
        XCTAssertEqual(Set(selected.orderedNodes.map(\.id)),Set(graph.nodes.map(\.id)).subtracting([b.id]))
        XCTAssertEqual(selected.midi[midi.id],plan.midi[midi.id])
        XCTAssertTrue(selected.connections.contains(where:{$0.sidechain}))
        XCTAssertEqual(selected.graph.edges.count,graph.edges.count-1)
        XCTAssertEqual(plan.graph,graph)
        let onlyB=try plan.selectingOutput(b.id)
        XCTAssertEqual(Set(onlyB.orderedNodes.map(\.id)),[side.id,router.id,b.id])
        XCTAssertTrue(onlyB.midi.isEmpty)
        XCTAssertEqual(onlyB.connections.count,2)
        XCTAssertThrowsError(try plan.selectingOutput("missing"))
        XCTAssertThrowsError(try plan.selectingOutput(router.id))
    }
}
