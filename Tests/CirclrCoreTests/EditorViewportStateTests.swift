import XCTest
@testable import CirclrCore

final class EditorViewportStateTests:XCTestCase {
    func clock()throws->MusicClock {try MusicClock(bars:16,context:MusicContext())}
    func testViewRoundTripKeepsEveryPositionWithoutChangingMusic()throws {
        var p=try HierarchyEditingTests().fixture(),view=EditorViewportState()
        view.topPitch=97;view.orbit.topPitch=88;view.orbit.page=2;view.orbit.barsPerPage=2
        view.steps.page=7;view.steps.subdivisions=8;view.steps.drumMode=true;view.steps.extraPitches=[3,97];view.steps.rowQuery="킥";view.steps.newPitch=97
        view.audioAssetID="audio";view.audio.zoom(by:2,around:3,assetDuration:10)
        view.scrolls=["piano":.init(x:850,y:130),"steps":.init(y:200)]
        var workspace=StudioWorkspace(page:.content);workspace.editor=view
        var automation=AutomationViewport();automation.reveal(base:64,beat:128);workspace.automationViewport=automation
        let before=p;p.hierarchyView = .init(camera:.init(),width:1024,height:768,selection:.album,workspace:workspace)
        let encoded=try JSONEncoder().encode(p),decoded=try JSONDecoder().decode(Project.self,from:encoded)
        XCTAssertEqual(decoded,p);p.hierarchyView=nil;XCTAssertEqual(p,before)
    }
    func testInvalidPagesAndPitchesAreClampedBeforeUsingGridArithmetic()throws {
        var view=EditorViewportState();view.topPitch=Int.min;view.orbit.page=Int.max;view.orbit.barsPerPage=Int.max;view.orbit.topPitch=Int.max
        view.steps.page=Int.max;view.steps.subdivisions=Int.max;view.steps.newPitch = -2;view.steps.extraPitches=[-4,3,128]
        let actual=view.restored(beats:16,clock:try clock(),assetID:nil,assetDuration:nil)
        XCTAssertEqual(actual.topPitch,12);XCTAssertEqual(actual.orbit.barsPerPage,4);XCTAssertEqual(actual.orbit.page,3)
        XCTAssertEqual(actual.orbit.highest,127);XCTAssertEqual(actual.steps.subdivisions,4);XCTAssertEqual(actual.steps.page,3)
        XCTAssertEqual(actual.steps.newPitch,0);XCTAssertEqual(actual.steps.extraPitches,[3])
    }
    func testShorterMusicClampsPageButDoesNotFitPitchOrEraseRowSearch()throws {
        var view=EditorViewportState();view.steps.page=9;view.steps.rowQuery="하이햇";view.topPitch=104;view.orbit.page=3
        let restored=view.restored(beats:4,clock:try MusicClock(bars:1,context:MusicContext()),assetID:nil,assetDuration:nil)
        XCTAssertEqual(restored.steps.page,0);XCTAssertEqual(restored.orbit.page,0);XCTAssertEqual(restored.topPitch,104);XCTAssertEqual(restored.steps.rowQuery,"하이햇")
    }
    func testSameAssetPreservesRangeAndReplacementDropsIt() {
        var view=EditorViewportState();view.audioAssetID="first";view.audio.zoom(by:4,around:8,assetDuration:10)
        let before=view.audio
        XCTAssertEqual(view.restored(beats:4,clock:nil,assetID:"first",assetDuration:10).audio,before)
        let replaced=view.restored(beats:4,clock:nil,assetID:"second",assetDuration:10)
        XCTAssertNil(replaced.audio.fitted);XCTAssertEqual(replaced.audioAssetID,"second")
        let shorter=view.restored(beats:4,clock:nil,assetID:"first",assetDuration:2)
        XCTAssertLessThanOrEqual(shorter.audio.range(assetDuration:2).upperBound,2)
        XCTAssertEqual(view.audio,before)
    }
    func testScrollClampsAtContentEdgesAndRejectsNonfiniteNumbers() {
        XCTAssertEqual(EditorScrollPosition(x:850,y:400).clamped(width:1000,height:600,visibleWidth:500,visibleHeight:300),.init(x:500,y:300))
        XCTAssertEqual(EditorScrollPosition(x:-4,y:-5).clamped(width:1000,height:600,visibleWidth:500,visibleHeight:300),.init())
        XCTAssertEqual(EditorScrollPosition(x:.nan,y:.infinity).clamped(width:1000,height:600,visibleWidth:500,visibleHeight:300),.init())
        XCTAssertEqual(EditorScrollPosition(x:100,y:100).clamped(width:50,height:50,visibleWidth:500,visibleHeight:300),.init())
    }
    func testRouterScrollRoundTripRestoresItsPositionAndRejectsUnknownKeys()throws {
        var view=EditorViewportState()
        view.scrolls=["router":.init(x:24,y:360),"output":.init(y:80),"futureRouter":.init(y:999)]
        let decoded=try JSONDecoder().decode(EditorViewportState.self,from:JSONEncoder().encode(view))
        let restored=decoded.restored(beats:16,clock:try clock(),assetID:nil,assetDuration:nil)
        XCTAssertEqual(restored.scrolls,["router":.init(x:24,y:360),"output":.init(y:80)])
        XCTAssertEqual(restored.restored(beats:16,clock:try clock(),assetID:nil,assetDuration:nil).scrolls,restored.scrolls)
        XCTAssertEqual(view.scrolls["futureRouter"],.init(y:999))
    }
    func testPersistedScrollKeysAndValuesAreBounded() {
        var view=EditorViewportState();view.scrolls=["piano":.init(x:.infinity,y:20),"steps":.init(y:-5),"unknown":.init(x:10)]
        let restored=view.restored(beats:16,clock:nil,assetID:nil,assetDuration:nil)
        XCTAssertEqual(restored.scrolls,["piano":.init(y:20),"steps":.init()])
    }
    func testAutomationDecodeRejectsInvalidRangeAndLegacyWorkspaceStillLoads()throws {
        let data=Data(#"{"page":"automation","automationViewport":{"fittedBeats":2000000}}"#.utf8)
        let invalid=try JSONDecoder().decode(StudioWorkspace.self,from:data)
        XCTAssertNil(invalid.automationViewport?.fittedBeats)
        let legacy=try JSONDecoder().decode(StudioWorkspace.self,from:Data(#"{"page":"settings","original":true}"#.utf8))
        XCTAssertNil(legacy.editor);XCTAssertNil(legacy.automationViewport);XCTAssertTrue(legacy.original)
    }
    func testStepExtraRowsEncodeInStablePitchOrder()throws {
        var view=StepEditorState();view.extraPitches=[97,3,36]
        let object=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(view)) as? [String:Any])
        XCTAssertEqual(object["extraPitches"] as? [Int],[3,36,97])
        XCTAssertEqual(try JSONDecoder().decode(StepEditorState.self,from:Data("{}".utf8)),.init())
    }
}
