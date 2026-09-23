import XCTest
@testable import CirclrApp
import CirclrCore

final class CanvasPlaybackLabelLODTests: XCTestCase {
    func testStructuralDensityDoesNotDependOnVisibleCables() {
        let threshold=CanvasPlaybackLabelLOD.denseProcessingCount
        XCTAssertFalse(CanvasPlaybackLabelLOD.compactPlayback(playing: true, stale: false,
            processingChildCount: threshold-1, editing: false))
        XCTAssertTrue(CanvasPlaybackLabelLOD.compactPlayback(playing: true, stale: false,
            processingChildCount: threshold, editing: false))
        XCTAssertTrue(CanvasPlaybackLabelLOD.compactPlayback(playing: true, stale: false,
            processingChildCount: threshold+12, editing: false))
        XCTAssertFalse(CanvasPlaybackLabelLOD.compactPlayback(playing: false, stale: false,
            processingChildCount: threshold, editing: false))
        XCTAssertFalse(CanvasPlaybackLabelLOD.compactPlayback(playing: true, stale: true,
            processingChildCount: threshold, editing: false))
        XCTAssertFalse(CanvasPlaybackLabelLOD.compactPlayback(playing: true, stale: false,
            processingChildCount: threshold, editing: true))
    }

    func testCompactDensePlaybackHidesOnlySmallDirectProcessingLabels() {
        let processing: [MusicCircleContent] = [
            .effect(Effect(.reverb)), .mix, .router(AudioRouter()), .output(trackID: "track")
        ]
        for content in processing {
            XCTAssertFalse(CanvasPlaybackLabelLOD.shows(content, screenRadius: 31.9,
                direct: true, compactPlayback: true, emphasized: false), "\(content)")
            XCTAssertTrue(CanvasPlaybackLabelLOD.shows(content, screenRadius: 32,
                direct: true, compactPlayback: true, emphasized: false))
            XCTAssertTrue(CanvasPlaybackLabelLOD.shows(content, screenRadius: 20,
                direct: true, compactPlayback: false, emphasized: false))
            XCTAssertTrue(CanvasPlaybackLabelLOD.shows(content, screenRadius: 20,
                direct: false, compactPlayback: true, emphasized: false))
            XCTAssertTrue(CanvasPlaybackLabelLOD.shows(content, screenRadius: 20,
                direct: true, compactPlayback: true, emphasized: true))
        }
    }

    func testTimeAndSoundSourceLabelsStayVisible() {
        let sources: [MusicCircleContent?] = [
            nil, .midi(laneID: "lane"), .audio(laneID: "lane", clipID: "clip"),
            .rhythmMIDI(trackID: "track"), .rhythmAudio(trackID: "track"),
            .instrument(trackID: "track")
        ]
        for content in sources {
            XCTAssertTrue(CanvasPlaybackLabelLOD.shows(content, screenRadius: 12,
                direct: true, compactPlayback: true, emphasized: false))
        }
    }
}
