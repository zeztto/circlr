import XCTest
@testable import CirclrCore

final class AgentPitchBendChangeTests:XCTestCase {
    func testExplicitChangeDecodesAndUsesCoreValidation()throws {
        let change=try JSONDecoder().decode(AgentPitchBendChange.self,from:Data(#"{"kind":"insert","beat":1,"rawValue":12288}"#.utf8))
        let result=try MIDIPitchBendEditing.apply(change.resolved(),to:nil)
        XCTAssertEqual(result.sequence?.events,[.init(beat:1,kind:.value(12288))])
        for text in [#"{"kind":"clear","index":0}"#, #"{"kind":"insert","beat":1,"rawValue":0,"range":{"semitones":2,"cents":0}}"#, #"{"kind":"clear","unexpected":1}"#, #"{"kind":"clear","index":null}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(AgentPitchBendChange.self,from:Data(text.utf8)).resolved())
        }
    }
}
