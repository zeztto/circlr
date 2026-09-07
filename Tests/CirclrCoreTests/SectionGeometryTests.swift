import XCTest
@testable import CirclrCore

final class SectionGeometryTests:XCTestCase {
    func testEveryPlaybackHasExactlyOneOutline() {
        for count in 1...256 {
            let r=SectionRings(repeats:count)
            XCTAssertEqual(r.radii.count,count)
            XCTAssertEqual(Set(r.radii).count,count)
            XCTAssertEqual(r.radii.first,80)
            XCTAssertLessThanOrEqual(r.outerRadius,136.000001)
            XCTAssertGreaterThan(r.portRadius,r.outerRadius)
            XCTAssertGreaterThan(r.lineWidth,0)
        }
        XCTAssertEqual(SectionRings(repeats:3).radii,[80,88,96])
        XCTAssertEqual(SectionRings(repeats:1).outerRadius,80)
        XCTAssertEqual(SectionRings(repeats:0).count,1)
        XCTAssertEqual(SectionRings(repeats:Int.max).count,256)
    }
    func testAudioTimelineMatchesSecondsAndTempoFollowing() throws {
        var context=MusicContext();context.tempo=120
        let clock=try MusicClock(bars:4,context:context)
        var clip=AudioClip(assetID:"audio",duration:2,beat:1)
        XCTAssertEqual(AudioClipGeometry.visibleBeats(clip,clock:clock),4)
        clip.followsTempo=true;clip.sourceBPM=60
        XCTAssertEqual(AudioClipGeometry.visibleBeats(clip,clock:clock),2)
        clip.beat=15
        XCTAssertEqual(AudioClipGeometry.visibleBeats(clip,clock:clock),1)
        clip.beat=18
        XCTAssertEqual(AudioClipGeometry.visibleBeats(clip,clock:clock),0)
    }
    func testUnwarpedAudioCrossesTempoChangeOnSameTimeAxis() throws {
        var context=MusicContext();context.tempo=120
        let clock=try MusicClock(bars:4,context:context,tempoChanges:[TempoChange(beat:4,bpm:60)])
        let clip=AudioClip(assetID:"audio",duration:2,beat:3)
        XCTAssertEqual(AudioClipGeometry.visibleBeats(clip,clock:clock),2.5,accuracy:1e-9)
    }
}
