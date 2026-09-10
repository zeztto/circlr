import XCTest
@testable import CirclrCore

final class SustainWorkspaceStateTests:XCTestCase {
    func testOpeningEmptySourceDoesNotCreateMusicOrSelection()throws {
        let source:MIDISustainSequence?=nil,state=SustainWorkspaceState()
        XCTAssertNil(source);XCTAssertEqual(state.reconciled(from:source,to:source),state)
        XCTAssertEqual(try JSONDecoder().decode(SustainWorkspaceState.self,from:JSONEncoder().encode(state)),state)
    }
    func testSourceChangeInvalidatesPositionalSelectionButRetainsViewport() {
        let source=MIDISustainSequence(events:[.init(beat:1,rawValue:0),.init(beat:1,rawValue:127)])
        let state=SustainWorkspaceState(selectedIndex:1,displayedBeats:16)
        XCTAssertEqual(state.reconciled(from:source,to:source),state)
        var changed=source;changed.events[0].rawValue=63
        let reconciled=state.reconciled(from:source,to:changed)
        XCTAssertNil(reconciled.selectedIndex);XCTAssertEqual(reconciled.displayedBeats,16)
        XCTAssertNil(state.reconciled(from:source,to:nil).selectedIndex)
    }
    func testInvalidSelectionAndViewportAreNormalized() {
        for index in [-1,100000,Int.max] {XCTAssertNil(SustainWorkspaceState(selectedIndex:index).validated().selectedIndex)}
        XCTAssertNil(SustainWorkspaceState(selectedIndex:1).validated(count:1).selectedIndex)
        XCTAssertEqual(SustainWorkspaceState(selectedIndex:0).validated(count:1).selectedIndex,0)
        for beat in [0,-1,131073,Double.nan,Double.infinity] {XCTAssertNil(SustainWorkspaceState(displayedBeats:beat).validated().displayedBeats)}
        XCTAssertEqual(SustainWorkspaceState(displayedBeats:131072).validated().displayedBeats,131072)
    }
}
