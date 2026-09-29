import XCTest
import AppKit
@testable import CirclrApp

@MainActor
final class ChatGPTConsoleBrandingTests: XCTestCase {
    func testOfficialSignInVectorLoadsAsNativeImage() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let image = try XCTUnwrap(ChatGPTConsoleBranding.loadLogo(from: root.appendingPathComponent("Resources")))
        XCTAssertEqual(image.size.width, 21)
        XCTAssertEqual(image.size.height, 21)
        XCTAssertTrue(image.isValid)
    }
}
