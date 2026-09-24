import AppKit
import XCTest
@testable import CirclrApp

final class PlaybackSpaceShortcutTests:XCTestCase {
    func testOnlyPlainSpaceRequestsTransport() {
        XCTAssertTrue(PlaybackSpaceShortcut.accepts(keyCode:49,modifiers:[],textInputActive:false))
        // Caps Lock may be enabled while the user presses an otherwise plain Space.
        XCTAssertTrue(PlaybackSpaceShortcut.accepts(keyCode:49,modifiers:[.capsLock],textInputActive:false))
        XCTAssertFalse(PlaybackSpaceShortcut.accepts(keyCode:36,modifiers:[],textInputActive:false))
        let modified:[NSEvent.ModifierFlags]=[[.option],[.command],[.control],[.shift],[.function],[.option,.shift]]
        for modifiers in modified {
            XCTAssertFalse(PlaybackSpaceShortcut.accepts(keyCode:49,modifiers:modifiers,textInputActive:false))
        }
    }

    func testSpaceDoesNotStartTransportDuringTextOrIMEEditing() {
        XCTAssertFalse(PlaybackSpaceShortcut.accepts(keyCode:49,modifiers:[],textInputActive:true))
        XCTAssertFalse(PlaybackSpaceShortcut.accepts(keyCode:49,modifiers:[.option],textInputActive:true))
    }

    func testViewingModePassesFnSpaceThroughBothKeyRoutingLayers() {
        XCTAssertTrue(ViewingModeKeyRouting.passesToSystem(keyCode:49,modifiers:[.function]))
        XCTAssertFalse(PlaybackSpaceShortcut.accepts(keyCode:49,modifiers:[.function],textInputActive:false))
        XCTAssertFalse(ViewingModeKeyRouting.passesToSystem(keyCode:49,modifiers:[]))
        XCTAssertFalse(ViewingModeKeyRouting.passesToSystem(keyCode:49,modifiers:[.option]))
        XCTAssertFalse(ViewingModeKeyRouting.passesToSystem(keyCode:3,modifiers:[.function]))
    }
}
