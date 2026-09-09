import XCTest
@testable import CirclrCore

final class SoundSelectionTests:XCTestCase {
    func instruments(_ plugins:[AudioUnitCatalogEntry])->[SoundCatalogItem] {
        SoundSelection.instruments(plugins,bank:[SoundBankPreset(name:"Piano",program:0,bankLSB:0,drums:false)!])
    }
    func plugin(_ name:String="Nordic",vendor:String="겨울 Audio",type:UInt32=SoundSelection.instrumentType,subtype:UInt32=1)->AudioUnitCatalogEntry {
        .init(descriptor:.init(name:name,type:type,subtype:subtype,manufacturer:2),manufacturerName:vendor)
    }
    func testUnicodeVendorAndKindSearch() {
        let entries=instruments([plugin("Gláss Keys")])
        XCTAssertEqual(SoundSelection.search(entries,query:"ＧＬＡＳＳ 겨울".decomposedStringWithCanonicalMapping).map(\.title),["Gláss Keys"])
        XCTAssertEqual(SoundSelection.search(entries,query:"베이스".decomposedStringWithCanonicalMapping).map(\.id),[.synth(.bass)])
        XCTAssertEqual(SoundSelection.search(entries,query:"",category:.synth).count,10)
        XCTAssertEqual(SoundSelection.search(entries,query:"sound bank").map(\.id),[.soundBank(program:0,bankLSB:0,drums:false)])
        XCTAssertTrue(SoundSelection.search(entries,query:"없음").isEmpty)
    }
    func testInstrumentAndEffectCatalogsRejectOtherComponentTypes()throws {
        let instrument=plugin(),effect=plugin(type:SoundSelection.effectType),other=plugin(type:0)
        let all=[instrument,effect,other]
        let instruments=instruments(all),effects=SoundSelection.effects(all)
        XCTAssertEqual(instruments.count,12);XCTAssertEqual(effects.count,1)
        XCTAssertThrowsError(try SoundSelection.instrument(.audioUnit(effect.descriptor.id),current:Instrument(),catalog:effects))
        XCTAssertThrowsError(try SoundSelection.effect(.audioUnit(instrument.descriptor.id),current:Effect(.gain),catalog:instruments))
    }
    func testDuplicateNamesKeepDistinctIDsAndDuplicateComponentsAreRemoved() {
        let a=plugin(vendor:"North"),b=plugin(vendor:"South",subtype:2)
        let rows=SoundSelection.search(instruments([a,b,a]),query:"Nordic")
        XCTAssertEqual(rows.count,2);XCTAssertNotEqual(rows[0].id,rows[1].id)
        XCTAssertEqual(SoundSelection.search(rows,query:"South").map(\.id),[.audioUnit(b.descriptor.id)])
    }
    func testSameSynthPreservesEveryCustomizedValueAndOldEngine()throws {
        var current=Instrument.synthesizer(.pad)
        current.synth?.cutoff=731;current.synth?.attack=0.93;current.synth?.engineVersion=2
        current.synth?.stereoWidth=0.18;current.drums=true;current.program=45
        let result=try SoundSelection.instrument(.synth(.pad),current:current,catalog:instruments([]))
        XCTAssertEqual(result,current)
    }
    func testDifferentSynthUsesVoiceDefaultsPreservingOtherModes()throws {
        var current=Instrument.synthesizer(.pad);current.synth?.cutoff=731;current.drums=true;current.program=45
        current.plugin=plugin().descriptor
        let before=current
        let result=try SoundSelection.instrument(.synth(.bass),current:current,catalog:instruments([]))
        XCTAssertEqual(result.synth,SynthPatch(.bass));XCTAssertEqual(result.kind,.synthesizer)
        XCTAssertEqual(result.plugin,current.plugin);XCTAssertEqual(result.drums,true);XCTAssertEqual(result.program,45);XCTAssertEqual(current,before)
        let bank=try SoundSelection.instrument(.soundBank(program:45,bankLSB:0,drums:true),current:result,catalog:SoundSelection.instruments([],bank:[SoundBankPreset(name:"Fixture kit",program:45,bankLSB:0,drums:true)!]))
        XCTAssertEqual(bank.kind,.soundBank);XCTAssertEqual(bank.synth,result.synth);XCTAssertEqual(bank.program,45)
    }
    func testSameAudioUnitKeepsSerializedStateAndDifferentUnitReplacesIt()throws {
        let a=plugin(),b=plugin(subtype:2),catalog=instruments([a,b])
        var current=Instrument();current.kind = .audioUnit;current.plugin=a.descriptor
        current.plugin?.state=Data([1,2,3,4]);current.plugin?.name="保存された名前"
        XCTAssertEqual(try SoundSelection.instrument(.audioUnit(a.descriptor.id),current:current,catalog:catalog),current)
        let next=try SoundSelection.instrument(.audioUnit(b.descriptor.id),current:current,catalog:catalog)
        XCTAssertEqual(next.plugin,b.descriptor);XCTAssertNil(next.plugin?.state)
        XCTAssertThrowsError(try SoundSelection.instrument(.audioUnit(a.descriptor.id),current:current,catalog:[]))
    }
    func testEffectSelectionKeepsParametersAndSamePluginState()throws {
        let a=plugin(type:SoundSelection.effectType),b=plugin(type:SoundSelection.effectType,subtype:2)
        let catalog=SoundSelection.effects([a,b]);var current=Effect(.reverb,amount:0.27,secondary:0.82)
        let next=try SoundSelection.effect(.audioUnit(a.descriptor.id),current:current,catalog:catalog)
        XCTAssertEqual(next.kind,.audioUnit);XCTAssertEqual(next.plugin,a.descriptor)
        XCTAssertEqual(next.amount,current.amount);XCTAssertEqual(next.secondary,current.secondary);XCTAssertEqual(next.renderVersion,current.renderVersion)
        current=next;current.plugin?.state=Data([7,8,9])
        XCTAssertEqual(try SoundSelection.effect(.audioUnit(a.descriptor.id),current:current,catalog:catalog),current)
        XCTAssertEqual(try SoundSelection.effect(.audioUnit(b.descriptor.id),current:current,catalog:catalog).plugin,b.descriptor)
        XCTAssertThrowsError(try SoundSelection.effect(.synth(.pad),current:current,catalog:catalog))
        XCTAssertThrowsError(try SoundSelection.effect(.audioUnit(a.descriptor.id),current:current,catalog:[]))
    }
    func testReturningToAnInactiveSoundRestoresItsSavedSettings()throws {
        let unit=plugin(),catalog=instruments([unit])
        var current=Instrument.synthesizer(.pad);current.synth?.cutoff=731
        current.plugin=unit.descriptor;current.plugin?.state=Data([4,3,2,1])
        let bank=try SoundSelection.instrument(.soundBank(program:0,bankLSB:0,drums:false),current:current,catalog:catalog)
        XCTAssertEqual(try SoundSelection.instrument(.synth(.pad),current:bank,catalog:catalog),current)
        let au=try SoundSelection.instrument(.audioUnit(unit.descriptor.id),current:bank,catalog:catalog)
        XCTAssertEqual(au.kind,.audioUnit);XCTAssertEqual(au.plugin,current.plugin)
        let fx=plugin(type:SoundSelection.effectType);var effect=Effect(.reverb)
        effect.plugin=fx.descriptor;effect.plugin?.state=Data([8,7,6])
        let result=try SoundSelection.effect(.audioUnit(fx.descriptor.id),current:effect,catalog:SoundSelection.effects([fx]))
        XCTAssertEqual(result.kind,.audioUnit);XCTAssertEqual(result.plugin,effect.plugin)
    }
}
