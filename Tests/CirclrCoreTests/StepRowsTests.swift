import XCTest
@testable import CirclrCore

final class StepRowsTests:XCTestCase {
    func testCatalogCombinesObservedMappedAndAddedPitchesWithoutInvalidOrDuplicateRows() {
        XCTAssertEqual(StepRows.pitches(observed:[42,36,42,-1],mapped:[38,36,128],extra:[0,127,38],fallback:60),[0,36,38,42,127])
        XCTAssertEqual(StepRows.pitches(observed:[],mapped:[],extra:[],fallback:36),[36])
        XCTAssertEqual(StepRows.pitches(observed:[-10],mapped:[200],extra:[],fallback:Int.max),[127])
        XCTAssertEqual(StepRows.pitches(observed:[],mapped:[],extra:[],fallback:Int.min),[0])
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
