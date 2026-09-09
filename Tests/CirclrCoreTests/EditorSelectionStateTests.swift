import XCTest
@testable import CirclrCore

final class EditorSelectionStateTests:XCTestCase {
    func testSelectionFiltersMissingIDsAndPreservesAnchorAndSourceNotes() {
        let notes=[Note(beat:2,length:1,pitch:64,velocity:90),Note(beat:0,length:1,pitch:60,velocity:70)]
        var s=EditorSelectionState();s.noteIDs=[notes[0].id,"missing",notes[1].id,notes[0].id];s.anchorID=notes[0].id;s.beat=2
        let r=s.restored(notes:notes,beats:16,clip:nil,automation:[])
        XCTAssertEqual(r.noteIDs,notes.map(\.id).sorted());XCTAssertEqual(r.anchorID,notes[0].id);XCTAssertEqual(r.beat,2)
        XCTAssertEqual(s.noteIDs.count,4)
        let deleted=s.restored(notes:[notes[1]],beats:16,clip:nil,automation:[])
        XCTAssertEqual(deleted.noteIDs,[notes[1].id]);XCTAssertEqual(deleted.anchorID,notes[1].id)
        XCTAssertNil(s.restored(notes:[],beats:16,clip:nil,automation:[]).anchorID)
    }
    func testCursorPreservesSourceTimeAcrossTrimAndRejectsAnotherAssetOrClip() {
        var clip=AudioClip(assetID:"file",duration:4);clip.sourceStart=2
        var s=EditorSelectionState();s.audioClipID=clip.id;s.audioAssetID=clip.assetID;s.audioSourcePosition=4
        XCTAssertEqual(s.restored(notes:[],beats:16,clip:clip,automation:[]).audioSourcePosition,4)
        clip.sourceStart=5;clip.duration=1
        XCTAssertEqual(s.restored(notes:[],beats:16,clip:clip,automation:[]).audioSourcePosition,5)
        s.audioSourcePosition=9
        XCTAssertEqual(s.restored(notes:[],beats:16,clip:clip,automation:[]).audioSourcePosition,6)
        var other=clip;other.assetID="replacement";XCTAssertNil(s.restored(notes:[],beats:16,clip:other,automation:[]).audioSourcePosition)
        other=clip;other.id="another";XCTAssertNil(s.restored(notes:[],beats:16,clip:other,automation:[]).audioSourcePosition)
    }
    func testAutomationSelectionIsValidatedPerParameter() {
        let a=AutomationPoint(beat:0,value:1),b=AutomationPoint(beat:1,value:0.5)
        var s=EditorSelectionState();s.automationPoints=["gain":a.id,"pan":b.id,"unknown":a.id]
        let lanes=[AutomationLane(parameter:.gain,points:[a]),AutomationLane(parameter:.pan,points:[b])]
        XCTAssertEqual(s.restored(notes:[],beats:16,clip:nil,automation:lanes).automationPoints,["gain":a.id,"pan":b.id])
        XCTAssertEqual(s.restored(notes:[],beats:16,clip:nil,automation:[lanes[1]]).automationPoints,["pan":b.id])
        s.automationPoints["gain"]=b.id;XCTAssertNil(s.restored(notes:[],beats:16,clip:nil,automation:lanes).automationPoints["gain"])
    }
    func testNonfiniteAndOutOfRangePositionsAreSafe() {
        var s=EditorSelectionState();s.beat = .nan
        XCTAssertEqual(s.restored(notes:[],beats:16,clip:nil,automation:[]).beat,0)
        s.beat=30;XCTAssertEqual(s.restored(notes:[],beats:4,clip:nil,automation:[]).beat,4)
        s.beat = -10;XCTAssertEqual(s.restored(notes:[],beats:4,clip:nil,automation:[]).beat,0)
        var clip=AudioClip(assetID:"file",duration:4);clip.sourceStart=1
        s.audioClipID=clip.id;s.audioAssetID=clip.assetID;s.audioSourcePosition = .infinity
        XCTAssertNil(s.restored(notes:[],beats:4,clip:clip,automation:[]).audioSourcePosition)
    }
    func testWorkspaceRoundTripAndLegacyDecodeKeepMusicSeparate()throws {
        var p=try HierarchyEditingTests().fixture(),w=StudioWorkspace(),s=EditorSelectionState()
        s.noteIDs=["a","b"];s.anchorID="b";s.beat=3;s.automationPoints=["gain":"point"];w.selection=s
        let original=p;p.hierarchyView = .init(camera:.init(),width:1024,height:768,selection:.album,workspace:w)
        let decoded=try JSONDecoder().decode(Project.self,from:JSONEncoder().encode(p));XCTAssertEqual(decoded,p)
        p.hierarchyView=nil;XCTAssertEqual(p,original)
        XCTAssertNil(try JSONDecoder().decode(StudioWorkspace.self,from:Data("{}".utf8)).selection)
        XCTAssertNil(try JSONDecoder().decode(StudioWorkspace.self,from:Data(#"{"selection":{"beat":"invalid"}}"#.utf8)).selection)
    }
}
