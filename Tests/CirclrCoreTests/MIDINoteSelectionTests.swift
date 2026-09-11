import XCTest
@testable import CirclrCore

final class MIDINoteSelectionTests:XCTestCase {
    func note(_ id:ID,_ beat:Double,_ pitch:Int)->Note {var n=Note(beat:beat,length:0.5,pitch:pitch,velocity:87);n.id=id;return n}
    var notes:[Note] {[note("late",32.13,36),note("chord",0.13,64),note("near",0.1301,67),note("seed",0.13,36),note("rounding",0.13+1e-9,72)]}
    func testPitchSelectionIncludesHiddenTimeAndEverySelectedPitch() {
        XCTAssertEqual(MIDINoteSelection.applying(.samePitch,to:notes,selected:["seed"]),["seed","late"])
        XCTAssertEqual(MIDINoteSelection.applying(.samePitch,to:notes,selected:["seed","chord"]),["seed","late","chord"])
    }
    func testStartSelectionPreservesActualGrooveAndUnionsSeeds() {
        XCTAssertEqual(MIDINoteSelection.applying(.sameStart,to:notes,selected:["seed"]),["seed","chord","rounding"])
        XCTAssertEqual(MIDINoteSelection.applying(.sameStart,to:notes.reversed(),selected:["seed","late"]),["seed","chord","rounding","late"])
        XCTAssertEqual(MIDINoteSelection.applying(.sameStart,to:notes,selected:["near"]),["near"])
    }
    func testAllClearInvertAndStaleSelections() {
        let all=Set(notes.map(\.id))
        XCTAssertEqual(MIDINoteSelection.applying(.all,to:notes,selected:[]),all)
        XCTAssertEqual(MIDINoteSelection.applying(.clear,to:notes,selected:all),[])
        XCTAssertEqual(MIDINoteSelection.applying(.invert,to:notes,selected:["seed","missing"]),all.subtracting(["seed"]))
        XCTAssertEqual(MIDINoteSelection.applying(.invert,to:notes,selected:all),[])
        for action in [MIDINoteSelection.Action.sameStart,.samePitch] {
            XCTAssertEqual(MIDINoteSelection.applying(action,to:notes,selected:["missing"]),[])
            XCTAssertEqual(MIDINoteSelection.applying(action,to:[],selected:["seed"]),[])
        }
    }
    func testDenseUnsortedSelectionUsesDirectSeedsWithoutTransitiveExpansion() {
        var lane=Lane(trackID:"keys");lane.notes=(0..<10000).reversed().map{note("n\($0)",Double($0/4)+0.13,60+$0%4)}
        lane.audio=[AudioClip(assetID:"tone",duration:1)];let original=lane
        let selected=Set((0..<2500).map{"n\($0*4)"})
        XCTAssertEqual(MIDINoteSelection.applying(.sameStart,to:lane.notes,selected:selected).count,10000)
        XCTAssertEqual(lane,original)
        let near=[note("a",1,60),note("b",1+0.75e-7,61),note("c",1+1.5e-7,62)]
        XCTAssertEqual(MIDINoteSelection.applying(.sameStart,to:near,selected:["a"]),["a","b"])
    }
}
