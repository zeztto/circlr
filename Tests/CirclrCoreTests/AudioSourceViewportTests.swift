import XCTest
@testable import CirclrCore

final class AudioSourceViewportTests:XCTestCase {
    func testFitPreservesSourceCoordinatesAndRemainsFixedAcrossTrim() {
        let asset=Asset(name:"source",path:"source.wav",duration:120,sampleRate:48000)
        var clip=AudioClip(assetID:asset.id,duration:2);clip.sourceStart=60
        var view=AudioSourceViewport();XCTAssertEqual(view.range(assetDuration:120),0...120)
        view.fit(clip,assetDuration:120);let fixed=view.range(assetDuration:120)
        XCTAssertEqual(fixed.lowerBound,59.84,accuracy:1e-9);XCTAssertEqual(fixed.upperBound,62.16,accuracy:1e-9)
        for source in [59.84,60,61.3,62,62.16] {
            XCTAssertEqual(view.source(at:view.phase(at:source,assetDuration:120),assetDuration:120),source,accuracy:1e-9)
        }
        clip.sourceStart=60.5;clip.duration=1
        XCTAssertEqual(view.range(assetDuration:120),fixed)
        XCTAssertFalse(view.contains(30,assetDuration:120));XCTAssertGreaterThan(view.phase(at:90,assetDuration:120),1)
        view.showAll();XCTAssertEqual(view.range(assetDuration:120),0...120)
    }
    func testFitAtFileEdgesAndTinyClipHasVisiblePadding() {
        let asset=Asset(name:"short",path:"short.wav",duration:4,sampleRate:48000)
        var clip=AudioClip(assetID:asset.id,duration:0.005),view=AudioSourceViewport()
        view.fit(clip,assetDuration:4);XCTAssertEqual(view.range(assetDuration:4).lowerBound,0)
        XCTAssertGreaterThan(view.range(assetDuration:4).upperBound,clip.duration)
        clip.sourceStart=3.995;view.fit(clip,assetDuration:4)
        XCTAssertEqual(view.range(assetDuration:4).upperBound,4)
        XCTAssertEqual(view.source(at:2,assetDuration:4),4)
    }
    func testTrimLimitsPreserveFadeSumRenderWindowAndOppositeEdge()throws {
        let asset=Asset(name:"source",path:"source.wav",duration:8,sampleRate:48000)
        var clip=AudioClip(assetID:asset.id,duration:2);clip.sourceStart=2;clip.fadeIn=0.4;clip.fadeOut=0.6
        clip.renderWindow=AudioRenderWindow(sourceStart:1,duration:4,cycleBeat:0,automaticEdges:false,envelopes:[])
        let bounds=AudioTrimBounds(clip:clip,asset:asset)
        XCTAssertEqual(bounds.start,1...3);XCTAssertEqual(bounds.end,3...5)
        let trimmed=bounds.trimming(clip,to:10,editingEnd:false)
        XCTAssertEqual(trimmed.sourceStart,3);XCTAssertEqual(trimmed.duration,1);try trimmed.validateEditing(asset:asset)
        let extended=bounds.trimming(clip,to:10,editingEnd:true)
        XCTAssertEqual(extended.sourceStart,2);XCTAssertEqual(extended.duration,3);try extended.validateEditing(asset:asset)
        XCTAssertEqual(extended.renderWindow,clip.renderWindow)
        clip.renderWindow=nil;clip.duration=0.005;clip.fadeIn=nil;clip.fadeOut=nil
        XCTAssertEqual(AudioTrimBounds(clip:clip,asset:asset).trimming(clip,to:2,editingEnd:true).duration,0.005,accuracy:1e-9)
    }
}
