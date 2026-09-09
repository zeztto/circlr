import XCTest
@testable import CirclrCore

final class AudioSourceViewportTests:XCTestCase {
    func testZoomPreservesPointerSourceAndClampsAtFileEdges() {
        var view=AudioSourceViewport()
        view.zoom(by:4,around:30,assetDuration:120)
        XCTAssertEqual(view.range(assetDuration:120),22.5...52.5)
        XCTAssertEqual(view.phase(at:30,assetDuration:120),0.25,accuracy:1e-9)
        view.zoom(by:0.25,around:30,assetDuration:120)
        XCTAssertNil(view.fitted)
        view.zoom(by:4,around:-10,assetDuration:120)
        XCTAssertEqual(view.range(assetDuration:120),0...30)
        view.showAll();view.zoom(by:4,around:130,assetDuration:120)
        XCTAssertEqual(view.range(assetDuration:120),90...120)
    }
    func testPanAndRevealKeepZoomAndDoNotFollowVisibleCursor() {
        var view=AudioSourceViewport()
        view.pan(by:4,assetDuration:120);XCTAssertNil(view.fitted)
        view.zoom(by:4,around:60,assetDuration:120)
        view.pan(by:15,assetDuration:120)
        XCTAssertEqual(view.range(assetDuration:120),60...90)
        view.reveal(75,assetDuration:120);XCTAssertEqual(view.range(assetDuration:120),60...90)
        view.reveal(40,assetDuration:120);XCTAssertEqual(view.range(assetDuration:120),25...55)
        view.reveal(120,assetDuration:120);XCTAssertEqual(view.range(assetDuration:120),90...120)
        view.pan(by:-200,assetDuration:120);XCTAssertEqual(view.range(assetDuration:120),0...30)
        view.pan(by:200,assetDuration:120);XCTAssertEqual(view.range(assetDuration:120),90...120)
    }
    func testNavigationLimitsPrecisionAndRejectsInvalidInput() {
        var view=AudioSourceViewport()
        view.zoom(by:1e300,around:60.123,assetDuration:120)
        let range=view.range(assetDuration:120)
        XCTAssertEqual(range.upperBound-range.lowerBound,0.01,accuracy:1e-9)
        for phase in [0.0,0.123,0.5,0.987,1.0] {
            XCTAssertEqual(view.phase(at:view.source(at:phase,assetDuration:120),assetDuration:120),phase,accuracy:1e-9)
        }
        for invalid in [Double.nan,.infinity,-.infinity] {
            view.zoom(by:invalid,around:60,assetDuration:120)
            view.zoom(by:2,around:invalid,assetDuration:120)
            view.zoom(by:2,around:60,assetDuration:invalid)
            view.pan(by:invalid,assetDuration:120)
            view.reveal(invalid,assetDuration:120)
        }
        view.zoom(by:0,around:60,assetDuration:120)
        view.zoom(by:-2,around:60,assetDuration:120)
        view.pan(by:10,assetDuration:0)
        view.reveal(-1,assetDuration:120);view.reveal(121,assetDuration:120)
        XCTAssertEqual(view.range(assetDuration:120),range)
        var tiny=AudioSourceViewport()
        tiny.zoom(by:100,around:0.002,assetDuration:0.005)
        XCTAssertEqual(tiny.range(assetDuration:0.005),0...0.005)
        view.zoom(by:1e-300,around:60,assetDuration:120)
        XCTAssertNil(view.fitted)
    }
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
