import XCTest
@testable import CirclrCore

final class MusicContextEditingTests: XCTestCase {
    func fixture() throws -> Project {
        var p=Project();_ = p.addTrack(name:"건반");_ = p.addSection(name:"벌스",at:Point(),bars:4)
        p.enableAlbum();return try SectionGraphMigration.migrate(p)
    }
    func section(_ p:Project) -> CircleAddress {.section(arrangementID:p.activeArrangementID,useID:p.active.uses[0].id)}

    func testEffectiveDefaultAlbumAndRememberedLocalValue() throws {
        var p=try fixture();p.album!.compositions[0].settings.tempo = .local(90)
        p.sections[0].settings.tempo = .local(100)
        let address=section(p),initial=p
        XCTAssertEqual(try MusicContextEditing.snapshot(at:address,in:p).context.tempo,100)
        XCTAssertEqual(p,initial)
        try MusicContextEditing.apply(.source(.tempo,.global),at:address,in:&p)
        XCTAssertEqual(try MusicContextEditing.snapshot(at:address,in:p).context.tempo,120)
        try MusicContextEditing.apply(.tempo(132),at:address,in:&p)
        XCTAssertEqual(p.active.uses[0].settings.tempo,.local(132))
        try MusicContextEditing.apply(.source(.tempo,.inherit),at:address,in:&p)
        XCTAssertEqual(try MusicContextEditing.snapshot(at:address,in:p).context.tempo,100)
        XCTAssertEqual(p.active.uses[0].settings.tempo.value,132)
        try MusicContextEditing.apply(.source(.tempo,.local),at:address,in:&p)
        XCTAssertEqual(try MusicContextEditing.snapshot(at:address,in:p).context.tempo,132)
        XCTAssertEqual(p.sections,initial.sections)
    }

    func testFirstLocalCopiesEffectiveValueAndFieldEditsPreserveEachOther() throws {
        var p=try fixture();p.global.tempo=128;p.global.meter=Meter(7,8)
        p.global.scale=Scale(root:9,name:"Dorian",intervals:Scale.modes.first{$0.0=="Dorian"}!.1)
        p.global.beatGrid=BeatGrid(subdivisions:3,accents:[2,2,3],swing:0.2)
        let address=section(p)
        try MusicContextEditing.apply(.source(.tempo,.local),at:address,in:&p)
        XCTAssertEqual(p.active.uses[0].settings.tempo,.local(128))
        try MusicContextEditing.apply(.numerator(5),at:address,in:&p)
        try MusicContextEditing.apply(.denominator(16),at:address,in:&p)
        try MusicContextEditing.apply(.scaleRoot(2),at:address,in:&p)
        try MusicContextEditing.apply(.scaleMode("major"),at:address,in:&p)
        try MusicContextEditing.apply(.subdivisions(8),at:address,in:&p)
        try MusicContextEditing.apply(.swing(0.4),at:address,in:&p)
        let context=try MusicContextEditing.snapshot(at:address,in:p).context
        XCTAssertEqual(context.meter,Meter(5,16));XCTAssertEqual(context.scale.root,2)
        XCTAssertEqual(context.scale.name,"major");XCTAssertEqual(context.tempo,128)
        XCTAssertEqual(context.beatGrid,BeatGrid(subdivisions:8,accents:[2,2,3],swing:0.4))
        XCTAssertEqual(p.global.meter,Meter(7,8))
    }

    func testGlobalCompositionRhythmAndRoundTrip() throws {
        var p=try fixture();let song=p.album!.compositions[0].id
        let pattern=RhythmPattern(name:"킥",trackID:p.tracks[0].id);p.patterns=[pattern]
        try MusicContextEditing.apply(.tempo(128.123456789),at:.album,in:&p)
        try MusicContextEditing.apply(.rhythm(pattern.id),at:.composition(song),in:&p)
        try MusicContextEditing.apply(.accents("2 + 2 + 3"),at:.composition(song),in:&p)
        let saved=try JSONDecoder().decode(Project.self,from:JSONEncoder().encode(p))
        XCTAssertEqual(saved,p)
        let context=try MusicContextEditing.snapshot(at:section(p),in:saved).context
        XCTAssertEqual(context.tempo,128.123456789);XCTAssertEqual(context.rhythm.patternID,pattern.id)
        XCTAssertEqual(context.beatGrid.accents,[2,2,3])
        let original=p;try MusicContextEditing.apply(.tempo(128.123456789),at:.album,in:&p)
        XCTAssertEqual(p,original)
        try MusicContextEditing.apply(.rhythm(nil),at:.composition(song),in:&p)
        XCTAssertNil(try MusicContextEditing.snapshot(at:section(p),in:p).context.rhythm.patternID)
    }

