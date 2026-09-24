import AppKit
import XCTest
@testable import CirclrApp

@MainActor final class AgentConsoleFollowTests:XCTestCase {
    private func events(_ ids:ClosedRange<Int>)->[ActivityEvent] {
        ids.map {ActivityEvent(id:$0,time:Date(timeIntervalSince1970:Double($0)),source:"검증",message:"이벤트 \($0)",revision:0)}
    }

    func testNewEventsPreserveScrolledHistoryEvenWhenStoreTruncatesAtFiveHundred() {
        var follow=ConsoleLogFollowState()
        follow.load(events(1...500),sequence:500)
        follow.viewportChanged(bottomY:122,viewportHeight:122)
        follow.viewportChanged(bottomY:280,viewportHeight:122)
        XCTAssertFalse(follow.isFollowing)
        let frozen=follow.displayedEvents.map(\.id)

        follow.receive(events(2...501),sequence:501)
        XCTAssertEqual(follow.displayedEvents.map(\.id),frozen)
        XCTAssertEqual(follow.unreadCount,1)
        follow.receive(events(8...507),sequence:507)
        XCTAssertEqual(follow.displayedEvents.map(\.id),frozen)
        XCTAssertEqual(follow.unreadCount,7)

        follow.jumpToLatest()
        XCTAssertTrue(follow.isFollowing)
        XCTAssertEqual(follow.unreadCount,0)
        XCTAssertEqual(follow.displayedEvents.first?.id,8)
        XCTAssertEqual(follow.displayedEvents.last?.id,507)
    }

    func testScrollingBackToBottomResumesFollowingAndCountsBurstBySequence() {
        var follow=ConsoleLogFollowState()
        follow.load(events(1...3),sequence:3)
        follow.viewportChanged(bottomY:122,viewportHeight:122)
        follow.viewportChanged(bottomY:150,viewportHeight:122)
        XCTAssertFalse(follow.isFollowing)
        follow.receive(events(1...7),sequence:7)
        XCTAssertEqual(follow.unreadCount,4)
        follow.viewportChanged(bottomY:121,viewportHeight:122)
        XCTAssertTrue(follow.isFollowing)
        XCTAssertEqual(follow.unreadCount,0)
        XCTAssertEqual(follow.displayedEvents.last?.id,7)
    }

    func testContentGrowthDuringAutomaticScrollDoesNotImpersonateUserScroll() {
        var follow=ConsoleLogFollowState()
        follow.load(events(1...3),sequence:3)
        follow.viewportChanged(bottomY:122,viewportHeight:122)
        follow.receive(events(1...4),sequence:4)
        follow.viewportChanged(bottomY:170,viewportHeight:122)
        XCTAssertTrue(follow.isFollowing)
        follow.viewportChanged(bottomY:122,viewportHeight:122)
        follow.viewportChanged(bottomY:170,viewportHeight:122)
        XCTAssertFalse(follow.isFollowing)
    }

    func testUnchangedBottomGeometryCannotLeaveAutomaticFollowGuardStuck() {
        var follow=ConsoleLogFollowState()
        follow.load(events(1...3),sequence:3)
        let oldGeneration=follow.scrollGeneration
        follow.receive(events(1...4),sequence:4)
        follow.automaticScrollCompleted(generation:oldGeneration)
        follow.automaticScrollIssued(generation:follow.scrollGeneration)
        follow.viewportChanged(bottomY:170,viewportHeight:122)
        XCTAssertTrue(follow.isFollowing)
        follow.automaticScrollCompleted(generation:follow.scrollGeneration)
        XCTAssertFalse(follow.isFollowing)
    }

    func testStaleOffBottomGeometryBeforeIssuedScrollDoesNotDetachAfterSuccessfulScroll() {
        var follow=ConsoleLogFollowState()
        follow.load(events(1...3),sequence:3)
        follow.viewportChanged(bottomY:122,viewportHeight:122)
        follow.receive(events(1...4),sequence:4)
        follow.viewportChanged(bottomY:170,viewportHeight:122) // Layout growth before scrollTo.
        let generation=follow.scrollGeneration
        follow.automaticScrollIssued(generation:generation)
        follow.automaticScrollCompleted(generation:generation)
        XCTAssertTrue(follow.isFollowing)
        follow.viewportChanged(bottomY:170,viewportHeight:122)
        XCTAssertFalse(follow.isFollowing)
    }

    func testBottomObservationAfterIssuedScrollOverridesEarlierOffBottomObservation() {
        var follow=ConsoleLogFollowState()
        follow.load(events(1...3),sequence:3)
        follow.automaticScrollIssued(generation:follow.scrollGeneration)
        follow.viewportChanged(bottomY:170,viewportHeight:122)
        follow.viewportChanged(bottomY:122,viewportHeight:122)
        follow.automaticScrollCompleted(generation:follow.scrollGeneration)
        XCTAssertTrue(follow.isFollowing)
    }

