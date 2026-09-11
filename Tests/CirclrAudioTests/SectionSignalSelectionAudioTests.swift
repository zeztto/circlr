import XCTest
import CirclrCore
@testable import CirclrAudio

final class SectionSignalSelectionAudioTests:XCTestCase {
    func testIndependentRouterBusAndSidechainSelectedPCMMatchFullRender() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-selected-bus-"+newID())
        defer {try? FileManager.default.removeItem(at:root)}
        let helper=AudioRouterAudioTests(),fixture=try helper.fixture(root)
        var p=fixture.project
        func selected(_ project:Project)throws->(SectionSignalPlan,MusicClock) {
            let use=project.active.uses[0],(section,context,clock)=try ArrangementCompiler.context(project:project,use:use)
            let plan=try XCTUnwrap(SectionGraphCompiler.compile(project:project,section:section,use:use,context:context,clock:clock))
            return (try plan.selectingOutput(fixture.outputs[0]),clock)
        }
        let full=try await helper.render(p)
        let (plan,clock)=try selected(p)
        XCTAssertFalse(plan.orderedNodes.contains(where:{$0.id==fixture.sources[1]}))
        let partial=try await SectionGraphRenderer.render(plan,project:p,root:nil,clock:clock,tail:0)
        try helper.assertPCM(partial[p.tracks[0].id],full[p.tracks[0].id])
        XCTAssertNil(partial[p.tracks[1].id])
        var graph=try XCTUnwrap(p.sections[0].graph)
        let effect=MusicCircle(name:"duck",content:.effect(Effect(.compressor,amount:0.7,secondary:0.4)))
        graph.nodes.append(effect);graph.edges.removeAll{$0.to==fixture.outputs[0]}
        try SectionGraphEditing.connect(from:fixture.router,to:effect.id,fromPortID:AudioRouter.output1,in:&graph)
        try SectionGraphEditing.connect(from:fixture.router,to:effect.id,fromPortID:AudioRouter.output2,toPortID:CirclePort.sidechainInput,in:&graph)
        try SectionGraphEditing.connect(from:effect.id,to:fixture.outputs[0],in:&graph)
        p.sections[0].graph=graph
        let ducked=try await helper.render(p)
        let (sidechainPlan,sidechainClock)=try selected(p)
        XCTAssertTrue(sidechainPlan.orderedNodes.contains(where:{$0.id==fixture.sources[1]}))
        let sidechainPCM=try await SectionGraphRenderer.render(sidechainPlan,project:p,root:nil,clock:sidechainClock,tail:0)
        try helper.assertPCM(sidechainPCM[p.tracks[0].id],ducked[p.tracks[0].id])
        XCTAssertNotEqual(sidechainPCM[p.tracks[0].id]?.left,partial[p.tracks[0].id]?.left)
    }
}
