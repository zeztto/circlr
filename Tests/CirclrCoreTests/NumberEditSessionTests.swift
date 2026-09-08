import XCTest
@testable import CirclrCore

final class NumberEditSessionTests: XCTestCase {
    func testUntouchedAndCancelledDraftNeverRoundOriginal() throws {
        let original=0.123456789012345
        var edit=NumberEditSession<Int>();edit.begin(value:original,context:1)
        XCTAssertNotEqual(Double(edit.text),original)
        XCTAssertNil(try edit.resolve(value:original,context:1,range:0...1))
        edit.text="0.8";edit.reset(value:original)
        XCTAssertNil(try edit.resolve(value:original,context:1,range:0...1))
        XCTAssertEqual(Double(NumberEditSession<Int>.format(0.00003125)),0.00003125)
    }
    func testTypingIsDraftAndConsumedCommitCannotRepeatOnBlur() throws {
        var edit=NumberEditSession<Int>();edit.begin(value:4000,context:1)
        for text in ["1","12","120","1200"] {edit.text=text;XCTAssertTrue(edit.isDirty)}
        let next=try XCTUnwrap(edit.resolve(value:4000,context:1,range:40...20000))
        XCTAssertEqual(next,1200);edit.reset(value:next)
        XCTAssertNil(try edit.resolve(value:4000,context:1,range:40...20000))
    }
    func testInvalidNumbersRangesAndIntegers() throws {
        var edit=NumberEditSession<Int>();edit.begin(value:8,context:1)
        for text in ["", "-", "abc", "nan", "inf", "1e999", "0", "1025", "2.5"] {
            edit.text=text
            XCTAssertThrowsError(try edit.resolve(value:8,context:1,range:1...1024,integerOnly:true),text)
        }
        edit.text=" 16 ";XCTAssertEqual(try edit.resolve(value:8,context:1,range:1...1024,integerOnly:true),16)
        edit.text="8.0";XCTAssertNil(try edit.resolve(value:8,context:1,range:1...1024,integerOnly:true))
    }
    func testDirtyDraftRejectsChangedTargetRevisionOrValue() throws {
        var edit=NumberEditSession<String>();edit.begin(value:0.5,context:"track-a:r1")
        edit.text="0.7";edit.refresh(value:0.6,context:"track-a:r2",editing:true)
        XCTAssertEqual(edit.text,"0.7")
        XCTAssertThrowsError(try edit.resolve(value:0.6,context:"track-a:r2",range:0...1))
        XCTAssertThrowsError(try edit.resolve(value:0.5,context:"track-b:r1",range:0...1))
        XCTAssertThrowsError(try edit.resolve(value:0.6,context:"track-a:r1",range:0...1))
    }
    func testPristineTabFieldAdoptsPreviousFieldsCommit() throws {
        var edit=NumberEditSession<Int>();edit.begin(value:12,context:1)
        edit.refresh(value:12,context:2,editing:true)
        edit.text="24"
        XCTAssertEqual(try edit.resolve(value:12,context:2,range:0...60),24)
        edit.refresh(value:30,context:3,editing:false)
        XCTAssertEqual(edit.text,"30")
        XCTAssertNil(try edit.resolve(value:30,context:3,range:0...60))
    }
    func testTypingBeforeFocusCallbackRetainsFirstCharacter() throws {
        var edit=NumberEditSession<Int>();edit.reset(value:1)
        edit.type("0",value:1,context:2)
        XCTAssertTrue(edit.hasBaseline)
        edit.refresh(value:1,context:2,editing:edit.isDirty)
        edit.type("0.8",value:1,context:2)
        XCTAssertEqual(try edit.resolve(value:1,context:2,range:0...4),0.8)
    }
    func testRoundedSourceTimeDisplayPreservesRawValueAndAcceptsPreciseInput()throws {
        for (presentation,text,unit) in [(NumberEditPresentation.sourceSeconds,"9.032","초"),(.sourceMilliseconds,"9.0","ms")] {
            let raw=9.031723050019
            var edit=NumberEditSession<Int>(presentation:presentation);edit.begin(value:raw,context:1)
            XCTAssertEqual(edit.text,text);XCTAssertNil(try edit.resolve(value:raw,context:1,range:0...32))
            edit.text="10.123456789";XCTAssertEqual(try edit.resolve(value:raw,context:1,range:0...32),10.123456789)
            edit.text="33"
            XCTAssertThrowsError(try edit.resolve(value:raw,context:1,range:0...32)){XCTAssertTrue(String(describing:$0).contains(unit))}
            edit.reset(value:raw);XCTAssertNil(try edit.resolve(value:raw,context:2,range:0...32))
        }
    }
}
