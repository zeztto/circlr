import XCTest
@testable import CirclrCore

final class PitchBendSelectionSafetyTests:XCTestCase {
    private let selected=PitchBendWorkspaceState(selectedIndex:1,displayedBeats:64)
    private var source:MIDIPitchBendSequence {.init(events:[.init(beat:1,kind:.value(9000)),.init(beat:2,kind:.range(.init(semitones:12)))])}
    func testUnchangedSourceRetainsSelectionAndViewport() {
        XCTAssertEqual(selected.reconciled(from:source,to:source),selected)
    }
    func testInsertionRemovalReorderAndInitialChangesClearOnlySelection() {
        var inserted=source;inserted.events.insert(.init(beat:0,kind:.value(8192)),at:0)
        var removed=source;removed.events.removeFirst()
        var reordered=source;reordered.events.reverse()
        var seed=source;seed.initialRange = .init(semitones:24)
        for candidate in [inserted,removed,reordered,seed] {
            XCTAssertEqual(selected.reconciled(from:source,to:candidate),.init(displayedBeats:64))
        }
        XCTAssertEqual(selected.reconciled(from:source,to:nil),.init(displayedBeats:64))
    }
    func testIdenticalEventAtSameIndexDoesNotProveSourceIdentity() {
        let duplicate=MIDIPitchBendEvent(beat:1,kind:.value(8192))
        let before=MIDIPitchBendSequence(events:[duplicate,duplicate])
        let after=MIDIPitchBendSequence(events:[duplicate,duplicate,duplicate])
        XCTAssertNil(selected.reconciled(from:before,to:after).selectedIndex)
    }
    func testMissingOrOutOfRangeSelectionCleared() {
        XCTAssertNil(selected.reconciled(from:nil,to:nil).selectedIndex)
        XCTAssertNil(PitchBendWorkspaceState(selectedIndex:8).reconciled(from:source,to:source).selectedIndex)
    }
}
