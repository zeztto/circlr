import XCTest
@testable import CirclrCore

final class PitchBendWorkspaceStateTests:XCTestCase {
    func testLegacyWorkspaceDecodesWithoutCreatingExpressionState()throws {
        for json in [#"{}"#,#"{"page":"content","original":true}"#,#"{"page":"automation","automationParameter":"pan"}"#] {
            let value=try JSONDecoder().decode(StudioWorkspace.self,from:Data(json.utf8))
            XCTAssertNil(value.pitchBend)
        }
        let old=try JSONDecoder().decode(StudioWorkspace.self,from:Data(#"{"page":"content","original":true}"#.utf8))
        XCTAssertTrue(old.original);XCTAssertEqual(old.page,.content)
        let malformed=try JSONDecoder().decode(StudioWorkspace.self,from:Data(#"{"page":"pitchBend","pitchBend":{"selectedIndex":"bad","displayedBeats":4}}"#.utf8))
        XCTAssertNil(malformed.pitchBend)
    }
    func testValidationClearsInvalidFieldsIndependentlyAndChecksCurrentEventCount() {
        for index in [-1,100000,Int.max] {
            let value=PitchBendWorkspaceState(selectedIndex:index,displayedBeats:8).validated()
            XCTAssertNil(value.selectedIndex);XCTAssertEqual(value.displayedBeats,8)
        }
        for beats in [Double.nan,Double.infinity,-Double.infinity,0,-1,131073] {
            let value=PitchBendWorkspaceState(selectedIndex:2,displayedBeats:beats).validated(count:3)
            XCTAssertEqual(value.selectedIndex,2);XCTAssertNil(value.displayedBeats)
        }
        XCTAssertNil(PitchBendWorkspaceState(selectedIndex:2).validated(count:2).selectedIndex)
        XCTAssertNil(PitchBendWorkspaceState(selectedIndex:0).validated(count:0).selectedIndex)
        XCTAssertEqual(PitchBendWorkspaceState(selectedIndex:99999,displayedBeats:131072).validated(count:100000),.init(selectedIndex:99999,displayedBeats:131072))
    }
    func testDocumentRoundTripRetainsPitchPageAndViewOnlyState()throws {
        var p=try HierarchyEditingTests().fixture()
        let address=CircleAddress.section(arrangementID:p.active.id,useID:p.active.uses[0].id)
        var workspace=StudioWorkspace(page:.pitchBend);workspace.original=true
        workspace.pitchBend = .init(selectedIndex:3,displayedBeats:64)
        let sections=p.sections,patterns=p.patterns,revision=p.musicRevision
        p.hierarchyView = .init(camera:.init(pan:.init(-10,20),zoom:2),width:1024,height:768,selection:address,settingsOpen:true,midiStepMode:false,workspace:workspace)
        let decoded=try JSONDecoder().decode(Project.self,from:JSONEncoder().encode(p))
        XCTAssertEqual(decoded,p);XCTAssertEqual(decoded.hierarchyView?.workspace,workspace)
        XCTAssertEqual(decoded.sections,sections);XCTAssertEqual(decoded.patterns,patterns);XCTAssertEqual(decoded.musicRevision,revision)
        let sanitized=try JSONDecoder().decode(StudioWorkspace.self,from:Data(#"{"page":"pitchBend","pitchBend":{"selectedIndex":100000,"displayedBeats":0}}"#.utf8))
        XCTAssertEqual(sanitized.pitchBend,.init())
    }
    func testRestorationRetainsOrdinaryAndSharedMIDIAndRejectsOtherDestinations()throws {
        let p=try StudioNavigationRhythmTests().fixture(),before=p
        let use=p.active.uses[0]
        let graph=try XCTUnwrap(SectionGraphEditing.effective(section:p.sections[0],use:use))
        let ordinary=try XCTUnwrap(graph.nodes.first{if case .midi=$0.content{return true};return false})
        func address(_ id:ID)->CircleAddress {.music(arrangementID:p.active.id,useID:use.id,nodeID:id)}
        var workspace=StudioWorkspace(page:.pitchBend);workspace.pitchBend = .init(selectedIndex:0,displayedBeats:32)
        for target in [address(ordinary.id),address("rhythm-midi:\(p.tracks[0].id)")] {
            let restored=workspace.restored(at:target,in:p)
            XCTAssertEqual(restored.page,.pitchBend);XCTAssertEqual(restored.pitchBend,workspace.pitchBend)
        }
        for target in [CircleAddress.section(arrangementID:p.active.id,useID:use.id),address("rhythm-audio:\(p.tracks[0].id)")] {
            let restored=workspace.restored(at:target,in:p)
            XCTAssertEqual(restored.page,.content);XCTAssertNil(restored.pitchBend)
        }
        XCTAssertEqual(workspace.restored(at:address("deleted"),in:p),.init())
        XCTAssertEqual(p,before)
    }
}
