import XCTest
@testable import CirclrCore

final class MIDITempoImportTests:XCTestCase {
    func fixture(bars:Int=2)throws->Project {
        var p=Project();_=p.addTrack(name:"원본");_=p.addSection(name:"A",at:Point(),bars:bars)
        return try SectionGraphMigration.migrate(p)
    }
    func parts(_ length:Double=4)->[MIDIImportPart] {[.init(name:"가져온 연주",notes:[Note(beat:0,length:length,pitch:60)])]}
    var map:MIDIImportTempoMap {.init(initialBPM:120,changes:[.init(beat:2,bpm:60)])}
    func clock(_ p:Project)throws->MusicClock {try ArrangementCompiler.context(project:p,use:p.active.uses[0]).2}
    func importFile(_ p:inout Project,at:Double=0,length:Double=4,extend:Bool=false,map:MIDIImportTempoMap?=nil)throws {
        _=try MIDIImportEditing.apply(parts(length),useID:p.active.uses[0].id,extendSection:extend,atBeat:at,tempoPolicy:.applyFile,tempoMap:map ?? self.map,in:&p)
    }
    func testRegionReplacementAndExactEndRestore()throws {
        var p=try fixture();let before=p
        let preview=try MIDITempoImport.preview(parts(),useID:p.active.uses[0].id,extendSection:false,atBeat:2,tempoMap:map,in:p)
        XCTAssertEqual(preview.regionSeconds,3);XCTAssertEqual(preview.previousRegionSeconds,2)
        XCTAssertEqual(preview.sectionSeconds,5);XCTAssertEqual(preview.previousSectionSeconds,4)
        try importFile(&p,at:2)
        let c=try clock(p)
        XCTAssertEqual(c.tempos,[.init(beat:0,bpm:120),.init(beat:4,bpm:60),.init(beat:6,bpm:120)])
        XCTAssertEqual(c.seconds,5);XCTAssertEqual(p.sections,before.sections);XCTAssertEqual(p.schemaVersion,4)
        var exact=try fixture(bars:1);try importFile(&exact)
        XCTAssertEqual(try clock(exact).seconds,3)
        XCTAssertEqual(exact.active.uses[0].tempoOverride?.changes,[.init(beat:2,bpm:60)])
    }
    func testVariableExistingMapAndExtensionRemainderRestore()throws {
        var p=try fixture();p.sections[0].tempoChanges=[.init(beat:1,bpm:90),.init(beat:3,bpm:80),.init(beat:6,bpm:100)]
        try importFile(&p,at:2,length:3)
        XCTAssertEqual(try clock(p).tempos,[.init(beat:0,bpm:120),.init(beat:1,bpm:90),.init(beat:2,bpm:120),.init(beat:4,bpm:60),.init(beat:5,bpm:80),.init(beat:6,bpm:100)])
        var extended=try fixture(bars:1)
        try importFile(&extended,at:2,length:5,extend:true)
        let c=try clock(extended)
        XCTAssertEqual(c.beats,8);XCTAssertEqual(c.bpm(at:7),120)
        XCTAssertEqual(c.seconds,5.5)
    }
    func testKeepCurrentIgnoresInvalidFileMapAndDoesNotUpgrade()throws {
        var p=try fixture();let before=p
        let invalid=MIDIImportTempoMap(initialBPM:.nan,changes:[.init(beat:-1,bpm:0)])
        let preview=try MIDITempoImport.preview(parts(),useID:p.active.uses[0].id,extendSection:false,tempoPolicy:.keepCurrent,tempoMap:invalid,in:p)
        XCTAssertNil(preview.tempoOverride);XCTAssertEqual(preview.regionSeconds,2)
        _=try MIDIImportEditing.apply(parts(),useID:p.active.uses[0].id,extendSection:false,tempoMap:invalid,in:&p)
        XCTAssertEqual(p.schemaVersion,before.schemaVersion);XCTAssertNil(p.active.uses[0].tempoOverride)
        XCTAssertEqual(try clock(p).seconds,4);XCTAssertEqual(p.sections,before.sections)
    }
    func testMalformedFileMapsAndMissingExtensionAreAtomic()throws {
        let base=try fixture(bars:1)
        for bad:MIDIImportTempoMap in [.init(initialBPM:0),.init(initialBPM:.infinity),.init(initialBPM:120,changes:[.init(beat:0,bpm:60)]),.init(initialBPM:120,changes:[.init(beat:2,bpm:60),.init(beat:2,bpm:90)]),.init(initialBPM:120,changes:[.init(beat:3,bpm:60),.init(beat:2,bpm:90)])] {
            var p=base;XCTAssertThrowsError(try importFile(&p,map:bad));XCTAssertEqual(p,base)
        }
        var p=base;XCTAssertThrowsError(try importFile(&p,at:2));XCTAssertEqual(p,base)
        XCTAssertThrowsError(try MIDIImportEditing.apply(parts(),useID:p.active.uses[0].id,extendSection:false,tempoPolicy:.applyFile,in:&p));XCTAssertEqual(p,base)
    }
    func testOtherUseOriginalPolicyClearDuplicateUndoAndRoundTrip()throws {
        var p=try fixture()
        p.arrangements[0].uses[0].settings.tempo = .local(150)
        _=try ProjectEditing.reuse(p.active.uses[0].id,in:&p,at:Point())
        let before=p,other=p.active.uses[1]
        try importFile(&p)
        XCTAssertEqual(p.active.uses[1],other);XCTAssertEqual(p.sections,before.sections)
        XCTAssertEqual(try clock(p).bpm(at:0),120)
        XCTAssertEqual(p.active.uses[0].settings.tempo,before.active.uses[0].settings.tempo)
        XCTAssertEqual(try JSONDecoder().decode(Project.self,from:JSONEncoder().encode(p)),p)
        var clone=p;ProjectEditing.duplicateArrangement(in:&clone,name:"B")
        XCTAssertEqual(clone.active.uses[0].tempoOverride,p.active.uses[0].tempoOverride)
        var detached=p;XCTAssertThrowsError(try ProjectEditing.detach(p.active.uses[0].id,in:&detached));XCTAssertEqual(detached,p)
        let restored=try CircleHistory.restore(before,layoutOnly:false,current:p)
        XCTAssertEqual(restored.schemaVersion,before.schemaVersion);XCTAssertNil(restored.active.uses[0].tempoOverride)
        try UseTempoOverrideEditing.clear(useID:p.active.uses[0].id,in:&p)
        XCTAssertEqual(try clock(p).bpm(at:0),150);XCTAssertEqual(p.schemaVersion,4)
    }
    func testTempoSettingsRequireExplicitClearButOtherFieldsRemainEditable()throws {
        var p=try fixture();try importFile(&p);p.enableAlbum();let before=p
        let address=CircleAddress.section(arrangementID:p.activeArrangementID,useID:p.active.uses[0].id)
        XCTAssertThrowsError(try MusicContextEditing.apply(.tempo(90),at:address,in:&p));XCTAssertEqual(p,before)
        var changed=p;changed.arrangements[0].uses[0].settings.tempo = .local(90)
        XCTAssertThrowsError(try UseTempoOverrideEditing.validateChanges(from:p,to:changed))
        changed=p;changed.arrangements[0].uses[0].settings.scale = .local(Scale())
        XCTAssertNoThrow(try UseTempoOverrideEditing.validateChanges(from:p,to:changed))
        changed=p;changed.arrangements[0].uses[0].tempoOverride=nil;changed.arrangements[0].uses[0].settings.tempo = .local(90)
        XCTAssertNoThrow(try UseTempoOverrideEditing.validateChanges(from:p,to:changed))
    }
    func testExistingFollowingAudioRejectsTempoCrossingWithoutPartialImport()throws {
        var p=try fixture();let asset=Asset(name:"원본",path:"audio.wav",duration:4,sampleRate:48000);p.assets=[asset]
        var lane=p.sections[0].lanes[0],clip=AudioClip(assetID:asset.id,duration:3)
        clip.followsTempo=true;clip.sourceBPM=120;lane.audio=[clip]
        try ProjectEditing.setLane(lane,for:p.active.uses[0].id,original:true,in:&p)
        let before=p
        XCTAssertThrowsError(try importFile(&p));XCTAssertEqual(p,before)
        p.sections[0].lanes[0].audio[0].followsTempo=false
        try importFile(&p)
        XCTAssertEqual(p.schemaVersion,4)
    }
    func testBoundaryTempoAfterSelectedNotesIsIgnoredAndSchemaRequired()throws {
        var p=try fixture(bars:1)
        try importFile(&p,map:.init(initialBPM:120,changes:[.init(beat:2,bpm:60),.init(beat:4,bpm:999),.init(beat:8,bpm:20)]))
        XCTAssertEqual(try clock(p).seconds,3)
        p.schemaVersion=3;XCTAssertThrowsError(try ProjectStore.validateStructure(p))
    }
    func testLegacyAudioAndRepeatedUseIDsAcrossArrangementsValidateExactOwner()throws {
        var p=try fixture();let asset=Asset(name:"원본",path:"audio.wav",duration:4,sampleRate:48000);p.assets=[asset]
        var lane=p.sections[0].lanes[0],clip=AudioClip(assetID:asset.id,duration:3);clip.followsTempo=true;lane.audio=[clip]
        try ProjectEditing.setLane(lane,for:p.active.uses[0].id,original:true,in:&p)
        p.sections[0].graph=nil;p.schemaVersion=1
        let legacy=p;XCTAssertThrowsError(try importFile(&p));XCTAssertEqual(p,legacy)
        p=try SectionGraphMigration.migrate(p);p.schemaVersion=4
        var other=p.active;other.id=newID();other.name="다른 편곡"
        other.uses[0].tempoOverride = .init(initialBPM:120,changes:[.init(beat:2,bpm:60)])
        p.arrangements.append(other)
        XCTAssertNoThrow(try UseTempoOverrideEditing.validateAudio(in:p,useID:p.active.uses[0].id,arrangementID:p.activeArrangementID))
        XCTAssertThrowsError(try UseTempoOverrideEditing.validateAudio(in:p,useID:other.uses[0].id,arrangementID:other.id))
        XCTAssertThrowsError(try ProjectStore.validateStructure(p))
        var changed=p;changed.arrangements[0].uses[0].settings.tempo = .local(100)
        XCTAssertNoThrow(try UseTempoOverrideEditing.validateChanges(from:p,to:changed))
        changed=p;changed.arrangements[1].uses[0].settings.tempo = .local(100)
        XCTAssertThrowsError(try UseTempoOverrideEditing.validateChanges(from:p,to:changed))
    }
}
