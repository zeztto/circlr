import XCTest
@testable import CirclrCore

final class MIDISustainEditingTests:XCTestCase {
    func testInsertAfterSameBeatAndUpdateValueRetainsReleaseOrder()throws {
        let source=MIDISustainSequence(channel:3,events:[.init(beat:1,rawValue:127),.init(beat:1,rawValue:0),.init(beat:2,rawValue:64)])
        let inserted=try MIDISustainEditing.apply(.insert(.init(beat:1,rawValue:63)),to:source)
        XCTAssertEqual(inserted.selectedIndex,2);XCTAssertEqual(inserted.sequence?.events.map(\.rawValue),[127,0,63,64])
        let changed=try MIDISustainEditing.apply(.update(index:1,event:.init(beat:1,rawValue:1)),to:inserted.sequence)
        XCTAssertEqual(changed.selectedIndex,1);XCTAssertEqual(changed.sequence?.events.map(\.rawValue),[127,1,63,64])
        XCTAssertEqual(source.events.map(\.rawValue),[127,0,64])
        XCTAssertEqual(changed.sequence?.channel,3)
    }
    func testBeatMoveAppendsAtDestinationAndPreservesOutOfWindowEvents()throws {
        let source=MIDISustainSequence(events:[.init(beat:0,rawValue:127),.init(beat:2,rawValue:0),.init(beat:2,rawValue:127),.init(beat:100,rawValue:0)])
        let changed=try MIDISustainEditing.apply(.update(index:0,event:.init(beat:2,rawValue:64)),to:source)
        XCTAssertEqual(changed.selectedIndex,2)
        XCTAssertEqual(changed.sequence?.events.map(\.rawValue),[0,127,64,0])
        XCTAssertEqual(changed.sequence?.events.last?.beat,100)
        let removed=try MIDISustainEditing.apply(.remove(index:1),to:changed.sequence)
        XCTAssertNil(removed.selectedIndex);XCTAssertEqual(removed.sequence?.events.count,3)
    }
    func testInitialSeedNilClearAndRawBoundaries()throws {
        let seed=try MIDISustainEditing.apply(.setInitial(channel:15,value:127),to:nil)
        XCTAssertEqual(seed.sequence?.channel,15);XCTAssertEqual(seed.sequence?.initialValue,127);XCTAssertNil(seed.selectedIndex)
        let a=try MIDISustainEditing.apply(.insert(.init(beat:131072,rawValue:0)),to:seed.sequence)
        XCTAssertEqual(a.selectedIndex,0)
        XCTAssertNil(try MIDISustainEditing.apply(.clear,to:a.sequence).sequence)
        XCTAssertNil(try MIDISustainEditing.apply(.clear,to:nil).sequence)
        let first=try MIDISustainEditing.apply(.insert(.init(beat:0,rawValue:64)),to:nil)
        XCTAssertEqual(first.sequence?.initialValue,0);XCTAssertEqual(first.sequence?.channel,0)
    }
    func testInvalidEventsIndicesInitialAndCountFailWithoutMutation()throws {
        let source=MIDISustainSequence(events:[.init(beat:0,rawValue:127)])
        let changes:[MIDISustainEditing.Change]=[
            .insert(.init(beat:0,rawValue:128)),.insert(.init(beat:0,rawValue:-1)),.insert(.init(beat:.nan,rawValue:0)),
            .update(index:1,event:.init(beat:0,rawValue:0)),.remove(index:-1),.setInitial(channel:16,value:0),.setInitial(channel:0,value:128)]
        for change in changes {XCTAssertThrowsError(try MIDISustainEditing.apply(change,to:source))}
        XCTAssertEqual(source.events,[.init(beat:0,rawValue:127)])
        XCTAssertThrowsError(try MIDISustainEditing.apply(.remove(index:0),to:nil))
        let full=MIDISustainSequence(events:Array(repeating:.init(beat:0,rawValue:0),count:100000))
        XCTAssertThrowsError(try MIDISustainEditing.apply(.insert(.init(beat:0,rawValue:127)),to:full))
        XCTAssertNoThrow(try MIDISustainEditing.apply(.update(index:99999,event:.init(beat:0,rawValue:127)),to:full))
        var invalid=source;invalid.events[0].rawValue=128
        XCTAssertThrowsError(try MIDISustainEditing.apply(.clear,to:invalid))
    }
}
