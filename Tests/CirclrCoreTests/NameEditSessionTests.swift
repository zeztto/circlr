import XCTest
@testable import CirclrCore

final class NameEditSessionTests:XCTestCase {
    struct Context:Equatable {var target:String;var revision:Int}
    let context=Context(target:"chorus",revision:12)

    func testTypingStaysADraftUntilOneExplicitResolution()throws {
        var draft=NameEditSession<Context>();draft.begin(value:"후렴",context:context)
        for text in ["후","후렴 2","후렴 2 · Midnight"] {draft.type(text,value:"후렴",context:context)}
        XCTAssertEqual(try draft.resolve(value:"후렴",context:context),.apply("후렴 2 · Midnight"))
        // Consume before a synchronous model update can trigger another end-edit notification.
        draft.reset(value:"후렴 2 · Midnight")
        XCTAssertEqual(try draft.resolve(value:"후렴 2 · Midnight",context:context),.unchanged)
    }
    func testCompositionCannotCommitItsIntermediateText()throws {
        var draft=NameEditSession<Context>();draft.type("ㅎ",value:"후렴",context:context)
        XCTAssertEqual(try draft.resolve(value:"후렴",context:context,isComposing:true),.composing)
        XCTAssertTrue(draft.isDirty);XCTAssertEqual(draft.text,"ㅎ")
        draft.type("후렴의 밤",value:"후렴",context:context)
        XCTAssertEqual(try draft.resolve(value:"후렴",context:context),.apply("후렴의 밤"))
    }
    func testUnicodeSymbolsEmojiAndInternalSpacingSurvive()throws {
        let name="여름밤  · 真夜中の街 / f0r h3r 🎹 👩🏽‍🎤"
        var draft=NameEditSession<Context>();draft.type("  \(name)  ",value:"old",context:context)
        XCTAssertEqual(try draft.resolve(value:"old",context:context),.apply(name))
    }
    func testBlankMultilineAndOversizedNewNamesAreRejected() {
        for text in ["", " \t ", "Verse\nChorus", "Verse\rChorus", String(repeating:"가",count:257)] {
            var draft=NameEditSession<Context>();draft.type(text,value:"old",context:context)
            XCTAssertThrowsError(try draft.resolve(value:"old",context:context))
            XCTAssertEqual(draft.text,text)
        }
    }
    func testExistingLongNameIsNeverTruncatedOnPristineBlur()throws {
        let name=String(repeating:"기존 이름 ",count:100)
        var draft=NameEditSession<Context>();draft.begin(value:name,context:context)
        XCTAssertEqual(try draft.resolve(value:name,context:context),.unchanged)
        XCTAssertEqual(draft.text,name)
    }
    func testEscapeResetsToLatestModelAndConsumesTheDraft()throws {
        var draft=NameEditSession<Context>();draft.type("draft",value:"old",context:context)
        draft.reset(value:"다른 에이전트가 바꾼 이름")
        XCTAssertFalse(draft.isDirty)
        XCTAssertEqual(try draft.resolve(value:"다른 에이전트가 바꾼 이름",context:context),.unchanged)
    }
    func testExternalValueRevisionAndTargetChangesCannotBeOverwritten() {
        var draft=NameEditSession<Context>();draft.type("local",value:"old",context:context)
        XCTAssertThrowsError(try draft.resolve(value:"external",context:context))
        XCTAssertThrowsError(try draft.resolve(value:"old",context:Context(target:"verse",revision:12)))
        XCTAssertThrowsError(try draft.resolve(value:"old",context:Context(target:"chorus",revision:13)))
        draft.refresh(value:"external",context:context,editing:true)
        XCTAssertEqual(draft.text,"local")
    }
    func testPristineFocusAdoptsNewRevisionBeforeTyping()throws {
        var draft=NameEditSession<Context>();draft.begin(value:"old",context:context)
        let next=Context(target:"chorus",revision:13)
        draft.refresh(value:"external",context:next,editing:true)
        draft.type("new",value:"external",context:next)
        XCTAssertEqual(try draft.resolve(value:"external",context:next),.apply("new"))
    }
    func testTypingBeforeFocusCallbackStillCapturesTheOriginalTarget()throws {
        var draft=NameEditSession<Context>();draft.type("new",value:"old",context:context)
        XCTAssertEqual(try draft.resolve(value:"old",context:context),.apply("new"))
    }
    func testOuterWhitespaceOnlyChangeDoesNotCreateUndoEntry()throws {
        var draft=NameEditSession<Context>();draft.type("  후렴  ",value:"후렴",context:context)
        XCTAssertEqual(try draft.resolve(value:"후렴",context:context),.unchanged)
    }
}
