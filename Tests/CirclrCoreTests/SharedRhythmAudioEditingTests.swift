import XCTest
@testable import CirclrCore

final class SharedRhythmAudioEditingTests:XCTestCase {
    func fixture()throws->Project {
        var p=Project();_=p.addTrack(name:"공유");_=p.addSection(name:"A",at:Point(),bars:4)
        let asset=Asset(name:"원본",path:"source.wav",duration:8,sampleRate:48000);p.assets=[asset]
        var pattern=RhythmPattern(name:"공유",trackID:p.tracks[0].id)
        var clip=AudioClip(assetID:asset.id,duration:1);clip.sourceStart=1;clip.fadeIn=0.2;clip.fadeOut=0.1
        pattern.audio=[clip];p.patterns=[pattern];p.global.rhythm.patternID=pattern.id
        p=try SectionGraphMigration.migrate(p)
        _=try ProjectEditing.reuse(p.active.uses[0].id,in:&p,at:Point(100,0))
        return p
    }
    @discardableResult func edit(_ c:AudioEditing.Change,_ p:inout Project)throws->ID? {
        try SharedRhythmAudioEditing.apply(c,patternID:p.patterns[0].id,trackID:p.tracks[0].id,clipID:p.patterns[0].audio[0].id,in:&p)
    }
    func testSplitOnlyPatternAndExpandedWindows()throws {
        var p=try fixture();let before=p
        let right=try edit(.split(sourceOffset:0.5),&p)
        XCTAssertEqual(p.patterns[0].audio.count,2);XCTAssertEqual(p.patterns[0].audio[1].id,right)
        XCTAssertEqual(p.patterns[0].audio[1].beat,1)
        XCTAssertEqual(p.patterns[0].audio[1].sourceStart,1.5)
        XCTAssertEqual(p.patterns[0].audio[0].renderWindow,p.patterns[0].audio[1].renderWindow)
        XCTAssertEqual(p.patterns[0].audio[0].renderWindow?.envelopes.count,1)
        var normalized=p;normalized.patterns=before.patterns;XCTAssertEqual(normalized,before)
        let expanded=try SectionGraphCompiler.expandedPattern(p.patterns[0],length:12,grid:p.global.beatGrid)
        XCTAssertEqual(expanded.audio.map{$0.renderWindow!.cycleBeat},[0,0,4,4,8,8])
        XCTAssertEqual(try JSONDecoder().decode(Project.self,from:JSONEncoder().encode(p)),p)
    }
    func testDuplicateAndDeleteIdentityAndWindow()throws {
        var p=try fixture();_=try edit(.split(sourceOffset:0.5),&p)
        let copy=try edit(.duplicate(beatOffset:2),&p)
        XCTAssertEqual(p.patterns[0].audio.last?.id,copy)
        XCTAssertEqual(p.patterns[0].audio.last?.beat,2)
        XCTAssertEqual(p.patterns[0].audio.last?.renderWindow?.cycleBeat,2)
        XCTAssertNil(try edit(.delete,&p));XCTAssertEqual(p.patterns[0].audio.count,2)
    }
    func testDifferentConsumerTemposAndFollowing()throws {
        var p=try fixture();p.arrangements[0].uses[1].settings.tempo = .local(90)
        let before=p
        XCTAssertThrowsError(try edit(.split(sourceOffset:0.5),&p));XCTAssertEqual(p,before)
        XCTAssertThrowsError(try edit(.duplicate(beatOffset:nil),&p));XCTAssertEqual(p,before)
        p.patterns[0].audio[0].followsTempo=true
        _=try edit(.split(sourceOffset:0.5),&p)
        XCTAssertEqual(p.patterns[0].audio[1].beat,1)
    }
    func testInvalidEditsAreAtomic()throws {
        var p=try fixture();let before=p
        for change:AudioEditing.Change in [.split(sourceOffset:.nan),.split(sourceOffset:0),.fade(input:2,output:0),.duplicate(beatOffset:4)] {
            XCTAssertThrowsError(try edit(change,&p));XCTAssertEqual(p,before)
        }
        var bad=p.patterns[0].audio[0];bad.gain = .infinity
        XCTAssertThrowsError(try edit(.replace(bad),&p));XCTAssertEqual(p,before)
        bad=before.patterns[0].audio[0];bad.sourceStart=8
        XCTAssertThrowsError(try edit(.replace(bad),&p));XCTAssertEqual(p,before)
        XCTAssertThrowsError(try SharedRhythmAudioEditing.apply(.delete,patternID:p.patterns[0].id,trackID:"stale",clipID:bad.id,in:&p));XCTAssertEqual(p,before)
    }
    func testVariableTempoAndUnalignedFramesRejectAtomically()throws {
        var p=try fixture();p.patterns[0].audio[0].followsTempo=true
        p.arrangements[0].uses[1].settings.tempo = .local(91)
        var before=p
        XCTAssertThrowsError(try edit(.split(sourceOffset:0.50001),&p));XCTAssertEqual(p,before)
        p.arrangements[0].uses[1].settings.tempo = Setting<Double>()
        p.sections[0].tempoChanges=[TempoChange(beat:2,bpm:90)]
        before=p
        XCTAssertThrowsError(try edit(.split(sourceOffset:0.5),&p));XCTAssertEqual(p,before)
        _=try edit(.duplicate(beatOffset:2),&p)
        XCTAssertEqual(p.patterns[0].audio.last?.beat,2)
    }

    func testOwnTempoOverridesParentMapAndReplaceNoop()throws {
        var p=try fixture()
        p.sections[0].tempoChanges=[TempoChange(beat:2,bpm:90)]
        let index=try XCTUnwrap(p.sections[0].graph?.nodes.firstIndex{if case .rhythmAudio=$0.content{return true};return false})
        p.sections[0].graph!.nodes[index].settings.tempo = .local(120)
        let before=p
        _=try edit(.replace(p.patterns[0].audio[0]),&p);XCTAssertEqual(p,before)
        _=try edit(.split(sourceOffset:0.5),&p)
        XCTAssertEqual(p.patterns[0].audio[1].beat,1)
    }

}
