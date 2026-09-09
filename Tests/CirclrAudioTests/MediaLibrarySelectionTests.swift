import XCTest
@testable import CirclrAudio

final class MediaLibrarySelectionTests:XCTestCase {
    func entry(_ name:String,_ kind:LibraryMediaKind = .audio,_ bytes:Int64=1024,folder:String="f")->LibraryEntry {
        LibraryEntry(folderID:folder,folderName:folder,relativePath:name,kind:kind,bytes:bytes,modified:Date(timeIntervalSince1970:0))
    }
    func testRangeExtendsAndShrinksInEitherDirection()throws {
        let ids=["a","b","c","d"]
        XCTAssertEqual(try MediaLibrarySelection.range(ids,anchor:"b",target:"d"),["b","c","d"])
        XCTAssertEqual(try MediaLibrarySelection.range(ids,anchor:"b",target:"c"),["b","c"])
        XCTAssertEqual(try MediaLibrarySelection.range(ids,anchor:"d",target:"b"),["b","c","d"])
        XCTAssertEqual(try MediaLibrarySelection.range(ids,anchor:"missing",target:"c"),["c"])
        XCTAssertThrowsError(try MediaLibrarySelection.range(ids,anchor:"b",target:"missing"))
    }
    func testLimitRejectsWholeChangeAndToggleCanRemoveAtLimit()throws {
        let ids=(0..<65).map(String.init),selected=Set(ids.prefix(64))
        XCTAssertEqual(try MediaLibrarySelection.range(ids,anchor:"0",target:"63"),selected)
        XCTAssertThrowsError(try MediaLibrarySelection.range(ids,anchor:"0",target:"64"))
        XCTAssertThrowsError(try MediaLibrarySelection.toggling("64",in:selected))
        XCTAssertEqual(try MediaLibrarySelection.toggling("0",in:selected),selected.subtracting(["0"]))
    }
    func testVisibleSelectionKeepsDisplayOrderAndDistinctFolders()throws {
        let a=entry("kick.wav",folder:"a"),b=entry("kick.wav",folder:"b"),c=entry("pad.wav")
        XCTAssertEqual(try MediaLibrarySelection.entries([c,b,a],ids:[a.id,b.id]),[b,a])
        XCTAssertThrowsError(try MediaLibrarySelection.entries([a],ids:[a.id,b.id]))
        XCTAssertThrowsError(try MediaLibrarySelection.entries([a,a],ids:[a.id]))
        XCTAssertThrowsError(try MediaLibrarySelection.entries([a],ids:[]))
    }
    func testMIDIAndMixedBatchesAreNeverPartiallyAccepted()throws {
        let a=entry("a.wav"),m=entry("a.mid",.midi),n=entry("b.mid",.midi)
        XCTAssertNoThrow(try MediaLibrarySelection.validate([a]));XCTAssertNoThrow(try MediaLibrarySelection.validate([m]))
        XCTAssertThrowsError(try MediaLibrarySelection.validate([a,m]));XCTAssertThrowsError(try MediaLibrarySelection.validate([m,n]))
        XCTAssertThrowsError(try MediaLibrarySelection.validate([entry("huge.mid",.midi,16_777_217)]))
    }
    func testBatchAndFileByteBoundsCannotOverflow()throws {
        XCTAssertNoThrow(try MediaLibrarySelection.validate([entry("a.wav",.audio,2_147_483_648),entry("b.wav",.audio,2_147_483_648)]))
        XCTAssertThrowsError(try MediaLibrarySelection.validate([entry("a.wav",.audio,2_147_483_648),entry("b.wav",.audio,2_147_483_648),entry("c.wav",.audio,1)]))
        for bytes in [Int64.min,0,2_147_483_649,Int64.max] {XCTAssertThrowsError(try MediaLibrarySelection.validate([entry("a.wav",.audio,bytes)]))}
        let a=entry("a.wav");XCTAssertThrowsError(try MediaLibrarySelection.validate([a,a]));XCTAssertThrowsError(try MediaLibrarySelection.validate([]))
    }
}
