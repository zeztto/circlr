import XCTest
@testable import CirclrCore

final class MIDIPitchBendEditingTests:XCTestCase {
    private func event(_ beat:Double,_ value:Int)->MIDIPitchBendEvent {.init(beat:beat,kind:.value(value))}
    func testInsertAndValueUpdatePreserveSameBeatOrder()throws {
        let source=MIDIPitchBendSequence(events:[event(1,1),event(1,2),event(3,3)])
        let inserted=try MIDIPitchBendEditing.apply(.insert(event(1,4)),to:source)
        XCTAssertEqual(inserted.selectedIndex,2)
        XCTAssertEqual(inserted.sequence?.events,[event(1,1),event(1,2),event(1,4),event(3,3)])
        let updated=try MIDIPitchBendEditing.apply(.update(index:0,event:event(1,5)),to:source)
        XCTAssertEqual(updated.selectedIndex,0);XCTAssertEqual(updated.sequence?.events,[event(1,5),event(1,2),event(3,3)])
        XCTAssertEqual(source.events,[event(1,1),event(1,2),event(3,3)])
    }
    func testBeatMovesInsertAfterDestinationTiesAndReturnNewIndex()throws {
        let source=MIDIPitchBendSequence(events:[event(1,1),event(2,2),event(2,3),event(4,4)])
        let forward=try MIDIPitchBendEditing.apply(.update(index:0,event:event(2,1)),to:source)
        XCTAssertEqual(forward.selectedIndex,2);XCTAssertEqual(forward.sequence?.events,[event(2,2),event(2,3),event(2,1),event(4,4)])
        let backward=try MIDIPitchBendEditing.apply(.update(index:3,event:event(2,4)),to:source)
        XCTAssertEqual(backward.selectedIndex,3);XCTAssertEqual(backward.sequence?.events,[event(1,1),event(2,2),event(2,3),event(2,4)])
        let first=try MIDIPitchBendEditing.apply(.update(index:3,event:event(0,4)),to:source)
        XCTAssertEqual(first.selectedIndex,0)
    }
    func testSeedCreationLastRemovalAndClearRemainDistinct()throws {
        let seeded=try MIDIPitchBendEditing.apply(.setInitial(channel:15,value:10000,range:.init(semitones:12,cents:127)),to:nil)
        XCTAssertNil(seeded.selectedIndex);XCTAssertEqual(seeded.sequence?.initialValue,10000)
        let added=try MIDIPitchBendEditing.apply(.insert(event(131072,16383)),to:seeded.sequence)
        let removed=try MIDIPitchBendEditing.apply(.remove(index:0),to:added.sequence)
        XCTAssertEqual(removed.sequence,seeded.sequence);XCTAssertNil(removed.selectedIndex)
        let cleared=try MIDIPitchBendEditing.apply(.clear,to:removed.sequence)
        XCTAssertNil(cleared.sequence);XCTAssertNil(cleared.selectedIndex)
        XCTAssertNil(try MIDIPitchBendEditing.apply(.clear,to:nil).sequence)
        XCTAssertEqual(try MIDIPitchBendEditing.apply(.insert(event(0,0)),to:nil).sequence?.initialValue,8192)
    }
    func testInvalidEditsAndMalformedSourceAreRejectedWithoutChangingInput()throws {
        let source=MIDIPitchBendSequence(events:[event(1,1)])
        let bad:[MIDIPitchBendEditing.Change]=[.insert(event(.nan,0)),.insert(event(.infinity,0)),.insert(event(-1,0)),.insert(event(131073,0)),.insert(event(1,16384)),.update(index:-1,event:event(0,0)),.update(index:1,event:event(0,0)),.remove(index:1),.setInitial(channel:16,value:8192,range:.init()),.setInitial(channel:0,value:-1,range:.init()),.setInitial(channel:0,value:8192,range:.init(cents:128))]
        for change in bad {XCTAssertThrowsError(try MIDIPitchBendEditing.apply(change,to:source))}
        XCTAssertEqual(source.events,[event(1,1)])
        XCTAssertThrowsError(try MIDIPitchBendEditing.apply(.update(index:0,event:event(0,0)),to:nil))
        XCTAssertThrowsError(try MIDIPitchBendEditing.apply(.remove(index:0),to:nil))
        let malformed=MIDIPitchBendSequence(events:[event(2,0),event(1,0)])
        XCTAssertThrowsError(try MIDIPitchBendEditing.apply(.clear,to:malformed))
        XCTAssertThrowsError(try MIDIPitchBendEditing.apply(.update(index:1,event:event(3,0)),to:malformed))
    }
    func testCountLimitAndCodableChanges()throws {
        let full=MIDIPitchBendSequence(events:Array(repeating:event(0,8192),count:100000))
        XCTAssertThrowsError(try MIDIPitchBendEditing.apply(.insert(event(1,0)),to:full))
        XCTAssertEqual(try MIDIPitchBendEditing.apply(.update(index:99999,event:event(131072,0)),to:full).selectedIndex,99999)
        XCTAssertEqual(try MIDIPitchBendEditing.apply(.remove(index:0),to:full).sequence?.events.count,99999)
        let changes:[MIDIPitchBendEditing.Change]=[.insert(event(0,0)),.update(index:2,event:.init(beat:4,kind:.range(.init(semitones:127,cents:127)))),.remove(index:1),.setInitial(channel:0,value:8192,range:.init()),.clear]
        for change in changes {XCTAssertEqual(try JSONDecoder().decode(MIDIPitchBendEditing.Change.self,from:JSONEncoder().encode(change)),change)}
    }
}
