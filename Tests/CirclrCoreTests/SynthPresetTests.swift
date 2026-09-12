import XCTest
@testable import CirclrCore

final class SynthPresetTests:XCTestCase {
    func testCatalogValidityCoverageDistinctnessAndRoundTrip()throws {
        let presets=SynthPreset.factory
        XCTAssertEqual(presets.count,12)
        XCTAssertEqual(Set(presets.map(\.id)).count,presets.count)
        XCTAssertEqual(Set(presets.map(\.name)).count,presets.count)
        XCTAssertEqual(Set(presets.map{$0.patch.voice.rawValue}),Set(SynthVoice.allCases.map(\.rawValue)))
        for (index,preset) in presets.enumerated() {
            try preset.patch.validate()
            XCTAssertEqual(preset.patch.engineVersion,3)
            XCTAssertTrue(presets.dropFirst(index+1).allSatisfy{$0.patch != preset.patch})
            let restored=try JSONDecoder().decode(SynthPatch.self,from:JSONEncoder().encode(preset.patch))
            XCTAssertEqual(restored,preset.patch)
            XCTAssertEqual(SynthPreset.matching(restored)?.id,preset.id)
        }
    }
    func testExplicitSelectionPreservesOtherInstrumentFieldsAndCustomLegacyPatch()throws {
        let catalog=SoundSelection.instruments([])
        var old=Instrument.synthesizer(.pad)
        old.synth?.engineVersion=1;old.synth?.cutoff=931;old.program=42;old.drums=true
        XCTAssertNil(SynthPreset.matching(old.synth!))
        XCTAssertEqual(try SoundSelection.instrument(.synth(.pad),current:old,catalog:catalog),old)
        let preset=SynthPreset.factory[7]
        let selected=try SoundSelection.instrument(.synthPreset(preset.id),current:old,catalog:catalog)
        XCTAssertEqual(selected.synth,preset.patch)
        XCTAssertEqual(selected.program,42);XCTAssertTrue(selected.drums)
        XCTAssertEqual(SoundSelection.choice(in:selected),.synthPreset(preset.id))
        XCTAssertEqual(try SoundSelection.instrument(.synthPreset(preset.id),current:selected,catalog:catalog),selected)
        XCTAssertThrowsError(try SoundSelection.instrument(.synthPreset("missing"),current:old,catalog:catalog))
        var customized=selected;customized.synth?.cutoff += 1
        XCTAssertNil(SynthPreset.matching(customized.synth!))
    }
    func testBaseVoiceSelectionResetsExactFactoryButPreservesCustomizedFactory()throws {
        let catalog=SoundSelection.instruments([])
        for preset in SynthPreset.factory {
            var current=Instrument.synthesizer(preset.patch.voice)
            current.synth=preset.patch;current.program=42
            let choice=SoundChoice.synth(preset.patch.voice)
            let base=try SoundSelection.instrument(choice,current:current,catalog:catalog)
            XCTAssertEqual(base.synth,SynthPatch(preset.patch.voice))
            XCTAssertEqual(SoundSelection.choice(in:base),choice)
            XCTAssertEqual(base.program,42)
            current.synth?.cutoff += 1
            XCTAssertEqual(try SoundSelection.instrument(choice,current:current,catalog:catalog),current)
        }
    }
    func testSearchAndAgentPageExposeExactApplicablePatch()throws {
        let entries=SoundSelection.instruments([])
        XCTAssertEqual(SoundSelection.search(entries,query:"벨벳 전자피아노").map(\.id),[.synthPreset("velvet-ep")])
        let catalog=try AgentSoundCatalog(instruments:entries,effects:[])
        var args=AgentArguments();args.query="벨벳 전자피아노"
        let page=try catalog.page(args)
        let item=try XCTUnwrap(page.items.first)
        XCTAssertEqual(item.id,"synth-preset:velvet-ep")
        XCTAssertEqual(item.synthPatch,SynthPreset.factory.first{$0.id=="velvet-ep"}?.patch)
        XCTAssertEqual(item.synthVoice,.electricPiano)
    }
    func testCatalogPatchAppliesThroughAgentAndHistoryRestoresLegacySound()throws {
        var project=try AgentTests().project()
        project.tracks[0].instrument = .synthesizer(.pad)
        project.tracks[0].instrument.synth?.engineVersion=1
        project.tracks[0].instrument.synth?.cutoff=931
        let before=project,preset=SynthPreset.factory[8]
        var instrument=project.tracks[0].instrument;instrument.synth=preset.patch
        var operation=AgentOperation("set_instrument")
        operation.trackID=project.tracks[0].id;operation.instrument=instrument
        let changed=try AgentProjectEditing.apply(AgentTests().request(project,[operation]),to:project)
        XCTAssertEqual(changed.tracks[0].instrument.synth,preset.patch)
        var restored=try CircleHistory.restore(before,layoutOnly:false,current:changed)
        restored.musicRevision=before.musicRevision
        XCTAssertEqual(restored,before)
    }

}
