import AppKit
import XCTest
@testable import CirclrApp

final class WorkspaceOverlayLayoutTests:XCTestCase {
    func testNarrowWorkspaceKeepsPickerClearOfTwoRowHeaderAndWindowEdges() {
        for viewport in [CGSize(width:700,height:600),CGSize(width:720,height:900),CGSize(width:900,height:800)] {
            let chrome=WorkspaceChromeLayout(width:viewport.width)
            let overlay=WorkspaceOverlayLayout(viewport:viewport,headerHeight:chrome.headerHeight)
            XCTAssertTrue(chrome.twoHeaderRows)
            XCTAssertGreaterThanOrEqual(overlay.topInset,chrome.headerHeight+16)
            XCTAssertGreaterThanOrEqual(viewport.width-overlay.pickerSize.width,32)
            XCTAssertLessThanOrEqual(overlay.topInset+overlay.pickerSize.height,viewport.height-16)
            XCTAssertGreaterThan(overlay.pickerSize.height,0)
        }
    }

    func testWideWorkspaceKeepsOriginalPickerLimitBelowOneRowHeader() {
        let viewport=CGSize(width:1600,height:900)
        let chrome=WorkspaceChromeLayout(width:viewport.width)
        let overlay=WorkspaceOverlayLayout(viewport:viewport,headerHeight:chrome.headerHeight)
        XCTAssertFalse(chrome.twoHeaderRows)
        XCTAssertEqual(overlay.topInset,82)
        XCTAssertEqual(overlay.pickerSize,CGSize(width:850,height:560))
    }

    func testHeaderBreakpointReflowsOverlayBeforeItCanCoverSecondRow() {
        let viewport=CGSize(width:1279,height:700)
        let chrome=WorkspaceChromeLayout(width:viewport.width)
        let overlay=WorkspaceOverlayLayout(viewport:viewport,headerHeight:chrome.headerHeight)
        XCTAssertEqual(chrome.headerHeight,116)
        XCTAssertEqual(overlay.topInset,132)
        XCTAssertLessThanOrEqual(overlay.topInset+overlay.pickerSize.height,viewport.height-16)
    }
}
