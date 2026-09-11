import XCTest
import CirclrCore
@testable import CirclrAudio

final class SourceCircleAudioTests:XCTestCase {
    func fixture(_ root:URL)throws->Project {
        var sound=PCM(frames:48000)
        for i in sound.left.indices {sound.left[i]=Float(i%47)/1024;sound.right[i] = -Float(i%31)/1024}
        let url=root.appendingPathComponent("audio.wav");try sound.writeWAV(url)
        var p=Project();_=p.addSection(name:"소스",at:Point(),bars:1);p=try SectionGraphMigration.migrate(p)
        let asset=Asset(name:"오디오",path:url.path,duration:1,sampleRate:48000)
        _=try AudioImportEditing.apply([asset],to:.section(arrangementID:p.active.id,useID:p.active.uses[0].id,trackID:nil,beat:0,position:nil,original:false),projectID:p.id,revision:p.musicRevision,in:&p)
        return p
    }
    func render(_ p:Project,_ root:URL?=nil)async throws->PCM {
        try await ArrangementRenderer.render(project:p,root:root,plan:ArrangementCompiler.compile(p),tailSeconds:0).mix
    }
    func testAudioOnlyMatchesLegacyPCMAfterEffectSaveAndReload()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(newID());defer{try? FileManager.default.removeItem(at:root)}
        var p=try fixture(root),legacy=p
        let lanes=try ArrangementCompiler.effectiveLanes(section:p.sections[0],use:p.active.uses[0])
        let legacyGraph=SectionGraphMigration.graph(lanes:lanes,tracks:p.tracks,effects:[])
        try SectionGraphEditing.set(legacyGraph,useID:p.active.uses[0].id,original:false,in:&legacy)
        func withEffect(_ p:Project)throws->Project {
            var p=p,g=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]))
            let source=try XCTUnwrap(g.nodes.first{if case .audio=$0.content{return true};return false})
            try SectionGraphEditing.insertEffect(MusicCircle(name:"필터",content:.effect(Effect(.lowpass,amount:0.5))),from:source.id,in:&g)
            try SectionGraphEditing.set(g,useID:p.active.uses[0].id,original:false,in:&p);return p
        }
        p=try withEffect(p);legacy=try withEffect(legacy)
        let reduced=try await render(p),old=try await render(legacy)
        XCTAssertGreaterThan(reduced.peak,0.01);XCTAssertEqual(reduced.left,old.left);XCTAssertEqual(reduced.right,old.right)
        let package=root.appendingPathComponent("source.circlr");_=try ProjectStore.save(p,to:package,mediaRoot:nil)
        let loaded=try ProjectStore.load(package),reopened=try await render(loaded.project,loaded.root)
        XCTAssertEqual(reopened.left,reduced.left);XCTAssertEqual(reopened.right,reduced.right)
    }
    func testFirstMIDIAndExplicitRhythmProduceSoundInAudioOnlyTrack()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(newID());defer{try? FileManager.default.removeItem(at:root)}
        var p=try fixture(root),lane=try XCTUnwrap(ArrangementCompiler.effectiveLanes(section:p.sections[0],use:p.active.uses[0]).first)
        lane.audio[0].gain=0
        try ProjectEditing.setLane(lane,for:p.active.uses[0].id,original:false,in:&p)
        let silent=try await render(p);XCTAssertEqual(silent.peak,0)
        var midi=p;lane.notes=[Note(beat:0,length:1,pitch:64)]
        try ProjectEditing.setLane(lane,for:midi.active.uses[0].id,original:false,in:&midi)
        let notes=try await render(midi);XCTAssertGreaterThan(notes.peak,0.01)
        var pattern=RhythmPattern(name:"새 패턴",trackID:lane.trackID);pattern.notes=[Note(beat:0,length:1,pitch:64)];p.patterns.append(pattern)
        var assignment=RhythmAssignment();assignment.patternID=pattern.id
        p.arrangements[p.activeIndex].uses[0].settings.rhythm = .local(assignment)
        _=try SourceCircleEditing.ensureRhythmMIDI(trackID:lane.trackID,useID:p.active.uses[0].id,in:&p)
        let rhythm=try await render(p);XCTAssertGreaterThan(rhythm.peak,0.01)
    }
    func testEffectBeforeOutputProcessesOnlyThatTracksAudio()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(newID());defer{try? FileManager.default.removeItem(at:root)}
        var p=try fixture(root),second=p.assets[0];second.id=newID();second.name="다른 오디오"
        _=try AudioImportEditing.apply([second],to:.section(arrangementID:p.active.id,useID:p.active.uses[0].id,trackID:nil,beat:0,position:nil,original:false),projectID:p.id,revision:p.musicRevision,in:&p)
        let before=try await ArrangementRenderer.render(project:p,root:nil,plan:ArrangementCompiler.compile(p),tailSeconds:0)
        var g=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:p.active.uses[0]))
        let track=p.tracks[0].id,other=p.tracks[1].id
        let output=try XCTUnwrap(g.nodes.first{if case .output(let id)=$0.content{return id==track};return false})
        try SectionGraphEditing.insertEffectBeforeOutput(MusicCircle(name:"출력 gain",content:.effect(Effect(.gain,amount:0.5))),before:output.id,in:&g)
        try SectionGraphEditing.set(g,useID:p.active.uses[0].id,original:false,in:&p)
        let after=try await ArrangementRenderer.render(project:p,root:nil,plan:ArrangementCompiler.compile(p),tailSeconds:0)
        XCTAssertEqual(after.stems[track]!.left,before.stems[track]!.left.map{$0*0.5})
        XCTAssertEqual(after.stems[track]!.right,before.stems[track]!.right.map{$0*0.5})
        XCTAssertEqual(after.stems[other]!.left,before.stems[other]!.left);XCTAssertEqual(after.stems[other]!.right,before.stems[other]!.right)
    }
}
