import XCTest
@testable import CirclrCore
@testable import CirclrAudio

final class MIDITempoRenderTests:XCTestCase {
    private func file() -> Data {
        // Format 1, 480 PPQ: 120 BPM at 0, 60 BPM at 2; one note ends at beat 4.
        let tempo:[UInt8]=[0,0xff,0x51,3,0x07,0xa1,0x20,0x87,0x40,0xff,0x51,3,0x0f,0x42,0x40,0,0xff,0x2f,0]
        let notes:[UInt8]=[0,0x90,60,100,0x8f,0,0x80,60,0,0,0xff,0x2f,0]
        var data=Data(Array("MThd".utf8)+[0,0,0,6,0,1,0,2,1,0xe0])
        for body in [tempo,notes] {data.append(contentsOf:Array("MTrk".utf8)+[0,0,0,UInt8(body.count)]+body)}
        return data
    }
    func testImportedTempoDrivesNoteOffAndCutoffThroughSectionRenderer()async throws {
        let imported=try MIDIImport.read(file())
        XCTAssertNil(imported.tempoImportIssue);XCTAssertEqual(imported.beats,4)
        XCTAssertEqual(imported.tempoChanges,[.init(beat:0,bpm:120),.init(beat:2,bpm:60)])
        let parts=imported.tracks.map{MIDIImportPart(name:$0.name,notes:$0.notes)}
        let map=MIDIImportTempoMap(initialBPM:120,changes:Array(imported.tempoChanges.dropFirst()))
        var original=Project();original.global.tempo=120
        _=original.addTrack(name:"원본 신스");_=original.addSection(name:"시간 기준",at:Point(),bars:1)
        original.tracks[0].instrument = .synthesizer(.pad)
        original=try SectionGraphMigration.migrate(original)
        let unchanged=original,useID=original.active.uses[0].id
        var context=MusicContext();context.tempo=120
        var durations:[Double]=[],renderedFrames:[Int]=[]
        for policy in [MIDIImportTempoPolicy.keepCurrent,.applyFile] {
            var project=original
            let laneIDs=try MIDIImportEditing.apply(parts,useID:useID,extendSection:false,tempoPolicy:policy,tempoMap:map,in:&project)
            let use=project.active.uses[0],section=project.sections[0]
            let lanes=try ArrangementCompiler.effectiveLanes(section:section,use:use)
            let lane=try XCTUnwrap(lanes.first{laneIDs.contains($0.id)})
            let trackIndex=try XCTUnwrap(project.tracks.firstIndex{$0.id==lane.trackID})
            project.tracks[trackIndex].instrument = .synthesizer(.pad)
            let patch=try XCTUnwrap(project.tracks[trackIndex].instrument.synth)
            let graph=try XCTUnwrap(SectionGraphEditing.effective(section:section,use:use))
            let node=try XCTUnwrap(graph.nodes.first{if case .instrument(let track)=$0.content{return track==lane.trackID};return false})
            XCTAssertEqual(node.startBeat,0);XCTAssertNil(node.lengthBeats);XCTAssertEqual(node.repeatCount,1)
            try AutomationEditing.set(parameter:.synthCutoff,points:[.init(beat:0,value:400),.init(beat:4,value:6400)],
                                      nodeID:node.id,useID:useID,in:&project)
            let beforeRender=project,currentUse=project.active.uses[0]
            let (currentSection,currentContext,clock)=try ArrangementCompiler.context(project:project,use:currentUse)
            let expectedClock=try MusicClock(bars:1,context:context,
                tempoChanges:policy == .applyFile ? [TempoChange(beat:2,bpm:60)]:[])
            XCTAssertEqual(clock.seconds,policy == .applyFile ? 3:2,accuracy:1e-12)
            XCTAssertEqual(clock.seconds(at:4),expectedClock.seconds(at:4),accuracy:1e-12)
            let expectedSpans:[AutomationSpan]=policy == .applyFile ? [
                .init(start:0,end:1,from:400,to:3400,shape:.linear),
                .init(start:1,end:3,from:3400,to:6400,shape:.linear)
            ]:[.init(start:0,end:2,from:400,to:6400,shape:.linear)]
            let plan=try XCTUnwrap(SectionGraphCompiler.compile(project:project,section:currentSection,use:currentUse,context:currentContext,clock:clock))
            let outputs=try await SectionGraphRenderer.render(plan,project:project,root:nil,clock:clock,tail:0.5)
            let actual=try XCTUnwrap(outputs[lane.trackID])
            // Expected note-off and filter timing share a separately constructed 48 kHz clock.
            let expected=try ProductionInstrument.synth(imported.tracks[0].notes,patch:patch,clock:expectedClock,tail:0.5,
                automation:[AutomationPlan(parameter:.synthCutoff,spans:expectedSpans)])
            XCTAssertEqual(actual.left,expected.left);XCTAssertEqual(actual.right,expected.right)
            let noteOff=Int(expectedClock.seconds(at:4)*PCM.rate)
            XCTAssertGreaterThan(actual.left[noteOff..<min(noteOff+4800,actual.count)].map{abs($0)}.max() ?? 0,0)
            var cursor=try SynthCutoffCursor(plan.automation[node.id] ?? [])
            XCTAssertEqual(cursor.value(at:expectedClock.seconds(at:4)),6400,accuracy:1e-10)
            XCTAssertEqual(cursor.value(at:expectedClock.seconds+0.4),6400,accuracy:1e-10)
            XCTAssertEqual(project,beforeRender);XCTAssertEqual(project.sections,original.sections)
            durations.append(clock.seconds);renderedFrames.append(actual.count)
        }
        XCTAssertEqual(durations,[2,3]);XCTAssertEqual(renderedFrames,[120000,168000])
        XCTAssertEqual(original,unchanged)
    }
}
