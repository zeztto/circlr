import AppKit
import SwiftUI
import XCTest
@testable import CirclrApp

final class OverlayKeyboardTraversalTests:XCTestCase {
    func testTabAndShiftTabWrapInsideVisibleOverlayOrder() {
        let order=["search","close","filter","row"]
        XCTAssertEqual(OverlayKeyboardTraversal.next(in:order,current:nil,backward:false),"close")
        XCTAssertEqual(OverlayKeyboardTraversal.next(in:order,current:"row",backward:false),"search")
        XCTAssertEqual(OverlayKeyboardTraversal.next(in:order,current:"search",backward:true),"row")
        XCTAssertEqual(OverlayKeyboardTraversal.next(in:[],current:nil,backward:false),nil)
    }

    func testOnlyUnmodifiedTabAndEscapeAreCapturedOutsideIMEComposition() {
        XCTAssertEqual(OverlayKeyboardTraversal.action(keyCode:48,modifiers:[],markedText:false),.next)
        XCTAssertEqual(OverlayKeyboardTraversal.action(keyCode:48,modifiers:[.shift],markedText:false),.previous)
        XCTAssertEqual(OverlayKeyboardTraversal.action(keyCode:53,modifiers:[],markedText:false),.cancel)
        XCTAssertNil(OverlayKeyboardTraversal.action(keyCode:48,modifiers:[.command],markedText:false))
        XCTAssertNil(OverlayKeyboardTraversal.action(keyCode:53,modifiers:[.option],markedText:false))
        XCTAssertNil(OverlayKeyboardTraversal.action(keyCode:53,modifiers:[],markedText:true))
        XCTAssertNil(OverlayKeyboardTraversal.action(keyCode:48,modifiers:[],markedText:true))
    }

    func testLibraryFilterOptionsRemainKeyboardReachableWithDynamicFolders() {
        let folder=MediaLibraryFilterMenu.folder
        let kind=MediaLibraryFilterMenu.kind
        XCTAssertEqual(folder.triggerFocus,"folder-filter")
        XCTAssertEqual(folder.optionFocusKeys(folderCount:0),["folder-option-0"])
        XCTAssertEqual(folder.optionFocusKeys(folderCount:2),["folder-option-0","folder-option-1","folder-option-2"])
        XCTAssertEqual(kind.triggerFocus,"kind-filter")
        XCTAssertEqual(kind.optionFocusKeys(folderCount:2),["kind-option-0","kind-option-1","kind-option-2"])
        XCTAssertEqual(OverlayKeyboardTraversal.next(in:folder.optionFocusKeys(folderCount:2),current:"folder-option-2",backward:false),"folder-option-0")
        XCTAssertEqual(folder.optionHeight(in:600,folderCount:20),120)
        XCTAssertEqual(kind.optionHeight(in:600,folderCount:0),108)
        XCTAssertEqual(folder.optionHeight(in:900,folderCount:20),180)
    }

    func testLibraryFilterActivationLeavesModifiedShortcutsAvailable() {
        XCTAssertTrue(MediaLibraryFilterMenu.acceptsActivation([]))
        XCTAssertTrue(MediaLibraryFilterMenu.acceptsActivation([.capsLock]))
        let modified:[EventModifiers]=[[.option],[.command],[.control],[.shift],[.option,.shift]]
        for modifiers in modified {
            XCTAssertFalse(MediaLibraryFilterMenu.acceptsActivation(modifiers))
        }
    }

    func testLargeLibraryResultsUseIndexedFocusOrderAndWrapAtBoundaries() {
        let order=MediaLibraryKeyboardOrder(before:["search","folder-filter"],rows:.files(50_000),after:["preview","destination"])
        XCTAssertEqual(order.next(current:"folder-filter",backward:false),"file-toggle-0")
        XCTAssertEqual(order.next(current:"file-toggle-0",backward:false),"file-0")
        XCTAssertEqual(order.next(current:"file-49",backward:false),"file-toggle-50")
        XCTAssertEqual(order.next(current:"file-toggle-49999",backward:false),"file-49999")
        XCTAssertEqual(order.next(current:"file-49999",backward:false),"preview")
        XCTAssertEqual(order.next(current:"preview",backward:true),"file-49999")
        XCTAssertEqual(order.next(current:"destination",backward:false),"search")
        XCTAssertEqual(order.next(current:"search",backward:true),"destination")
        XCTAssertEqual(order.next(current:"file-50000",backward:false),"folder-filter")
    }

    func testLibraryFolderAndFilterFocusOrderIncludesOnlyExistingChoices() {
        let folders=MediaLibraryKeyboardOrder(before:["workspace"],rows:.folders(2),after:["clear-notice"])
        XCTAssertEqual(folders.next(current:"workspace",backward:false),"folder-open-0")
        XCTAssertEqual(folders.next(current:"folder-open-1",backward:false),"folder-remove-1")
        XCTAssertEqual(folders.next(current:"folder-remove-1",backward:false),"clear-notice")
        XCTAssertEqual(folders.next(current:"clear-notice",backward:false),"workspace")
        let empty=MediaLibraryKeyboardOrder(before:["workspace"],rows:.folders(0),after:[])
        XCTAssertEqual(empty.next(current:"workspace",backward:false),"workspace")
        let filter=MediaLibraryKeyboardOrder(before:[],rows:.filter(.kind,999),after:[])
        XCTAssertEqual(filter.next(current:"kind-option-2",backward:false),"kind-option-0")
        XCTAssertEqual(filter.next(current:"kind-option-0",backward:true),"kind-option-2")
    }

}
