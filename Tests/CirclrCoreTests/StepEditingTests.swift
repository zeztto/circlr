import XCTest
@testable import CirclrCore

final class StepEditingTests:XCTestCase {
    func testSelectedOnsetAddressMatchesOffGridAndFinalPageCells()throws {
        for division in StepGrid.resolutions {
            let grid=try StepGrid(subdivisions:division,beats:9.5)
            for beat in [0,0.03,0.2499999995,4.07,8.5,9.49] {
                let index=try XCTUnwrap(grid.index(at:beat))
                XCTAssertTrue(grid.contains(beat,in:index))
                XCTAssertLessThan(index/16,grid.pageCount)
                XCTAssertLessThan(index%16,16)
            }
            for beat in [-0.1,9.5,.infinity,.nan] {XCTAssertNil(grid.index(at:beat))}
        }
    }
    func testDrumAndPolyphonicSynthUseOrdinaryNotesWithoutDuplication()throws {
        let grid=try StepGrid(beats:4);var lane=Lane(trackID:"synth")
        for pitch in [60,64,67] {lane=try StepEditing.set(lane,grid:grid,index:0,pitch:pitch,enabled:true,velocity:102,gate:4)}
        XCTAssertEqual(lane.notes.map(\.pitch),[60,64,67]);XCTAssertEqual(lane.notes.map(\.length),[1,1,1])
        let previous=lane;lane=try StepEditing.set(lane,grid:grid,index:0,pitch:60,enabled:true);XCTAssertEqual(lane,previous)
        lane=try StepEditing.set(lane,grid:grid,index:0,pitch:64,enabled:false);XCTAssertEqual(lane.notes.map(\.pitch),[60,67])
        var drum=Lane(trackID:"drum")
        for step in [0,4,8,12] {drum=try StepEditing.set(drum,grid:grid,index:step,pitch:36,enabled:true)}
        XCTAssertEqual(drum.notes.map(\.beat),[0,1,2,3]);XCTAssertTrue(drum.notes.allSatisfy{$0.pitch==36 && $0.velocity==96})
    }
    func testResolutionAndNavigationPreserveOffGridTimingAndHeldNotes()throws {
        let grid=try StepGrid(beats:4);var lane=Lane(trackID:"t")
        lane.notes=[Note(beat:0.03,length:1.5,pitch:60,velocity:87),Note(beat:0.12,length:0.1,pitch:60),Note(beat:0.26,length:0.2,pitch:60)]
        let before=lane
        XCTAssertEqual(grid.onsets(in:lane,pitch:60,index:0).count,2)
        let triplet=try StepGrid(subdivisions:3,beats:4);XCTAssertEqual(triplet.onsets(in:lane,pitch:60,index:0).count,3)
        lane=try StepEditing.set(lane,grid:grid,index:0,pitch:60,enabled:true)
        XCTAssertEqual(lane,before)
        lane=try StepEditing.set(lane,grid:grid,index:1,pitch:60,enabled:false)
        XCTAssertEqual(lane.notes,Array(before.notes.prefix(2)))
        let velocity=try StepEditing.set(before,grid:grid,index:0,pitch:60,enabled:true,velocity:110)
        XCTAssertEqual(velocity.notes.map(\.beat),before.notes.map(\.beat));XCTAssertEqual(velocity.notes.map(\.length),before.notes.map(\.length))
        XCTAssertEqual(velocity.notes.map(\.id),before.notes.map(\.id))
    }
    func testPageCopyKeepsAudioOtherPagesAndSourceOffsetsWithFreshIDs()throws {
        let grid=try StepGrid(beats:9);var lane=Lane(trackID:"t")
        lane.notes=[Note(beat:0.07,length:0.6,pitch:60),Note(beat:3.9,length:2,pitch:64),Note(beat:5,length:1,pitch:70),Note(beat:8.5,length:0.4,pitch:72)]
        lane.audio=[AudioClip(assetID:"audio",duration:2)]
        let copy=try StepEditing.copyPage(lane,grid:grid,from:0,to:1)
        XCTAssertEqual(copy.audio,lane.audio);XCTAssertEqual(copy.notes.filter{$0.beat<4},Array(lane.notes.prefix(2)))
        XCTAssertEqual(copy.notes.filter{$0.beat>=4 && $0.beat<8}.map(\.beat),[4.07,7.9])
        XCTAssertEqual(copy.notes.filter{$0.beat>=4 && $0.beat<8}.last!.length,1.1,accuracy:1e-9)
        XCTAssertEqual(Set(copy.notes.map(\.id)).count,copy.notes.count)
        XCTAssertEqual(copy.notes.first{$0.beat==8.5},lane.notes.last)
        let clear=try StepEditing.clearPage(copy,grid:grid,page:1)
        XCTAssertTrue(clear.notes.contains{$0.beat==3.9 && $0.length==2});XCTAssertEqual(clear.audio,lane.audio)
    }
    func testOddMeterFinalStepAndInvalidInputs()throws {
        let grid=try StepGrid(subdivisions:4,beats:3.5)
        XCTAssertEqual(grid.stepCount,14);XCTAssertEqual(grid.pageCount,1)
        let lane=Lane(trackID:"t"),last=try StepEditing.set(lane,grid:grid,index:13,pitch:0,enabled:true,gate:16)
        XCTAssertEqual(last.notes[0].beat,3.25);XCTAssertEqual(last.notes[0].length,0.25)
        XCTAssertThrowsError(try StepEditing.set(lane,grid:grid,index:14,pitch:60,enabled:true))
        XCTAssertThrowsError(try StepEditing.set(lane,grid:grid,index:0,pitch:128,enabled:true))
        XCTAssertThrowsError(try StepEditing.set(lane,grid:grid,index:0,pitch:60,enabled:true,velocity:0))
        XCTAssertThrowsError(try StepEditing.set(lane,grid:grid,index:0,pitch:60,enabled:true,gate:.nan))
        XCTAssertThrowsError(try StepGrid(subdivisions:0,beats:4));XCTAssertThrowsError(try StepGrid(beats:.infinity))
        XCTAssertThrowsError(try StepEditing.copyPage(lane,grid:grid,from:0,to:1))
        XCTAssertEqual(try StepEditing.copyPage(lane,grid:grid,from:0,to:0),lane)
    }
    func testSavedStepViewAndLegacyViewportCompatibility()throws {
        let view=HierarchyViewport(camera:HierarchyCamera(),width:1024,height:673,selection:.album,midiStepMode:true)
        let encoded=try JSONEncoder().encode(view)
        XCTAssertEqual(try JSONDecoder().decode(HierarchyViewport.self,from:encoded),view)
        var legacy=try XCTUnwrap(JSONSerialization.jsonObject(with:encoded) as? [String:Any]);legacy.removeValue(forKey:"midiStepMode")
        let decoded=try JSONDecoder().decode(HierarchyViewport.self,from:JSONSerialization.data(withJSONObject:legacy))
        XCTAssertNil(decoded.midiStepMode);XCTAssertEqual(decoded.camera,view.camera)
    }

}
