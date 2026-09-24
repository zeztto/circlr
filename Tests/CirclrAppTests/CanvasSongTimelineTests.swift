import AppKit
import XCTest
@testable import CirclrApp
import CirclrCore

final class CanvasSongTimelineTests: XCTestCase {
    func testSevenSectionOrderAndTimingFollowExecutionInsteadOfStorageOrder() throws {
        var project=Project()
        project.circleLayout = .orbit
        _=project.addTrack(name:"검증 악기")
        let ids=(1...7).map { project.addSection(name:"섹션 \($0)",at:Point(Double($0)*100,0),bars:$0) }
        let index=project.activeIndex
        project.arrangements[index].edges=zip(ids,ids.dropFirst()).map { FlowEdge(from:$0.0,to:$0.1) }
        for i in project.arrangements[index].uses.indices {
            project.arrangements[index].uses[i].isEnd=project.arrangements[index].uses[i].id==ids.last
        }
        project.arrangements[index].uses.swapAt(0,6)
        project.enableAlbum()
        project=try SectionGraphMigration.migrate(project)

        let scene=try HierarchySceneBuilder.build(project)
        let owner=try XCTUnwrap(scene.nodes.first(where:{$0.role == .song}))
        let timeline=CanvasSongTimeline(scene:scene)
        let segments=timeline.segments(on:owner.id)
        XCTAssertEqual(segments.count,7)
        XCTAssertEqual(segments.map(\.section),ids.map{.section(arrangementID:project.activeArrangementID,useID:$0)})
        XCTAssertEqual(segments.map(\.orderLabel),["01","02","03","04","05","06","07"])
        XCTAssertEqual(timeline.orderLabel(for:segments[0].section),"01")
        XCTAssertEqual(timeline.timing(for:segments[0].section),"01 · 0:00.0–0:02.0 · 길이 0:02.0")
        XCTAssertEqual(timeline.timing(for:segments[1].section),"02 · 0:02.0–0:06.0 · 길이 0:04.0")
        XCTAssertFalse(segments[0].hasRoomForOrder(at:80))
        XCTAssertTrue(segments[0].hasRoomForOrder(at:280))
        XCTAssertNil(timeline.timing(for:.album))
    }

    func testFreeformSceneHasNoOrbitOrderPresentation() throws {
        var project=Project()
        project.circleLayout = .freeform
        _=project.addTrack(name:"검증 악기")
        let use=project.addSection(name:"섹션",at:Point(),bars:1)
        project.enableAlbum()
        let scene=try HierarchySceneBuilder.build(SectionGraphMigration.migrate(project))
        let timeline=CanvasSongTimeline(scene:scene)
        XCTAssertNil(timeline.orderLabel(for:.section(arrangementID:project.activeArrangementID,useID:use)))
    }

    func testReusedSectionHighlightsOnlyCurrentOccurrence() throws {
        var project=Project()
        project.circleLayout = .orbit
        _=project.addTrack(name:"검증 악기")
        let a=project.addSection(name:"A",at:Point(),bars:1)
        let b=project.addSection(name:"B",at:Point(200,0),bars:1)
        let arrangement=project.activeArrangementID
        project.arrangements[project.activeIndex].uses[0].isEnd=false
        project.arrangements[project.activeIndex].edges=[FlowEdge(from:a,to:b)]
        project.enableAlbum()
        let original=try HierarchySceneBuilder.build(SectionGraphMigration.migrate(project))
        var nodes=original.nodes
        let songIndex=try XCTUnwrap(nodes.firstIndex(where:{$0.role == .song}))
        let firstIndex=try XCTUnwrap(nodes.firstIndex(where:{$0.id == .section(arrangementID:arrangement,useID:a)}))
        let middleIndex=try XCTUnwrap(nodes.firstIndex(where:{$0.id == .section(arrangementID:arrangement,useID:b)}))
        let songTime=OrbitTimeline(duration:30)
        nodes[songIndex].timeline=songTime
        var firstOrbit=try XCTUnwrap(nodes[firstIndex].orbit)
        firstOrbit.timeline=songTime
        firstOrbit.intervals=[OrbitInterval(0,10),OrbitInterval(20,30)]
        nodes[firstIndex].orbit=firstOrbit
        var middleOrbit=try XCTUnwrap(nodes[middleIndex].orbit)
        middleOrbit.timeline=songTime
        middleOrbit.intervals=[OrbitInterval(10,20)]
        nodes[middleIndex].orbit=middleOrbit
        let scene=HierarchyScene(nodes:nodes,edges:original.edges,isOrbit:true)
        let timeline=CanvasSongTimeline(scene:scene)
        let segments=timeline.segments(on:nodes[songIndex].id)
        XCTAssertEqual(segments.map(\.orderLabel),["01","02","03"])
        XCTAssertEqual(segments.map(\.section),[nodes[firstIndex].id,nodes[middleIndex].id,nodes[firstIndex].id])
        XCTAssertEqual(timeline.orderLabel(for:nodes[firstIndex].id),"01, 03")
        XCTAssertEqual(timeline.badgeTiming(for:nodes[firstIndex].id),
                       "2회 · 01 0:00.0–0:10.0 / 03 0:20.0–0:30.0")
        for (seconds,expected) in [(5.0,[true,false,false]),(10.0,[false,true,false]),
                                   (25.0,[false,false,true])] {
            let highlighted=segments.map { segment in
                CanvasSongTimeline.isCurrent(segment.interval,at:seconds,
                    sectionActive:segment.section == (seconds == 10 ? nodes[middleIndex].id:nodes[firstIndex].id))
            }
            XCTAssertEqual(highlighted,expected,"\(seconds)초")
        }
    }

    func testTimingSubtitleFitsSelectedBadgeInPortraitViewport() {
        let subtitle="03 · 1:04.0–1:20.0 · 길이 0:16.0"
        let label=CanvasLabelText("03  세 번째 섹션",primary:true,showsSubtitle:true,
                                  subtitle:subtitle,availableWidth:340)
        let font=NSFont.systemFont(ofSize:StudioTheme.canvasSubtitleSize,weight:.medium)
        let measured=(subtitle as NSString).size(withAttributes:[.font:font]).width
        XCTAssertGreaterThanOrEqual(label.size.width-20,ceil(measured))
        XCTAssertLessThanOrEqual(label.size.width,340)
    }
    func testLongPortraitSectionTitleFitsTwoLinesBesideOrbit() {
        let label=CanvasLabelText("06  너의 도시 · Final Chorus",primary:false,showsSubtitle:true,
            subtitle:"8 bars",availableWidth:132,wrapTitle:true)
        XCTAssertTrue(label.titleFits)
        XCTAssertEqual(label.size.width,132)
        XCTAssertEqual(label.titleHeight,40)
        XCTAssertEqual(label.size.height,74)
        let timing=CanvasLabelText("06  너의 도시 · Final Chorus",primary:false,showsSubtitle:true,
            subtitle:"06 · 1:04.0–1:20.0 · 길이 0:16.0",availableWidth:132,wrapTitle:true)
        XCTAssertEqual(timing.size,label.size)
    }
}
