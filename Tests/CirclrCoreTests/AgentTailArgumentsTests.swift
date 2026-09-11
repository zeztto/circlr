import XCTest
@testable import CirclrCore

final class AgentTailArgumentsTests:XCTestCase {
    func testLegacyRenderArgumentsDecodeAutomaticTail()throws {
        for method in ["bounce","export"] {
            let json="""
            {"id":"legacy","method":"\(method)","arguments":{"useID":"use","trackID":"track","path":"/tmp/new.wav"}}
            """
            let request=try JSONDecoder().decode(AgentRequest.self,from:Data(json.utf8))
            XCTAssertNil(request.arguments?.tailSeconds)
            let roundTrip=try JSONDecoder().decode(AgentRequest.self,from:JSONEncoder().encode(request))
            XCTAssertNil(roundTrip.arguments?.tailSeconds)
            XCTAssertEqual(roundTrip.arguments?.useID,"use")
            let object=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(request.arguments)) as? [String:Any])
            XCTAssertNil(object["tailSeconds"])
        }
    }
    func testExplicitZeroFractionAndMaximumTailSurviveTransport()throws {
        for seconds in [0.0,12.5,120.0] {
            let json="""
            {"id":"manual","method":"bounce","arguments":{"tailSeconds":\(seconds),"useID":"use","trackID":"track"}}
            """
            let request=try JSONDecoder().decode(AgentRequest.self,from:Data(json.utf8))
            XCTAssertEqual(request.arguments?.tailSeconds,seconds)
            let roundTrip=try JSONDecoder().decode(AgentRequest.self,from:JSONEncoder().encode(request))
            XCTAssertEqual(roundTrip.arguments?.tailSeconds,seconds)
        }
    }
    func testTailRejectsNonNumericTransportValues() {
        for value in ["true","\"2\"","{}","[]"] {
            let json="{\"tailSeconds\":\(value)}"
            XCTAssertThrowsError(try JSONDecoder().decode(AgentArguments.self,from:Data(json.utf8)))
        }
    }
}
