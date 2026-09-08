import XCTest
@testable import CirclrAudio

final class MediaPreviewTests:XCTestCase {
    final class Player:MediaPreviewPlayer,@unchecked Sendable {
        var events:[String]=[]
        var onPrepare:(()->Void)?
        var onStart:(()->Void)?
        var startSucceeds=true
        var playing=false
        func prepare()throws{events.append("prepare");onPrepare?()}
        func startMuted()->Bool{events.append("start-muted");onStart?();return startSucceeds}
        func makeAudible(){events.append("audible")}
        func stop(){events.append("stop")}
        var isPlaying:Bool{playing}
        var seconds:Double{0.25}
    }
    func testNormalAndFailedStartAlwaysStopOnTheWorker()async throws {
        let player=Player()
        try await MediaPreview.run(player,cancellation:MediaPreviewCancellation()){_ in}
        XCTAssertEqual(player.events,["prepare","start-muted","audible","stop"])
        let failed=Player();failed.startSucceeds=false
        do{try await MediaPreview.run(failed,cancellation:MediaPreviewCancellation()){_ in};XCTFail("Failed start succeeded")}catch{}
        XCTAssertEqual(failed.events,["prepare","start-muted","stop"])
    }
    func testCancellationBeforePreparationDoesNotStart()async {
        let player=Player(),token=MediaPreviewCancellation();token.cancel()
        do{try await MediaPreview.run(player,cancellation:token){_ in};XCTFail("Cancelled preview succeeded")}catch{XCTAssertTrue(error is CancellationError)}
        XCTAssertEqual(player.events,["stop"])
    }
    func testCancellationWhileDeviceStartIsBlockedNeverMakesLateStartAudible()async {
        let player=Player(),token=MediaPreviewCancellation(),release=DispatchSemaphore(value:0),entered=expectation(description:"Device start entered")
        player.onStart={entered.fulfill();_ = release.wait(timeout:.now()+3)}
        let task=Task.detached{try await MediaPreview.run(player,cancellation:token){_ in}}
        await fulfillment(of:[entered],timeout:2)
        token.cancel();release.signal()
        do{try await task.value;XCTFail("Late start became audible")}catch{XCTAssertTrue(error is CancellationError)}
        XCTAssertEqual(player.events,["prepare","start-muted","stop"])
    }
    func testCancellationDuringPreparationPreventsStartingQueue()async {
        let player=Player(),token=MediaPreviewCancellation()
        player.onPrepare={token.cancel()}
        do{try await MediaPreview.run(player,cancellation:token){_ in};XCTFail("Cancelled prepare succeeded")}catch{XCTAssertTrue(error is CancellationError)}
        XCTAssertEqual(player.events,["prepare","stop"])
    }
    func testCancellationDuringPlaybackStopsWithoutAnotherUpdate()async {
        let player=Player(),token=MediaPreviewCancellation();player.playing=true
        do{try await MediaPreview.run(player,cancellation:token){seconds in XCTAssertEqual(seconds,0.25);token.cancel()};XCTFail("Cancelled playback succeeded")}catch{XCTAssertTrue(error is CancellationError)}
        XCTAssertEqual(player.events,["prepare","start-muted","audible","stop"])
    }
}
