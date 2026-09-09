import XCTest
@testable import CirclrCore

final class StudioNavigationSearchTests:XCTestCase {
    func section(_ use:String)->CircleAddress {.section(arrangementID:"song",useID:use)}
    func music(_ use:String,_ node:String)->CircleAddress {.music(arrangementID:"song",useID:use,nodeID:node)}
    func routes()->[StudioSectionRoute] {
        ["verse","chorus"].map{use in
            StudioSectionRoute(id:section(use),name:"Nordic 후렴",path:"앨범 › Citypop",tracks:[
                StudioTrackRoute(id:"one",name:"패드",destinations:[
                    StudioDestination(id:music(use,"midi"),name:"코드 연주",role:"MIDI",connected:true),
                    StudioDestination(id:music(use,"synth"),name:"따뜻한 신스",role:"악기",connected:true),
                    StudioDestination(id:music(use,"verb"),name:"넓은 공간",role:"이펙터",connected:true),
                    StudioDestination(id:music(use,"verb2"),name:"넓은 공간",role:"이펙터",connected:true),
                    StudioDestination(id:music(use,"audio"),name:"겨울 바다",role:"오디오",connected:false)]),
                StudioTrackRoute(id:"two",name:"패드",destinations:[
                    StudioDestination(id:music(use,"verb"),name:"넓은 공간",role:"이펙터",connected:true)])])
        }
    }
    func testEffectQueryReturnsThatEffectNotTrackPrimaryMIDI() {
        let all=StudioNavigationSearch.catalog(routes(),trackOrder:["one","two"])
        let result=StudioNavigationSearch.search(all,query:"넓은 공간",sectionID:section("verse"),trackID:"one")
        XCTAssertEqual(result.map(\.target),[music("verse","verb"),music("verse","verb2")])
        XCTAssertEqual(result.map(\.role),[.effect,.effect])
        XCTAssertTrue(result[0].detail.hasPrefix("이펙트 1/2"));XCTAssertTrue(result[1].detail.hasPrefix("이펙트 2/2"))
    }
    func testRepeatedUsesAndSharedEffectTrackPathsHaveUniqueIdentity() {
        let all=StudioNavigationSearch.catalog(routes(),trackOrder:["one","two"])
        XCTAssertEqual(Set(all.map(\.id)).count,all.count)
        let result=StudioNavigationSearch.search(all,query:"",role:.effect)
        XCTAssertEqual(result.count,6)
        XCTAssertEqual(result[0].target,result[2].target);XCTAssertNotEqual(result[0].id,result[2].id)
        XCTAssertTrue(result[0].path.contains("1 · 패드"));XCTAssertTrue(result[2].path.contains("2 · 패드"))
        XCTAssertNotEqual(result[0].sectionID,result[3].sectionID)
    }
    func testUnicodeAliasesAndTrackNumberFilters() {
        let all=StudioNavigationSearch.catalog(routes(),trackOrder:["one","two"])
        let query="ＣＩＴＹＰＯＰ ＮＯＲＤＩＣ 후렴 이펙트 2번 트랙"
        XCTAssertEqual(StudioNavigationSearch.search(all,query:query).map(\.target),[music("verse","verb"),music("chorus","verb")])
        XCTAssertEqual(StudioNavigationSearch.search(all,query:"1번 섹션 2 번 트랙 이펙트").map(\.target),[music("verse","verb")])
        let numbered=StudioNavigationSearch.catalog(routes(),trackOrder:(1...11).map{"unused\($0)"}+["two","one"])
        XCTAssertTrue(StudioNavigationSearch.search(numbered,query:"2번 트랙").isEmpty)
        XCTAssertEqual(StudioNavigationSearch.search(numbered,query:"１２번트랙 이펙트").count,2)
        XCTAssertEqual(StudioNavigationSearch.search(all,query:"음색").map(\.role),[.instrument,.instrument])
        XCTAssertEqual(StudioNavigationSearch.search(all,query:"악기").map(\.role),[.instrument,.instrument])
        XCTAssertEqual(StudioNavigationSearch.search(all,query:"이펙터").count,6)
    }
    func testRoleSectionAndTrackConstraintsCannotLeakOtherResults() {
        let all=StudioNavigationSearch.catalog(routes(),trackOrder:["one","two"])
        let result=StudioNavigationSearch.search(all,query:"",sectionID:section("chorus"),trackID:"one",role:.audio)
        XCTAssertEqual(result.map(\.target),[music("chorus","audio")]);XCTAssertFalse(result[0].connected)
        XCTAssertTrue(result[0].detail.hasSuffix("미연결"))
        XCTAssertTrue(StudioNavigationSearch.search(all,query:"없는 서클").isEmpty)
        XCTAssertTrue(StudioNavigationSearch.search(all,query:"",sectionID:section("missing")).isEmpty)
        XCTAssertTrue(StudioNavigationSearch.search(all,query:"",trackID:"two",role:.midi).isEmpty)
    }
    func testEmptySectionsAndLongNamesRemainDirectlyNavigable() {
        var routes=routes();let title=String(repeating:"겨울밤의 아주 긴 이름 ",count:12)
        routes.append(.init(id:section("empty"),name:title,path:"앨범 › 마지막 곡",tracks:[]))
        let all=StudioNavigationSearch.catalog(routes,trackOrder:["one","two"])
        let result=StudioNavigationSearch.search(all,query:"마지막 곡",role:.section)
        XCTAssertEqual(result.count,1);XCTAssertEqual(result[0].target,section("empty"));XCTAssertEqual(result[0].title,title)
        XCTAssertEqual(StudioNavigationSearch.search(all,query:"",role:.section).map(\.target),routes.map(\.id))
    }
    func testRealProjectCatalogPreservesModelAndOpensEveryDestination()throws {
        var project=try HierarchyEditingTests().fixture()
        _=try ProjectEditing.reuse(project.active.uses[0].id,in:&project,at:Point(300,0))
        let before=project
        let all=StudioNavigationSearch.catalog(try StudioNavigation.build(project),trackOrder:project.tracks.map(\.id))
        XCTAssertFalse(all.isEmpty)
        for entry in all {XCTAssertNotNil(try StudioNavigation.scene(revealing:entry.target,in:project).node(entry.target))}
        XCTAssertEqual(project,before)
    }
}
