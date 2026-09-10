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
    func testOwnedDuplicateUsesExplicitSourceAndPreservesExistingMusic()throws {
        var (p,owner)=try fixture()
        p.arrangements[0].uses[0].repeatCount=3
        let source=p.arrangements[0],before=p
        XCTAssertNotEqual(p.activeArrangementID,source.id)
        let id=try ArrangementSelection.duplicate(source.id,compositionID:owner,name:"  도시의 밤\n",in:&p)
        let copy=try XCTUnwrap(p.arrangements.last)
        XCTAssertEqual(copy.id,id);XCTAssertNotEqual(id,source.id);XCTAssertEqual(copy.name,"도시의 밤")
        XCTAssertEqual(copy.uses.count,source.uses.count)
        for (original,duplicate) in zip(source.uses,copy.uses) {
            XCTAssertNotEqual(original.id,duplicate.id)
            var normalized=duplicate;normalized.id=original.id
            XCTAssertEqual(normalized,original)
        }
        var expected=before
        expected.arrangements.append(copy);expected.activeArrangementID=id
        expected.album!.compositions[0].arrangementIDs.append(id)
        expected.album!.compositions[0].selectedArrangementID=id
        XCTAssertEqual(p,expected)
        try ProjectStore.validateStructure(p)
    }
    func testOwnedRenameOnlyChangesTargetAndSameTrimmedNameIsNoOp()throws {
        var (p,owner)=try fixture();let id=p.arrangements[0].id,before=p
        XCTAssertTrue(try ArrangementSelection.rename(id,compositionID:owner,name:" \n다른 이름  ",in:&p))
        var expected=before;expected.arrangements[0].name="다른 이름"
        XCTAssertEqual(p,expected)
        XCTAssertFalse(try ArrangementSelection.rename(id,compositionID:owner,name:" 다른 이름\n",in:&p))
        XCTAssertEqual(p,expected)
        XCTAssertTrue(try ArrangementSelection.rename(id,compositionID:owner,name:p.arrangements[1].name,in:&p))
        XCTAssertEqual(p.arrangements[0].name,p.arrangements[1].name)
    }
    func testOwnedOperationsRejectForeignMissingAndInvalidNamesAtomically()throws {
        var (p,owner)=try fixture();let before=p,source=p.arrangements[0].id
        let foreign=try XCTUnwrap(p.album!.compositions[1].selectedArrangementID)
        for id in [foreign,"missing"] {
            XCTAssertThrowsError(try ArrangementSelection.duplicate(id,compositionID:owner,name:"대안",in:&p));XCTAssertEqual(p,before)
            XCTAssertThrowsError(try ArrangementSelection.rename(id,compositionID:owner,name:"대안",in:&p));XCTAssertEqual(p,before)
        }
        for name in ["", " \n\t",String(repeating:"가",count:121)] {
            XCTAssertThrowsError(try ArrangementSelection.duplicate(source,compositionID:owner,name:name,in:&p));XCTAssertEqual(p,before)
            XCTAssertThrowsError(try ArrangementSelection.rename(source,compositionID:owner,name:name,in:&p));XCTAssertEqual(p,before)
        }
        let limit=String(repeating:"가",count:120)
        XCTAssertTrue(try ArrangementSelection.rename(source,compositionID:owner,name:limit,in:&p))
        let id=try ArrangementSelection.duplicate(source,compositionID:owner,name:limit,in:&p)
        XCTAssertEqual(p.arrangements.first{$0.id==id}?.name,limit)
    }
    func testOwnedOperationsRejectAmbiguousAndBrokenReferencesAtomically()throws {
        let (valid,owner)=try fixture(),source=valid.arrangements[0].id
        var shared=valid;shared.album!.compositions[1].arrangementIDs.append(source)
        var duplicateID=valid;duplicateID.arrangements.append(valid.arrangements[0])
        var missing=valid;missing.album!.compositions[0].arrangementIDs.append("missing")
        for invalid in [shared,duplicateID,missing] {
            var p=invalid
            XCTAssertThrowsError(try ArrangementSelection.duplicate(source,compositionID:owner,name:"대안",in:&p));XCTAssertEqual(p,invalid)
            XCTAssertThrowsError(try ArrangementSelection.rename(source,compositionID:owner,name:"대안",in:&p));XCTAssertEqual(p,invalid)
        }
    }
    func testOwnedDuplicateCopiesOccurrenceAndGroupColorsWithoutChangingSource()throws {
        var p=try CircleColorTests().fixture()
        let owner=try XCTUnwrap(p.album?.compositions.first?.id),source=p.active
        let use=try XCTUnwrap(source.uses.first)
        let group=CanvasGroup(name:"섹션 묶음",members:[use.id])
        p.arrangements[p.activeIndex].layout.groups=[group]
        let section=CircleAddress.section(arrangementID:source.id,useID:use.id)
        let node=try XCTUnwrap(p.sections.first?.graph?.nodes.first?.id)
        let music=CircleAddress.music(arrangementID:source.id,useID:use.id,nodeID:node)
        var innerGroup=CanvasGroup(name:"오디오 묶음",members:[node]);innerGroup.id="inner"
        p.sections[0].graph?.layout.groups.append(innerGroup)
        let inner=CircleAddress.group(parent:section,id:"inner")
        let outer=CircleAddress.group(parent:.composition(owner),id:group.id)
        p.circleColors=[section:CircleColor.Preset.amber.color,music:CircleColor.Preset.coral.color,inner:CircleColor.Preset.mint.color,outer:CircleColor.Preset.blue.color,.album:CircleColor.Preset.rose.color]
        let before=try XCTUnwrap(p.circleColors)
        let id=try ArrangementSelection.duplicate(source.id,compositionID:owner,name:"색 유지",in:&p)
        let newUse=try XCTUnwrap(p.active.uses.first?.id),newGroup=try XCTUnwrap(p.active.layout.groups.first?.id)
        let newSection=CircleAddress.section(arrangementID:id,useID:newUse)
        var expected=before
        expected[newSection]=before[section]
        expected[.music(arrangementID:id,useID:newUse,nodeID:node)]=before[music]
        expected[.group(parent:newSection,id:"inner")]=before[inner]
        expected[.group(parent:.composition(owner),id:newGroup)]=before[outer]
        XCTAssertEqual(p.circleColors,expected)
        XCTAssertEqual(p.arrangements.first{$0.id==source.id}?.uses,source.uses)
    }
    func testDuplicateMappingUsesExactOccurrenceAndRejectsInventedAddresses() throws {
        var p=try CircleColorTests().fixture()
        let owner=try XCTUnwrap(p.album?.compositions.first?.id),sourceID=p.activeArrangementID
        var second=p.active.uses[0];second.id=newID();second.name=p.active.uses[0].name
        p.arrangements[p.activeIndex].uses.append(second)
        let uses=p.active.uses, node=try XCTUnwrap(p.sections[0].graph?.nodes.first?.id)
        let invalid=CircleAddress.music(arrangementID:sourceID,useID:uses[0].id,nodeID:"deleted")
        p.circleColors=[invalid:CircleColor.Preset.coral.color]
        let before=p
        let result=try ArrangementSelection.duplicateWithMapping(sourceID,compositionID:owner,name:"대안",in:&p)
        XCTAssertEqual(result.arrangementID,p.activeArrangementID)
        for (old,new) in zip(uses,p.active.uses) {
            XCTAssertEqual(result.addressMap[.section(arrangementID:sourceID,useID:old.id)],.section(arrangementID:result.arrangementID,useID:new.id))
            XCTAssertEqual(result.addressMap[.music(arrangementID:sourceID,useID:old.id,nodeID:node)],.music(arrangementID:result.arrangementID,useID:new.id,nodeID:node))
        }
        XCTAssertNil(result.addressMap[invalid])
        XCTAssertNil(result.addressMap[.music(arrangementID:sourceID,useID:"missing",nodeID:node)])
        XCTAssertNil(result.addressMap[.music(arrangementID:"foreign",useID:uses[0].id,nodeID:node)])
        XCTAssertNil(result.addressMap[.group(parent:.section(arrangementID:sourceID,useID:uses[0].id),id:"deleted")])
        XCTAssertEqual(p.circleColors,before.circleColors)
        XCTAssertEqual(p.arrangements.first{$0.id==sourceID},before.active)
        XCTAssertEqual(p.sections,before.sections)
        XCTAssertEqual(p.tracks,before.tracks)
        XCTAssertEqual(p.assets,before.assets)
    }
    func testDuplicateMappingFailureDoesNotPartiallyPublishClone() throws {
        var p=try CircleColorTests().fixture()
        let owner=try XCTUnwrap(p.album?.compositions.first?.id),source=p.activeArrangementID
        p.arrangements[p.activeIndex].uses[0].sectionID="missing"
        let before=p
        XCTAssertThrowsError(try ArrangementSelection.duplicateWithMapping(source,compositionID:owner,name:"대안",in:&p))
        XCTAssertEqual(p,before)
    }

}