    func testSharedNodeEditNeverCopiesUseOverridesIntoOriginal() throws {
        var p=try fixture();let use=p.active.uses[0],base=p.sections[0].graph!
        var variant=base;variant.nodes[0].gain=0.4
        try SectionGraphEditing.set(variant,useID:use.id,original:false,in:&p)
        let edits=p.active.uses[0].graphEdits,nodeID=base.nodes[0].id
        let address=CircleAddress.music(arrangementID:p.activeArrangementID,useID:use.id,nodeID:nodeID)
        try MusicContextEditing.apply(.tempo(150),at:address,original:true,in:&p)
        XCTAssertEqual(p.sections[0].graph!.nodes[0].settings.tempo,.local(150))
        XCTAssertEqual(p.sections[0].graph!.nodes[0].gain,base.nodes[0].gain)
        XCTAssertEqual(p.active.uses[0].graphEdits,edits)
        XCTAssertEqual(Array(p.sections[0].graph!.nodes.dropFirst()),Array(base.nodes.dropFirst()))
        XCTAssertEqual(try MusicContextEditing.snapshot(at:address,original:true,in:p).context.tempo,150)
    }

    func testInactiveArrangementAddressDoesNotSwitchActiveOrEditOtherUse() throws {
        var p=try fixture();let old=p.activeArrangementID,oldUse=p.active.uses[0]
        ProjectEditing.duplicateArrangement(in:&p,name:"대안")
        let target=section(p);p.activeArrangementID=old
        try MusicContextEditing.apply(.tempo(144),at:target,in:&p)
        XCTAssertEqual(p.activeArrangementID,old);XCTAssertEqual(p.active.uses[0],oldUse)
        XCTAssertEqual(try MusicContextEditing.snapshot(at:target,in:p).context.tempo,144)
    }

    func testInvalidValuesTargetsAndDormantLocalValueAreAtomic() throws {
        var p=try fixture();let address=section(p),before=p
        let changes:[MusicContextChange]=[.tempo(.nan),.tempo(0),.numerator(65),.denominator(3),.scaleRoot(12),.scaleMode("unknown"),.swing(0.8),.subdivisions(0),.accents("2++3"),.rhythm("missing")]
        for change in changes {
            XCTAssertThrowsError(try MusicContextEditing.apply(change,at:address,in:&p))
            XCTAssertEqual(p,before)
        }
        for target in [CircleAddress.sound,.section(arrangementID:"missing",useID:"missing"),.music(arrangementID:p.activeArrangementID,useID:p.active.uses[0].id,nodeID:"missing")] {
            XCTAssertThrowsError(try MusicContextEditing.apply(.tempo(140),at:target,in:&p));XCTAssertEqual(p,before)
        }
        p.arrangements[0].uses[0].settings.tempo=Setting(1000,source:.inherit)
        let dormant=p
        XCTAssertThrowsError(try MusicContextEditing.apply(.source(.tempo,.local),at:address,in:&p))
        XCTAssertEqual(p,dormant)
    }

    func testAccentParserRejectsMissingOrInvalidGroups() throws {
        XCTAssertEqual(try MusicContextEditing.parseAccents(""),[])
        XCTAssertEqual(try MusicContextEditing.parseAccents("2 + 2+3"),[2,2,3])
        for text in ["0","2++3","2+","-2+3","65","word","1.5","1,2",Array(repeating:"1",count:65).joined(separator:"+")] {
            XCTAssertThrowsError(try MusicContextEditing.parseAccents(text))
        }
    }
}
