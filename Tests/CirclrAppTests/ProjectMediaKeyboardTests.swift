import XCTest
import AppKit
@testable import CirclrApp

final class ProjectMediaKeyboardTests:XCTestCase {
    func testFocusedActionUsesStandardActivationWithoutHijackingEditingShortcuts() {
        for code in [UInt16(36),76,49] {
            XCTAssertTrue(ProjectMediaActivationKey.accepts(keyCode:code,modifiers:[],markedText:false))
            XCTAssertFalse(ProjectMediaActivationKey.accepts(keyCode:code,modifiers:[],markedText:true),"IME composition must retain Return/Space")
            for modifiers in [NSEvent.ModifierFlags.command,.option,.control,.shift] {
                XCTAssertFalse(ProjectMediaActivationKey.accepts(keyCode:code,modifiers:modifiers,markedText:false))
            }
        }
        for code in [UInt16(48),53,51,123,124] {
            XCTAssertFalse(ProjectMediaActivationKey.accepts(keyCode:code,modifiers:[],markedText:false),"Traversal, Escape and editing keys belong to their existing routes")
        }
    }
}
