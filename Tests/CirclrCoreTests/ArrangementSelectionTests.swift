import XCTest
@testable import CirclrCore

final class ArrangementSelectionTests:XCTestCase {
    func fixture()throws->(Project,ID) {
        var p=try AlbumTests().legacySong();p.arrangements[0].name="도시의 밤"
        ProjectEditing.duplicateArrangement(in:&p,name:"도시의 밤")
        ProjectEditing.duplicateArrangement(in:&p,name:"긴 대안 · 夜の街 · Nordic reprise")
        p.enableAlbum();let owner=try XCTUnwrap(p.album?.compositions.first?.id)
        _ = try AlbumEditing.add(name:"다른 곡",kind:.song,in:&p)
        return (p,owner)
    }
    func testCatalogUsesDeclaredOwnerOrderAndDistinguishesSameNames()throws {
        var (p,owner)=try fixture();p.album!.compositions[0].arrangementIDs.reverse()
        let rows=try ArrangementSelection.catalog(p,compositionID:owner)
        XCTAssertEqual(rows.map(\.id),p.album!.compositions[0].arrangementIDs)
        XCTAssertEqual(rows.map(\.ordinal),[1,2,3]);XCTAssertEqual(Set(rows.map(\.id)).count,3)
        XCTAssertTrue(rows[1].title.hasPrefix("#2 · "));XCTAssertEqual(rows[1].name,rows[2].name)
        XCTAssertEqual(rows.map(\.sectionCount),[1,1,1])
    }
    func testUnicodeExactOrdinalAndNameTerms()throws {
        let (p,owner)=try fixture(),rows=try ArrangementSelection.catalog(p,compositionID:owner)
        XCTAssertEqual(ArrangementSelection.search(rows,query:"도시의 밤".decomposedStringWithCanonicalMapping).count,2)
        XCTAssertEqual(ArrangementSelection.search(rows,query:"#２").map(\.id),[rows[1].id])
        XCTAssertEqual(ArrangementSelection.search(rows,query:"ＮＯＲＤＩＣ 夜").map(\.id),[rows[2].id])
        XCTAssertTrue(ArrangementSelection.search(rows,query:"#0").isEmpty)
        XCTAssertTrue(ArrangementSelection.search(rows,query:"#four").isEmpty)
        XCTAssertTrue(ArrangementSelection.search(rows,query:"#1 Nordic").isEmpty)
    }
    func testSelectionOnlyChangesOwnerPlaybackChoiceAndActiveArrangement()throws {
        var (p,owner)=try fixture();let before=p,id=p.album!.composition(owner)!.arrangementIDs[0]
        XCTAssertTrue(try ArrangementSelection.select(id,compositionID:owner,in:&p))
        var expected=before;expected.activeArrangementID=id;expected.album!.compositions[0].selectedArrangementID=id
        XCTAssertEqual(p,expected)
    }
    func testSamePlaybackSelectionPreservesDifferentViewingArrangement()throws {
        var (p,owner)=try fixture();let node=p.album!.composition(owner)!
        p.activeArrangementID=node.arrangementIDs[0];let before=p
        XCTAssertFalse(try ArrangementSelection.select(node.selectedArrangementID!,compositionID:owner,in:&p))
        XCTAssertEqual(p,before)
    }
    func testForeignMissingAndContainerOwnersRejectWithoutChangingMusic()throws {
        var (p,owner)=try fixture();let before=p,foreign=p.album!.compositions[1].selectedArrangementID!
        XCTAssertThrowsError(try ArrangementSelection.select(foreign,compositionID:owner,in:&p));XCTAssertEqual(p,before)
        XCTAssertThrowsError(try ArrangementSelection.select("missing",compositionID:owner,in:&p));XCTAssertEqual(p,before)
        XCTAssertThrowsError(try ArrangementSelection.catalog(p,compositionID:"missing"))
        _ = try AlbumEditing.wrapContents(of:owner,name:"악장",in:&p)
        XCTAssertThrowsError(try ArrangementSelection.catalog(p,compositionID:owner))
    }
    func testManyChoicesKeepOrdinalsAndMissingReferencesFailClosed()throws {
        var p=try AlbumTests().legacySong()
        for i in 2...65 {ProjectEditing.duplicateArrangement(in:&p,name:"편곡 \(i)")}
        p.enableAlbum();let owner=p.album!.compositions[0].id
        let rows=try ArrangementSelection.catalog(p,compositionID:owner)
        XCTAssertEqual(rows.count,65);XCTAssertEqual(ArrangementSelection.search(rows,query:"#1").map(\.id),[rows[0].id])
        XCTAssertEqual(ArrangementSelection.search(rows,query:"#65").map(\.id),[rows[64].id])
        p.album!.compositions[0].arrangementIDs.append("missing")
        XCTAssertThrowsError(try ArrangementSelection.catalog(p,compositionID:owner))
    }
}
