import XCTest
@testable import CirclrCore

final class AgentSoundCatalogTests:XCTestCase {
    func fixture(state:Data?=nil)throws->AgentSoundCatalog {
        let plugins=[AudioUnitCatalogEntry(descriptor:PluginDescriptor(name:"Shared",type:SoundSelection.instrumentType,subtype:1,manufacturer:2,state:state),manufacturerName:"Maker"),
                     AudioUnitCatalogEntry(descriptor:PluginDescriptor(name:"Shared",type:SoundSelection.effectType,subtype:1,manufacturer:2,state:state),manufacturerName:"Maker")]
        let bank=[SoundBankPreset(name:"E.Piano",program:4,bankLSB:0,drums:false)!,SoundBankPreset(name:"E.Piano v",program:4,bankLSB:16,drums:false)!,SoundBankPreset(name:"Kit",program:25,bankLSB:0,drums:true)!]
        return try AgentSoundCatalog(instruments:SoundSelection.instruments(plugins,bank:bank),effects:SoundSelection.effects(plugins))
    }
    func testPageTraversalIsCompleteStableAndBounded()throws {
        let catalog=try fixture();var args=AgentArguments();args.limit=3
        var ids=[String](),pages=0
        repeat {
            let page=try catalog.page(args);pages+=1;XCTAssertLessThanOrEqual(page.items.count,3)
            XCTAssertEqual(page.total,14);XCTAssertEqual(page.catalogID,catalog.id)
            ids+=page.items.map(\.id);args.offset=page.nextOffset;args.catalogID=page.catalogID
        }while args.offset != nil
        XCTAssertEqual(pages,5);XCTAssertEqual(Set(ids).count,14)
        XCTAssertEqual(ids,try catalog.page(AgentArguments()).items.map(\.id))
        args.offset=1_000_000;let empty=try catalog.page(args)
        XCTAssertTrue(empty.items.isEmpty);XCTAssertNil(empty.nextOffset);XCTAssertEqual(empty.total,14)
    }
    func testNamesNumbersUnicodeAndTypedFiltersMatchGUI()throws {
        let catalog=try fixture();var args=AgentArguments();args.query="피아노".decomposedStringWithCanonicalMapping;args.category="soundBank"
        XCTAssertEqual(try catalog.page(args).items.map(\.id),["bank:melodic:4:0","bank:melodic:4:16"])
        args.query="#５";XCTAssertEqual(try catalog.page(args).total,2)
        args.query="#26";args.bankDrums=true
        let kit=try XCTUnwrap(catalog.page(args).items.first);XCTAssertEqual(kit.program,25);XCTAssertEqual(kit.bankLSB,0);XCTAssertEqual(kit.drums,true)
        args.bankDrums=false;XCTAssertEqual(try catalog.page(args).total,0)
        args=AgentArguments();args.query="ｍａｋｅｒ";args.soundTarget="effect"
        let effect=try XCTUnwrap(catalog.page(args).items.first);XCTAssertEqual(effect.plugin?.type,SoundSelection.effectType)
        args.soundTarget="instrument";XCTAssertNotEqual(try catalog.page(args).items.first?.id,effect.id)
    }
    func testPublicMetadataDoesNotExposePluginStateAndDetectsCatalogChanges()throws {
        let first=try fixture(),withState=try fixture(state:Data("secret plugin state".utf8))
        XCTAssertEqual(first.id,withState.id);XCTAssertEqual(first.id.count,64)
        let page=try withState.page(AgentArguments());XCTAssertNil(page.items.last?.plugin?.state)
        let encoded=String(decoding:try JSONEncoder().encode(page),as:UTF8.self)
        XCTAssertFalse(encoded.contains("state"));XCTAssertFalse(encoded.contains("path"))
        let unavailable=try AgentSoundCatalog(instruments:[],effects:[],bankNotice:"은행 없음")
        XCTAssertNotEqual(unavailable.id,first.id);XCTAssertEqual(try unavailable.page(AgentArguments()).notices,["은행 없음"])
        var args=AgentArguments();args.catalogID=first.id;XCTAssertThrowsError(try unavailable.page(args)){XCTAssertTrue($0.localizedDescription.contains("stale_catalog"))}
        args=AgentArguments();args.soundTarget="effect";XCTAssertTrue(try unavailable.page(args).notices.isEmpty)
    }
    func testInvalidQueriesAreRejectedAtNativeBoundary()throws {
        let catalog=try fixture()
        let invalid:[String]=[#"{"soundTarget":"shell"}"#,#"{"category":"sampler"}"#,#"{"soundTarget":"effect","category":"synth"}"#,#"{"soundTarget":"effect","bankDrums":false}"#,#"{"category":"synth","bankDrums":true}"#,#"{"category":"effect"}"#,#"{"limit":0}"#,#"{"limit":129}"#,#"{"offset":-1}"#,#"{"offset":1000001}"#]
        for json in invalid {let args=try JSONDecoder().decode(AgentArguments.self,from:Data(json.utf8));XCTAssertThrowsError(try catalog.page(args),json)}
        var args=AgentArguments();args.query=String(repeating:"a",count:257);XCTAssertThrowsError(try catalog.page(args))
        args.query=String(repeating:"a",count:256);XCTAssertNoThrow(try catalog.page(args))
    }
    func testQueryAndResponseCodableContractAndLegacyArguments()throws {
        let query=Data(##"{"id":"qa","method":"sounds","arguments":{"query":"#5","soundTarget":"instrument","category":"soundBank","bankDrums":false,"offset":0,"limit":1}}"##.utf8)
        let request=try JSONDecoder().decode(AgentRequest.self,from:query),catalog=try fixture()
        let page=try catalog.page(XCTUnwrap(request.arguments))
        XCTAssertEqual(page.schema,"circlr-sounds-v1");XCTAssertEqual(page.nextOffset,1)
        XCTAssertEqual(page,try JSONDecoder().decode(AgentSoundPage.self,from:JSONEncoder().encode(page)))
        let old=try JSONDecoder().decode(AgentArguments.self,from:Data(#"{"useID":"existing"}"#.utf8))
        XCTAssertNil(old.query);XCTAssertEqual(old.useID,"existing")
    }
    func testReturnedBankAddressCanBeMergedIntoAtomicInstrumentEdit()throws {
        let catalog=try fixture();var args=AgentArguments();args.query="E.Piano v"
        let result=try XCTUnwrap(catalog.page(args).items.first)
        var project=try AgentTests().project();project.tracks[0].instrument = .synthesizer(.electricPiano);project.tracks[0].instrument.synth?.cutoff=731
        let before=project;var instrument=project.tracks[0].instrument
        instrument.kind = .soundBank;instrument.program=try XCTUnwrap(result.program);instrument.bankLSB=result.bankLSB;instrument.drums=try XCTUnwrap(result.drums)
        var op=AgentOperation("set_instrument");op.trackID=project.tracks[0].id;op.instrument=instrument
        let changed=try AgentProjectEditing.apply(AgentTests().request(project,[op]),to:project)
        XCTAssertEqual(changed.tracks[0].instrument.bankLSB,16);XCTAssertEqual(changed.tracks[0].instrument.synth,before.tracks[0].instrument.synth)
        XCTAssertEqual(changed.sections,before.sections);XCTAssertEqual(changed.arrangements,before.arrangements);XCTAssertEqual(project,before)
    }
}