    func testWheelInputDetachesDuringUninterruptedBurstBeforeAnyAutoScrollTimerCompletes() {
        var follow=ConsoleLogFollowState()
        follow.load(events(1...3),sequence:3)
        follow.viewportChanged(bottomY:122,viewportHeight:122)
        follow.receive(events(1...4),sequence:4)
        let inFlightGeneration=follow.scrollGeneration
        follow.automaticScrollIssued(generation:inFlightGeneration)
        follow.userDidScroll() // Explicit wheel event arrives while a programmatic scroll is pending.
        XCTAssertFalse(follow.isFollowing)
        follow.viewportChanged(bottomY:170,viewportHeight:122)

        for sequence in 5...20 {
            follow.receive(events(1...sequence),sequence:sequence)
            follow.automaticScrollCompleted(generation:inFlightGeneration)
        }
        XCTAssertFalse(follow.isFollowing)
        XCTAssertEqual(follow.displayedEvents.last?.id,4)
        XCTAssertEqual(follow.unreadCount,16)
    }

    func testWheelAtAlreadyBottomResumesAfterNoMovement() {
        var follow=ConsoleLogFollowState()
        follow.load(events(1...3),sequence:3)
        follow.viewportChanged(bottomY:122,viewportHeight:122)
        follow.userDidScroll()
        XCTAssertFalse(follow.isFollowing)
        XCTAssertTrue(follow.finishUserScroll())
        XCTAssertTrue(follow.isFollowing)
    }

    func testKeyboardOrAccessibilityScrollGeometryDetachesDuringSubHundredMillisecondEventBurst() {
        var follow=ConsoleLogFollowState()
        follow.load(events(1...3),sequence:3)
        follow.viewportChanged(anchorY:80,bottomY:122,viewportHeight:122)
        for sequence in 4...20 {
            follow.receive(events(1...sequence),sequence:sequence)
            follow.viewportChanged(anchorY:80,bottomY:170,viewportHeight:122)
            XCTAssertTrue(follow.isFollowing)
        }
        // A keyboard/VoiceOver scroll moves the content origin and bottom marker together.
        follow.viewportChanged(anchorY:104,bottomY:194,viewportHeight:122)
        XCTAssertFalse(follow.isFollowing)
        follow.receive(events(1...30),sequence:30)
        XCTAssertEqual(follow.displayedEvents.last?.id,20)
        XCTAssertEqual(follow.unreadCount,10)
    }

    func testNewRowsAloneDoNotLookLikeKeyboardScrolling() {
        var follow=ConsoleLogFollowState()
        follow.load(events(1...3),sequence:3)
        follow.viewportChanged(anchorY:80,bottomY:122,viewportHeight:122)
        follow.receive(events(1...4),sequence:4)
        follow.viewportChanged(anchorY:80,bottomY:180,viewportHeight:122)
        XCTAssertTrue(follow.isFollowing)
        follow.viewportChanged(anchorY:22,bottomY:122,viewportHeight:122)
        XCTAssertTrue(follow.isFollowing)
    }

    func testFiveHundredEventEvictionCompensationDoesNotImpersonateAccessibilityScroll() {
        var follow=ConsoleLogFollowState()
        follow.load(events(1...500),sequence:500)
        XCTAssertEqual(follow.anchorEventID,500)
        follow.viewportChanged(anchorY:90,bottomY:122,viewportHeight:122)
        follow.receive(events(2...501),sequence:501)
        XCTAssertEqual(follow.anchorEventID,500) // The same row survives first-row eviction.
        // SwiftUI may compensate by moving the content origin; the retained row stays put.
        follow.viewportChanged(anchorY:90,bottomY:170,viewportHeight:122)
        XCTAssertTrue(follow.isFollowing)
        follow.viewportChanged(anchorY:114,bottomY:194,viewportHeight:122)
        XCTAssertFalse(follow.isFollowing)
        follow.receive(events(3...502),sequence:502)
        XCTAssertEqual(follow.displayedEvents.last?.id,501)
        XCTAssertEqual(follow.unreadCount,1)
    }

    func testFiveHundredHistoryKeepsRetainedAnchorInBoundedEagerTail() {
        var follow=ConsoleLogFollowState()
        follow.load(events(1...500),sequence:500)
        XCTAssertEqual(follow.displayedEvents.count,500)
        XCTAssertEqual(follow.lazyPrefixEvents.count,436)
        XCTAssertEqual(follow.eagerTailEvents.count,ConsoleLogFollowState.eagerTailLimit)
        for sequence in 501...565 {
            follow.receive(events((sequence-499)...sequence),sequence:sequence)
            XCTAssertEqual(follow.displayedEvents.count,500)
            XCTAssertEqual(follow.eagerTailEvents.count,64)
            XCTAssertTrue(follow.eagerTailEvents.contains(where:{$0.id==follow.anchorEventID}))
        }
        XCTAssertNotEqual(follow.anchorEventID,500)
    }

    func testReopenInvalidatesOldScrollProxyButSchedulesNewViewImmediately() throws {
        var scheduler=ConsoleScrollScheduler()
        scheduler.didAppear()
        let old=try XCTUnwrap(scheduler.schedule())
        XCTAssertNil(scheduler.schedule()) // Same view coalesces work within one frame.
        scheduler.didDisappear()
        scheduler.didAppear()
        let current=try XCTUnwrap(scheduler.schedule())
        XCTAssertNotEqual(old,current)
        XCTAssertFalse(scheduler.consume(old)) // Old ScrollViewProxy must never be used.
        XCTAssertTrue(scheduler.consume(current))
        XCTAssertNotNil(scheduler.schedule()) // New view remains schedulable.
    }
}
