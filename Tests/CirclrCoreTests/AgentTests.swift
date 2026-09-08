import XCTest
@testable import CirclrCore

final class AgentTests:XCTestCase {
    func project()throws->Project{var p=Project();_=p.addTrack(name:"신스");_=p.addSection(name:"후렴",at:Point(),bars:2);p.enableAlbum();return try SectionGraphMigration.migrate(p)}
    func request(_ p:Project,_ operations:[AgentOperation])->AgentRequest{var r=AgentRequest(method:"apply");r.projectID=p.id;r.expectedRevision=p.musicRevision;var a=AgentArguments();a.operations=operations;r.arguments=a;return r}
    func testStaleWritesAndInvalidBatchDoNotChangeProject()throws{
        let p=try project();var rename=AgentOperation("rename_project");rename.name="변경"
        var stale=request(p,[rename]);stale.expectedRevision=12
        XCTAssertThrowsError(try AgentProjectEditing.apply(stale,to:p))
        var bad=AgentOperation("set_node");bad.nodeID="missing";bad.useID=p.active.uses[0].id;bad.startBeat=2
        XCTAssertThrowsError(try AgentProjectEditing.apply(request(p,[rename,bad]),to:p));XCTAssertEqual(p.name,"새 곡")
    }
    func testGeneratedMIDIAndEffectShareAtomicEditor()throws{
        let p=try project();var op=AgentOperation("generate_midi");op.useID=p.active.uses[0].id;op.laneID=p.sections[0].lanes[0].id;op.pattern = .arpeggio
        var synth=AgentOperation("set_instrument");synth.trackID=p.tracks[0].id;synth.synthVoice = .pluck
        var effect=AgentOperation("add_effect");effect.useID=op.useID;effect.from="instrument:\(p.tracks[0].id)";effect.effect=Effect(.delay,amount:0.3,secondary:0.25)
        let result=try AgentProjectEditing.apply(request(p,[op,synth,effect]),to:p)
        let lanes=try ArrangementCompiler.effectiveLanes(section:result.sections[0],use:result.active.uses[0])
        XCTAssertEqual(lanes[0].notes.count,16);XCTAssertEqual(result.tracks[0].instrument.synth?.voice,.pluck)
        let graph=try XCTUnwrap(SectionGraphEditing.effective(section:result.sections[0],use:result.active.uses[0]))
        XCTAssertTrue(graph.nodes.contains{if case .effect = $0.content{return true};return false})
        XCTAssertTrue(p.sections[0].lanes[0].notes.isEmpty)
    }
    func testAgentNoteInputAcceptsMissingIDsButRequiresMusicalFields()throws{
        let data=Data(#"{"id":"req","method":"apply","arguments":{"operations":[{"kind":"set_notes","notes":[{"beat":0,"length":1,"pitch":66,"velocity":90}]}]}}"#.utf8)
        let r=try JSONDecoder().decode(AgentRequest.self,from:data);XCTAssertFalse(r.arguments!.operations![0].notes![0].id.isEmpty)
        XCTAssertThrowsError(try JSONDecoder().decode(Note.self,from:Data(#"{"beat":0,"pitch":66}"#.utf8)))
        let p=try project();var op=AgentOperation("generate_midi");op.useID=p.active.uses[0].id;op.laneID=p.sections[0].lanes[0].id
        XCTAssertThrowsError(try AgentProjectEditing.apply(request(p,[op]),to:p))
    }
    func testClipTrimAndSectionReorderShareAtomicCommands() throws {
        var p=try project();let ai=p.activeArrangementID,first=p.active.uses[0].id
        let second=p.addSection(name:"뒤",at:Point(),bars:1)
        try ProjectEditing.connect(from:first,to:second,in:&p)
        let asset=Asset(name:"녹음",path:"media/take.wav",duration:5,sampleRate:48000)
        p.assets.append(asset)
        let clip=AudioClip(assetID:asset.id,duration:4)
        p.sections[0].lanes[0].audio=[clip];p=try SectionGraphMigration.migrate(p)
        var trim=AgentOperation("set_clip");trim.useID=first;trim.laneID=p.sections[0].lanes[0].id;trim.clipID=clip.id;trim.sourceStart=1;trim.duration=2
        var reorder=AgentOperation("reorder_section");reorder.arrangementID=ai;reorder.useID=second;reorder.to=first
        let result=try AgentProjectEditing.apply(request(p,[trim,reorder]),to:p)
        XCTAssertEqual(result.active.startID,second)
        let audio=try ArrangementCompiler.effectiveLanes(section:result.sections[0],use:result.active.uses.first{$0.id==first}!).first!.audio.first!
        XCTAssertEqual(audio.sourceStart,1);XCTAssertEqual(audio.duration,2)
        trim.duration=8
        XCTAssertThrowsError(try AgentProjectEditing.apply(request(p,[reorder,trim]),to:p));XCTAssertEqual(p.active.startID,first)
    }
    func testStepCommandsShareNotesAndRejectInvalidBatchOrMismatchedNode()throws {
        let p=try project(),lane=p.sections[0].lanes[0]
        var op=AgentOperation("set_step");op.useID=p.active.uses[0].id;op.laneID=lane.id;op.nodeID="midi:\(lane.id)";op.stepIndex=4;op.pitch=36;op.enabled=true;op.subdivisions=4;op.velocity=108
        let first=try AgentProjectEditing.apply(request(p,[op]),to:p)
        let notes=try ArrangementCompiler.effectiveLanes(section:first.sections[0],use:first.active.uses[0])[0].notes
        XCTAssertEqual(notes.count,1);XCTAssertEqual(notes[0].beat,1);XCTAssertEqual(notes[0].velocity,108)
        let again=try AgentProjectEditing.apply(request(first,[op]),to:first)
        XCTAssertEqual(again,first)
        var invalid=op;invalid.pitch=200
        XCTAssertThrowsError(try AgentProjectEditing.apply(request(p,[op,invalid]),to:p));XCTAssertTrue(p.sections[0].lanes[0].notes.isEmpty)
        invalid=op;invalid.nodeID="instrument:\(p.tracks[0].id)"
        XCTAssertThrowsError(try AgentProjectEditing.apply(request(p,[invalid]),to:p))
        invalid=op;invalid.enabled=nil;XCTAssertThrowsError(try AgentProjectEditing.apply(request(p,[invalid]),to:p))
        op.enabled=false;let cleared=try AgentProjectEditing.apply(request(first,[op]),to:first)
        XCTAssertTrue(try ArrangementCompiler.effectiveLanes(section:cleared.sections[0],use:cleared.active.uses[0])[0].notes.isEmpty)
    }

    func testBatchMIDICommandsPreserveUntouchedNotesAndRejectStaleIDs()throws {
        var p=try project();var lane=p.sections[0].lanes[0];lane.notes=[Note(beat:0.13,length:1,pitch:60),Note(beat:0.13,length:1,pitch:64),Note(beat:3,length:1,pitch:67)]
        let use=p.active.uses[0].id;try ProjectEditing.setLane(lane,for:use,original:false,in:&p)
        var op=AgentOperation("edit_notes");op.useID=use;op.laneID=lane.id;op.nodeID="midi:\(lane.id)";op.noteIDs=lane.notes.prefix(2).map(\.id);op.edit="transpose";op.semitones=12
        let changed=try AgentProjectEditing.apply(request(p,[op]),to:p),notes=try ArrangementCompiler.effectiveLanes(section:changed.sections[0],use:changed.active.uses[0])[0].notes
        XCTAssertEqual(notes.map(\.pitch),[72,76,67]);XCTAssertEqual(notes.map(\.id),lane.notes.map(\.id))
        var bad=op;bad.noteIDs=["missing"]
        XCTAssertThrowsError(try AgentProjectEditing.apply(request(p,[op,bad]),to:p));XCTAssertEqual(lane.notes.map(\.pitch),[60,64,67])
        bad=op;bad.noteIDs=[lane.notes[0].id,lane.notes[0].id];XCTAssertThrowsError(try AgentProjectEditing.apply(request(p,[bad]),to:p))
        bad=op;bad.nodeID="instrument:\(lane.trackID)";XCTAssertThrowsError(try AgentProjectEditing.apply(request(p,[bad]),to:p))
    }

}
