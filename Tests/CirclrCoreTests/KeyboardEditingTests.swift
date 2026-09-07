import XCTest
@testable import CirclrCore

final class KeyboardEditingTests:XCTestCase {
    func testNoteMovesPreserveIdentityAndOtherProperties() {
        let note=Note(beat:1,length:0.5,pitch:66,velocity:87)
        let moved=KeyboardEditing.changed(note,by:.time(0.25),beats:8)
        XCTAssertEqual(moved.id,note.id);XCTAssertEqual(moved.beat,1.25)
        XCTAssertEqual(moved.pitch,66);XCTAssertEqual(moved.length,0.5);XCTAssertEqual(moved.velocity,87)
    }
    func testTimeAndLengthStopAtSectionBoundaries() {
        let note=Note(beat:2.5,length:0.5,pitch:66)
        XCTAssertEqual(KeyboardEditing.changed(note,by:.time(5),beats:3).beat,2.5)
        XCTAssertEqual(KeyboardEditing.changed(note,by:.time(-5),beats:3).beat,0)
        XCTAssertEqual(KeyboardEditing.changed(note,by:.length(5),beats:3).length,0.5)
        XCTAssertGreaterThan(KeyboardEditing.changed(note,by:.length(-5),beats:3).length,0)
    }
    func testPitchVelocityBoundsAndInvalidDeltas() {
        let note=Note(beat:0,length:1,pitch:125,velocity:3)
        XCTAssertEqual(KeyboardEditing.changed(note,by:.pitch(12),beats:4).pitch,127)
        XCTAssertEqual(KeyboardEditing.changed(note,by:.velocity(-10),beats:4).velocity,1)
        XCTAssertEqual(KeyboardEditing.changed(note,by:.time(.nan),beats:4),note)
        XCTAssertEqual(KeyboardEditing.changed(note,by:.length(1),beats:.infinity),note)
    }
}
