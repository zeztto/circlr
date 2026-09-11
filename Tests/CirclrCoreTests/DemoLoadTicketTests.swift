import XCTest
@testable import CirclrCore

final class DemoLoadTicketTests:XCTestCase {
    func testExactRequestCanApplyOnlyBeforeCancellationOrReplacement() throws {
        let project=try ProjectStarters.make(id:"blank")
        let ticket=DemoLoadTicket(generation:1,project:project,projectPath:nil,mediaPath:"/owned/demo.circlr")
        XCTAssertTrue(ticket.canApply(generation:1,project:project,projectPath:nil,mediaPath:"/owned/demo.circlr",cancelled:false))
        XCTAssertFalse(ticket.canApply(generation:1,project:project,projectPath:nil,mediaPath:"/owned/demo.circlr",cancelled:true))
        XCTAssertFalse(ticket.canApply(generation:2,project:project,projectPath:nil,mediaPath:"/owned/demo.circlr",cancelled:false))
    }
    func testLateCompletionCannotReplaceNewProjectOrMusicEdit() throws {
        let original=try ProjectStarters.make(id:"blank")
        let ticket=DemoLoadTicket(generation:4,project:original,projectPath:nil,mediaPath:nil)
        var edited=original;edited.sections[0].lanes[0].notes=[Note(beat:0)]
        XCTAssertFalse(ticket.canApply(generation:4,project:edited,projectPath:nil,mediaPath:nil,cancelled:false))
        edited=original;edited.musicRevision += 1
        XCTAssertFalse(ticket.canApply(generation:4,project:edited,projectPath:nil,mediaPath:nil,cancelled:false))
        XCTAssertFalse(ticket.canApply(generation:4,project:try ProjectStarters.make(id:"blank"),projectPath:nil,mediaPath:nil,cancelled:false))
    }
    func testLayoutChangesAlsoPreventLateReplacementWithoutMusicRevisionChange() throws {
        let original=try ProjectStarters.make(id:"blank")
        let ticket=DemoLoadTicket(generation:1,project:original,projectPath:nil,mediaPath:nil)
        var edited=original;edited.arrangements[0].layout.pan=Point(33,44)
        XCTAssertEqual(edited.musicRevision,original.musicRevision)
        XCTAssertFalse(ticket.canApply(generation:1,project:edited,projectPath:nil,mediaPath:nil,cancelled:false))
    }
    func testSaveAndMediaRootChangesInvalidateRequestEvenWithIdenticalProject() throws {
        let original=try ProjectStarters.make(id:"blank")
        let ticket=DemoLoadTicket(generation:1,project:original,projectPath:nil,mediaPath:nil)
        XCTAssertFalse(ticket.canApply(generation:1,project:original,projectPath:"/saved/song.circlr",mediaPath:nil,cancelled:false))
        XCTAssertFalse(ticket.canApply(generation:1,project:original,projectPath:nil,mediaPath:"/saved/song.circlr",cancelled:false))
    }
}
