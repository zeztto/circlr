import XCTest
@testable import CirclrApp

final class ChatGPTFeatureAvailabilityTests: XCTestCase {
    func testReleaseRoutesPersistedChatToLocalCommandsWithoutChangingPreference() {
        let saved=ChatGPTConsoleMode.chat
        let configurations: [[String:Any]?] = [nil, [:], ["CirclrAccountChatEnabled":false],
                                              ["CirclrAccountChatEnabled":"true"], ["CirclrAccountChatEnabled":1]]
        for info in configurations {
            let feature=ChatGPTFeatureAvailability(info:info)
            XCTAssertFalse(feature.accountChatEnabled)
            XCTAssertEqual(feature.consoleMode(preferred:saved),.command)
        }
        XCTAssertEqual(saved,.chat)
    }
    func testExplicitQABundlePreservesBothConsoleModes() {
        let feature=ChatGPTFeatureAvailability(info:["CirclrAccountChatEnabled":true])
        XCTAssertTrue(feature.accountChatEnabled)
        XCTAssertEqual(feature.consoleMode(preferred:.chat),.chat)
        XCTAssertEqual(feature.consoleMode(preferred:.command),.command)
    }
}
