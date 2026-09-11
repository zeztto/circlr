import XCTest
@testable import CirclrCore

final class StepRowsTests:XCTestCase {
    func testCatalogCombinesObservedMappedAndAddedPitchesWithoutInvalidOrDuplicateRows() {
        XCTAssertEqual(StepRows.pitches(observed:[42,36,42,-1],mapped:[38,36,128],extra:[0,127,38],fallback:60),[0,36,38,42,127])
        XCTAssertEqual(StepRows.pitches(observed:[],mapped:[],extra:[],fallback:36),[36])
        XCTAssertEqual(StepRows.pitches(observed:[-10],mapped:[200],extra:[],fallback:Int.max),[127])
        XCTAssertEqual(StepRows.pitches(observed:[],mapped:[],extra:[],fallback:Int.min),[0])
    }
    func testDefaultDrumRowsRemainVisibleAfterFirstNoteAndPreserveCustomPitches() {
        let defaults=Array(StepRows.generalMIDIDrumNames.keys)
        let empty=StepRows.pitches(observed:[],mapped:[],extra:[],fallback:36,defaults:defaults)
        XCTAssertEqual(empty,[36,38,39,42,45,46,49,51])
        XCTAssertEqual(StepRows.pitches(observed:[36],mapped:[],extra:[],fallback:36,defaults:defaults),empty)
        XCTAssertEqual(StepRows.pitches(observed:[60],mapped:[35],extra:[127],fallback:36,defaults:defaults),[35,36,38,39,42,45,46,49,51,60,127])
        XCTAssertEqual(StepRows.pitches(observed:[],mapped:[12,16],extra:[],fallback:36),[12,16])
    }
    func testOnlyTheActiveInstrumentContributesMappedAndDefaultRows() {
        var instrument=Instrument(drums:true)
        instrument.sample=SampleInstrument(assetID:"kept",rootPitch:12)
        instrument.sample?.zones=[SampleZone(12,assetID:"kept")]
        XCTAssertEqual(StepRows.pitches(instrument:instrument,observed:[],extra:[]),[36,38,39,42,45,46,49,51])
        instrument.kind = .sampler
        XCTAssertEqual(StepRows.pitches(instrument:instrument,observed:[60],extra:[]),[12,60])
        instrument.kind = .synthesizer
        XCTAssertEqual(StepRows.pitches(instrument:instrument,observed:[],extra:[]),[36])
        instrument.kind = .soundBank;instrument.drums=false
        XCTAssertEqual(StepRows.pitches(instrument:instrument,observed:[64],extra:[]),[64])
    }
    func testSearchMatchesCurrentNamesNumbersUnicodeAndCommonAccidentalNotation() {
        let rows=[StepRow(pitch:36,label:"36 · 킥"),StepRow(pitch:38,label:"Café Snare"),StepRow(pitch:61,label:"C♯4"),StepRow(pitch:63,label:"E♭4")]
        XCTAssertEqual(StepRows.filter(rows,query:"킥").map(\.pitch),[36])
        XCTAssertEqual(StepRows.filter(rows,query:"３８ CAFE").map(\.pitch),[38])
        XCTAssertEqual(StepRows.filter(rows,query:"c#4").map(\.pitch),[61])
        XCTAssertEqual(StepRows.filter(rows,query:"eb4").map(\.pitch),[63])
        XCTAssertEqual(StepRows.filter(rows,query:"킥 38"),[])
    }
    func testAllQueryTermsMustMatchOneRowAndBlankSearchKeepsTheCatalogOrder() {
        let rows=[StepRow(pitch:42,label:"Closed Hat 01"),StepRow(pitch:46,label:"Open Hat 02"),StepRow(pitch:60,label:"여름밤 🎹")]
        XCTAssertEqual(StepRows.filter(rows,query:" HAT\t02 ").map(\.pitch),[46])
        XCTAssertEqual(StepRows.filter(rows,query:"여름밤 🎹").map(\.pitch),[60])
        XCTAssertEqual(StepRows.filter(rows,query:" \n\t "),rows)
        XCTAssertEqual(StepRows.filter(rows,query:"없는 이름"),[])
    }
}
