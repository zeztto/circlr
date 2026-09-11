import XCTest
@testable import CirclrCore

final class AudioTempoRegionTests:XCTestCase {
    private func timing(changes:[TempoChange],start:Double=0,length:Double?=nil,repeats:Int=1,local:Bool=false)throws->AudioClipTiming {
        var context=MusicContext();context.tempo=120
        let clock=try MusicClock(bars:4,context:context,tempoChanges:changes)
        var node=MusicCircle(name:"audio",content:.audio(laneID:"lane",clipID:"clip"))
        node.startBeat=start;node.lengthBeats=length;node.repeatCount=repeats
        if local {node.settings.tempo = .local(120)}
        return AudioClipTiming(node:node,context:context,clock:clock)
    }
    private func clip(beat:Double=0,duration:Double=1)->AudioClip {
        var clip=AudioClip(assetID:"asset",duration:duration,beat:beat)
        clip.followsTempo=true;clip.sourceBPM=120
        return clip
    }
    func testChangesOutsideAudibleSpanAndExactEndAreAllowed() throws {
        for beat in [2.0,2.0-1e-12,8.0] {
            XCTAssertNoThrow(try timing(changes:[TempoChange(beat:beat,bpm:140)]).validateTempoFollowing(clip()))
        }
        XCTAssertThrowsError(try timing(changes:[TempoChange(beat:2-1e-5,bpm:140)]).validateTempoFollowing(clip()))
        XCTAssertNoThrow(try timing(changes:[TempoChange(beat:2,bpm:140)],start:4).validateTempoFollowing(clip()))
    }
    func testTrueCrossingAndDifferentRepeatRateAreRejected() throws {
        XCTAssertThrowsError(try timing(changes:[TempoChange(beat:8,bpm:140)],start:7,length:2).validateTempoFollowing(clip()))
        XCTAssertThrowsError(try timing(changes:[TempoChange(beat:4,bpm:140)],length:4,repeats:2).validateTempoFollowing(clip()))
        XCTAssertThrowsError(try timing(changes:[TempoChange(beat:2,bpm:140)],repeats:2).validateTempoFollowing(clip()))
    }
    func testSilentGapChangesReturningToSameRateAreAllowed() throws {
        let t=try timing(changes:[TempoChange(beat:2,bpm:140),TempoChange(beat:4,bpm:120)],length:4,repeats:2)
        XCTAssertNoThrow(try t.validateTempoFollowing(clip()))
    }
    func testExplicitLengthTruncatesAudibleSpanAndSkipsUnplayedClip() throws {
        XCTAssertNoThrow(try timing(changes:[TempoChange(beat:3,bpm:140)],length:2).validateTempoFollowing(clip(duration:3)))
        XCTAssertNoThrow(try timing(changes:[TempoChange(beat:3,bpm:140)],length:2).validateTempoFollowing(clip(beat:2,duration:3)))
        XCTAssertNoThrow(try timing(changes:[TempoChange(beat:3,bpm:140)],start:16).validateTempoFollowing(clip(duration:3)))
    }
    func testRenderWindowUsesSelectedSpanButPreservesLoopPeriod() throws {
        var c=clip(beat:1,duration:0.5)
        c.renderWindow=AudioRenderWindow(sourceStart:0,duration:2,cycleBeat:0,automaticEdges:true,envelopes:[])
        XCTAssertNoThrow(try timing(changes:[TempoChange(beat:2,bpm:140)]).validateTempoFollowing(c))
        XCTAssertThrowsError(try timing(changes:[TempoChange(beat:4,bpm:140)],repeats:2).validateTempoFollowing(c))
        XCTAssertThrowsError(try timing(changes:[TempoChange(beat:5.5,bpm:140)],length:4,repeats:2).validateTempoFollowing(c))
    }
    func testLocalAndUnfollowedClipsKeepExistingBehavior() throws {
        let changes=[TempoChange(beat:1,bpm:140)]
        XCTAssertNoThrow(try timing(changes:changes,local:true).validateTempoFollowing(clip()))
        var c=clip();c.followsTempo=false
        XCTAssertNoThrow(try timing(changes:changes).validateTempoFollowing(c))
    }
}
