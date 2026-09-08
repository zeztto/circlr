import XCTest
@testable import CirclrCore

final class RecordingAuthorizationTests:XCTestCase {
    func testStopAndLateApprovalCannotStartOrCancelNewRecording() {
        var gate=RecordingAuthorization()
        let first=gate.begin(projectID:"p",revision:3,address:.album,trackID:"t",laneID:"l")
        gate.cancel()
        XCTAssertFalse(gate.consume(first,projectID:"p",revision:3,address:.album,trackID:"t",laneID:"l"))
        let second=gate.begin(projectID:"p",revision:3,address:.album,trackID:"t",laneID:"l")
        XCTAssertFalse(gate.consume(first,projectID:"p",revision:3,address:.album,trackID:"t",laneID:"l"));XCTAssertEqual(gate.pending,second)
        XCTAssertTrue(gate.consume(second,projectID:"p",revision:3,address:.album,trackID:"t",laneID:"l"));XCTAssertNil(gate.pending)
        XCTAssertFalse(gate.consume(second,projectID:"p",revision:3,address:.album,trackID:"t",laneID:"l"))
    }
    func testProjectEditOrSelectionChangeInvalidatesPermissionEvenAtSameAddress() {
        for mismatch in 0..<5 {
            var gate=RecordingAuthorization();let request=gate.begin(projectID:"p",revision:3,address:.album,trackID:"t",laneID:"l")
            XCTAssertFalse(gate.consume(request,projectID:mismatch==0 ? "other":"p",revision:mismatch==1 ? 4:3,address:mismatch==2 ? .sound:.album,trackID:mismatch==3 ? "other":"t",laneID:mismatch==4 ? "other":"l"));XCTAssertNil(gate.pending)
        }
    }
}
