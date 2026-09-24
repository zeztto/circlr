import XCTest
@testable import CirclrCore

final class SavedWorkspaceTests:XCTestCase {
    func fixture()throws->Project {try HierarchyEditingTests().fixture()}
    func section(_ p:Project)->CircleAddress {.section(arrangementID:p.active.id,useID:p.active.uses[0].id)}
    func music(_ id:ID,in p:Project)->CircleAddress {.music(arrangementID:p.active.id,useID:p.active.uses[0].id,nodeID:id)}
    func viewport(_ address:CircleAddress,workspace:StudioWorkspace? = nil)->HierarchyViewport {
        .init(camera:.init(pan:.init(-10,20),zoom:2),width:1024,height:768,selection:address,settingsOpen:true,midiStepMode:true,workspace:workspace)
    }
    func testEveryPageRoundTripsWithOriginalAndAutomationSelection()throws {
        let p=try fixture()
        for page in [StudioWorkspace.Page.content,.connections,.transition,.automation,.settings] {
            var state=StudioWorkspace(page:page);state.original=true;state.automationParameter = .pan;state.transitionID="edge"
            var connection=ConnectionWorkspaceState();connection.query="도시의 밤 #3";connection.firstOctant = .southeast;connection.currentPortOnly=true
            state.connection=connection
            var project=p;project.hierarchyView=viewport(section(p),workspace:state)
            XCTAssertEqual(try JSONDecoder().decode(Project.self,from:JSONEncoder().encode(project)),project)
        }
    }
    func testLegacyViewportAndFutureWorkspaceValuesRemainReadable()throws {
        let p=try fixture(),saved=viewport(section(p))
        let decoded=try JSONDecoder().decode(HierarchyViewport.self,from:JSONEncoder().encode(saved))
        XCTAssertNil(decoded.workspace);XCTAssertTrue(decoded.settingsOpen);XCTAssertEqual(decoded.midiStepMode,true)
        let future=try JSONDecoder().decode(StudioWorkspace.self,from:Data(#"{"page":"future-editor","automationParameter":"future-control","original":true,"connection":{"future":1}}"#.utf8))
        XCTAssertEqual(future.page,.content);XCTAssertEqual(future.automationParameter,.gain);XCTAssertTrue(future.original);XCTAssertNil(future.connection)
        XCTAssertEqual(try JSONDecoder().decode(StudioWorkspace.self,from:Data("{}".utf8)),.init())
    }
    func testDeletedSelectionFallsBackToNearestValidOwner()throws {
        let p=try fixture(),scope=section(p),owner=CircleAddress.composition(try XCTUnwrap(p.album?.children.first))
        XCTAssertEqual(StudioWorkspace.restoredSelection(music("missing",in:p),in:p),scope)
        XCTAssertEqual(StudioWorkspace.restoredSelection(.section(arrangementID:p.active.id,useID:"missing"),in:p),owner)
        XCTAssertEqual(StudioWorkspace.restoredSelection(.group(parent:scope,id:"missing"),in:p),scope)
        XCTAssertEqual(StudioWorkspace.restoredSelection(.signal("missing"),in:p),.sound)
        XCTAssertEqual(StudioWorkspace.restoredSelection(.composition("missing"),in:p),.album)
        XCTAssertEqual(StudioWorkspace.restoredSelection(.music(arrangementID:"missing",useID:"missing",nodeID:"missing"),in:p),.album)
    }
    func testOpeningSelectionShowsSingleUnsavedSongButPreservesAlbumCases()throws {
        var project=try fixture()
        let songID=try XCTUnwrap(project.album?.children.first)
        XCTAssertEqual(StudioWorkspace.openingSelection(in:project),.composition(songID))

        project.hierarchyView=viewport(.album)
        XCTAssertEqual(StudioWorkspace.openingSelection(in:project),.album)
        project.hierarchyView=nil
        _=try AlbumEditing.add(name:"두 번째 곡",kind:.song,in:&project)
        XCTAssertEqual(StudioWorkspace.openingSelection(in:project),.album)
    }
    func testUnselectedArrangementDoesNotReopenItsHiddenChild()throws {
        var p=try fixture();var alternative=p.active;alternative.id=newID();p.arrangements.append(alternative)
        p.album?.compositions[0].arrangementIDs.append(alternative.id)
        let desired=CircleAddress.section(arrangementID:alternative.id,useID:alternative.uses[0].id),before=p
        XCTAssertEqual(StudioWorkspace.restoredSelection(desired,in:p),.composition(p.album!.compositions[0].id))
        XCTAssertEqual(p,before)
    }
    func testTransitionRequiresCurrentSourceAndAutomationRequiresAudio()throws {
        var p=try fixture();let start=section(p),from=p.active.uses[0].id
        let second=try ProjectEditing.reuse(from,in:&p,at:.init(400,0))
        try ProjectEditing.connect(from:from,to:second,in:&p)
        var state=StudioWorkspace(page:.transition);state.transitionID=p.active.edges[0].id
        XCTAssertEqual(state.restored(at:start,in:p).page,.transition)
        XCTAssertEqual(state.restored(at:.section(arrangementID:p.active.id,useID:second),in:p).page,.settings)
        p.arrangements[0].edges=[]
        XCTAssertNil(state.restored(at:start,in:p).transitionID)
        let midi=try XCTUnwrap(p.sections[0].graph?.nodes.first{if case .midi=$0.content{return true};return false})
        let instrument=try XCTUnwrap(p.sections[0].graph?.nodes.first{if case .instrument=$0.content{return true};return false})
        state = .init(page:.automation);state.automationParameter = .pan;state.original=true
        XCTAssertEqual(state.restored(at:music(midi.id,in:p),in:p).page,.content)
        XCTAssertEqual(state.restored(at:music(instrument.id,in:p),in:p),state)
    }
    func testSavedReconnectRetainsExactEndpointsAndDisarmsDeletedCable()throws {
        var p=try fixture();let scope=section(p),from=p.active.uses[0].id
        let second=try ProjectEditing.reuse(from,in:&p,at:.init(400,0));try ProjectEditing.connect(from:from,to:second,in:&p)
        let edge=try XCTUnwrap(AgentPortEditing.snapshot(at:scope,in:p).connections.first?.connection)
        var connection=ConnectionWorkspaceState();connection.ownPortID=edge.from.portID;connection.target=edge.to
        connection.replacing=edge.id;connection.replacementSource=edge.from;connection.replacementDestination=edge.to
        var saved=StudioWorkspace(page:.connections);saved.connection=connection;let before=p
        XCTAssertEqual(saved.restored(at:scope,in:p),saved);XCTAssertEqual(p,before)
        p.arrangements[0].edges=[];p.arrangements[0].chosenEdges=[:]
        let restored=try XCTUnwrap(saved.restored(at:scope,in:p).connection)
        XCTAssertNil(restored.replacing);XCTAssertNil(restored.target)
        XCTAssertEqual(restored.ownPortID,connection.ownPortID)
    }
    func testSavedInvalidPortFallsBackWithoutSelectingDestination()throws {
        let p=try fixture();var saved=StudioWorkspace(page:.connections)
        var connection=ConnectionWorkspaceState();connection.ownPortID="missing";connection.query="#2";saved.connection=connection
        let restored=try XCTUnwrap(saved.restored(at:section(p),in:p).connection)
        XCTAssertNotEqual(restored.ownPortID,"missing");XCTAssertEqual(restored.query,"#2");XCTAssertNil(restored.target)
    }
    func testMusicalUndoAndPortUndoPreserveCurrentWorkspace()throws {
        var old=try fixture();old.hierarchyView=viewport(section(old),workspace:.init(page:.settings))
        var current=old;current.name="바뀐 곡";var state=StudioWorkspace(page:.connections);state.original=true
        current.hierarchyView=viewport(section(old),workspace:state)
        let undone=try CircleHistory.restore(old,layoutOnly:false,current:current)
        XCTAssertEqual(undone.name,old.name);XCTAssertEqual(undone.hierarchyView,current.hierarchyView)
        let portUndo=try CircleHistory.restore(old,layoutOnly:true,current:current)
        XCTAssertEqual(portUndo.hierarchyView,current.hierarchyView);XCTAssertEqual(portUndo.name,current.name)
    }
}
