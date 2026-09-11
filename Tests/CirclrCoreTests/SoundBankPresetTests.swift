import XCTest
@testable import CirclrCore

final class SoundBankPresetTests:XCTestCase {
    func preset(_ program:Int=0,_ lsb:Int=0,_ drums:Bool=false,_ name:String="Piano")->SoundBankPreset {
        SoundBankPreset(name:name,program:program,bankLSB:lsb,drums:drums)!
    }
    func testNamesAndAddressesRemainDistinctAcrossVariationsAndKits() {
        let basic=preset(),variation=preset(0,8),kit=preset(0,0,true,"Standard")
        let ordered=SoundBankPreset.ordered([variation,kit,basic,basic])
        XCTAssertEqual(ordered,[basic,variation,kit]);XCTAssertEqual(Set(ordered.map(\.id)).count,3)
        XCTAssertEqual(preset(127).detail,"Sound Bank · 효과음 · #128 · 기본 뱅크")
        XCTAssertTrue(variation.detail.contains("변형 8"));XCTAssertTrue(kit.detail.contains("드럼 킷"))
    }
    func testExactDisplayedNumbersFamilyAndDrumFilters() {
        let bank=[preset(),preset(0,8),preset(10,0,false,"Music box"),preset(25,0,true,"TR-808"),preset(127,0,false,"Gunshot")]
        let catalog=SoundSelection.instruments([],bank:bank)
        XCTAssertEqual(SoundSelection.search(catalog,query:"#１").map(\.id),[bank[0].id,bank[1].id])
        XCTAssertEqual(SoundSelection.search(catalog,query:"피아노".decomposedStringWithCanonicalMapping).count,2)
        XCTAssertEqual(SoundSelection.search(catalog,query:"#26",bankDrums:true).map(\.id),[bank[3].id])
        XCTAssertTrue(SoundSelection.search(catalog,query:"#26",bankDrums:false).isEmpty)
        XCTAssertEqual(SoundSelection.search(catalog,query:"#128").map(\.id),[bank[4].id])
        XCTAssertTrue(SoundSelection.search(catalog,query:"#0").isEmpty)
        XCTAssertTrue(SoundSelection.search(catalog,query:"#129").isEmpty)
        XCTAssertTrue(SoundSelection.search(catalog,query:"#one").isEmpty)
    }
    func testLegacyDecodeAndVariationRoundTrip()throws {
        let old=try JSONDecoder().decode(Instrument.self,from:Data(#"{"kind":"soundBank","program":4,"drums":false}"#.utf8))
        XCTAssertNil(old.bankLSB);XCTAssertEqual(SoundSelection.choice(in:old),preset(4).id)
        let catalog=SoundSelection.instruments([],bank:[preset(4,8,false,"Detuned EP 1")])
        let next=try SoundSelection.instrument(preset(4,8).id,current:old,catalog:catalog)
        XCTAssertEqual(next.bankLSB,8);XCTAssertEqual(next.program,4);XCTAssertFalse(next.drums)
        XCTAssertEqual(try JSONDecoder().decode(Instrument.self,from:JSONEncoder().encode(next)),next)
        XCTAssertEqual(try SoundSelection.instrument(preset(4,8).id,current:next,catalog:catalog),next)
    }
    func testPresetSelectionChangesOnlyBankAddressAndPreservesInactiveSounds()throws {
        var current=Instrument.synthesizer(.electricPiano);current.synth?.cutoff=731
        current.plugin=PluginDescriptor(name:"saved",type:SoundSelection.instrumentType,subtype:1,manufacturer:2,state:Data([1,2]))
        let before=current,kit=preset(25,0,true,"TR-808"),catalog=SoundSelection.instruments([],bank:[kit,preset(4,8)])
        let drums=try SoundSelection.instrument(kit.id,current:current,catalog:catalog)
        XCTAssertEqual(drums.kind,.soundBank);XCTAssertEqual(drums.program,25);XCTAssertNil(drums.bankLSB);XCTAssertTrue(drums.drums)
        XCTAssertEqual(drums.synth,current.synth);XCTAssertEqual(drums.plugin,current.plugin)
        let melodic=try SoundSelection.instrument(preset(4,8).id,current:drums,catalog:catalog)
        XCTAssertFalse(melodic.drums);XCTAssertEqual(melodic.bankLSB,8)
        XCTAssertEqual(current,before)
        XCTAssertThrowsError(try SoundSelection.instrument(preset(4,16).id,current:melodic,catalog:catalog))
    }
    func testInvalidMetadataAndProjectBankValuesAreRejected()throws {
        XCTAssertNil(SoundBankPreset(name:" ",program:0,bankLSB:0,drums:false))
        XCTAssertNil(SoundBankPreset(name:"test",program:128,bankLSB:0,drums:false))
        XCTAssertNil(SoundBankPreset(name:"test",program:0,bankLSB:-1,drums:false))
        var project=try HierarchyEditingTests().fixture()
        project.tracks[0].instrument=Instrument(program:4,bankLSB:8)
        XCTAssertNoThrow(try ProjectStore.validateStructure(project))
        project.tracks[0].instrument.bankLSB=128
        XCTAssertThrowsError(try ProjectStore.validateStructure(project))
        project.tracks[0].instrument.bankLSB=nil;project.tracks[0].instrument.program = -1
        XCTAssertThrowsError(try ProjectStore.validateStructure(project))
    }
}
