import XCTest
@testable import CirclrCore

final class ConnectionWorkspaceStateTests:XCTestCase {
    let ports=CirclePort.ports(for:MusicCircleContent.effect(Effect(.gain)))
    let source=CircleAddress.music(arrangementID:"arrangement",useID:"use",nodeID:"source")
    let target=CircleAddress.music(arrangementID:"arrangement",useID:"use",nodeID:"target")
    var edge:CirclePortConnection {.init(edgeID:"edge",from:source,to:target,signal:.audio)}
    var choice:ConnectionTargetChoice {.init(endpoint:edge.to,title:"북유럽 신스",detail:"IN 스테레오",ordinal:nil)}
    func fixture()->ConnectionWorkspaceState {
        var value=ConnectionWorkspaceState();value.ownPortID=CirclePort.audioOutput
        value.target=edge.to;value.query="북유럽";value.firstOctant = .north;value.secondOctant = .south
        value.replacing=edge.id;value.replacementSource=edge.from;value.replacementDestination=edge.to
        value.currentPortOnly=true;value.managingGroupPorts=true;return value
    }
    func testRestoresEveryValidFieldWithoutChangingSource() {
        let value=fixture(),before=value
        XCTAssertEqual(value.restored(ports:ports,targets:[choice],connections:[edge]),value)
        XCTAssertEqual(value,before)
    }
    func testMissingOrFilteredTargetOnlyClearsSelection() {
        var value=fixture();value.replacing=nil;value.replacementSource=nil;value.replacementDestination=nil
        var expected=value;expected.target=nil
        XCTAssertEqual(value.restored(ports:ports,targets:[],connections:[]),expected)
        value.query="없는 검색어";expected.query=value.query
        XCTAssertEqual(value.restored(ports:ports,targets:[choice],connections:[]),expected)
    }
    func testMissingOwnPortCancelsReplacementWithoutAutoSelectingTarget() {
        let value=fixture();let inputs=ports.filter{$0.direction == .input}
        let restored=value.restored(ports:inputs,targets:[choice],connections:[edge])
        XCTAssertEqual(restored.ownPortID,CirclePort.audioInput);XCTAssertEqual(restored.firstOctant,.west);XCTAssertEqual(restored.secondOctant,.east)
        XCTAssertNil(restored.target);XCTAssertNil(restored.replacing);XCTAssertNil(restored.replacementSource);XCTAssertNil(restored.replacementDestination)
        XCTAssertEqual(restored.query,value.query);XCTAssertTrue(restored.currentPortOnly)
        XCTAssertEqual(value.restored(ports:[],targets:[],connections:[]).ownPortID,"")
    }
    func testDeletedReplacementDoesNotBecomeAnArmedNewConnection() {
        let value=fixture();let restored=value.restored(ports:ports,targets:[choice],connections:[])
        XCTAssertNil(restored.target);XCTAssertNil(restored.replacing)
        XCTAssertEqual(restored.ownPortID,value.ownPortID);XCTAssertEqual(restored.query,value.query)
        XCTAssertEqual(restored.firstOctant,value.firstOctant);XCTAssertEqual(restored.secondOctant,value.secondOctant)
    }
    func testRewiredPortWithSameEdgeIDInvalidatesRememberedReplacement() {
        let value=fixture();var changed=edge
        changed.to.portID="in.audio.bus2"
        XCTAssertEqual(changed.id,edge.id)
        let restored=value.restored(ports:ports,targets:[choice],connections:[changed])
        XCTAssertNil(restored.replacing);XCTAssertNil(restored.target)
    }
    func testGainChangeDoesNotDiscardValidIntentButEndpointChangeDoes() {
        let value=fixture();var changed=edge;changed.gain=0.3
        XCTAssertEqual(value.restored(ports:ports,targets:[choice],connections:[changed]),value)
        changed.id=CircleConnectionID(edgeID:edge.id.edgeID,from:source,to:.sound)
        let restored=value.restored(ports:ports,targets:[choice],connections:[changed])
        XCTAssertNil(restored.replacing);XCTAssertNil(restored.target)
    }
}
