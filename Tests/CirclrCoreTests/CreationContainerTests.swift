import XCTest
@testable import CirclrCore

final class CreationContainerTests:XCTestCase {
    func testMusicAndNestedGroupsResolveToTheirSection() {
        let section=CircleAddress.section(arrangementID:"a",useID:"u")
        let music=CircleAddress.music(arrangementID:"a",useID:"u",nodeID:"n")
        XCTAssertEqual(music.creationContainer,section)
        XCTAssertEqual(CircleAddress.group(parent:.group(parent:music,id:"inner"),id:"outer").creationContainer,section)
    }
    func testSoundAndStructuralContainersKeepTheirMeaning() {
        XCTAssertEqual(CircleAddress.signal("bus").creationContainer,.sound)
        for address in [CircleAddress.album,.sound,.composition("song"),.section(arrangementID:"a",useID:"u")] {
            XCTAssertEqual(address.creationContainer,address)
            XCTAssertEqual(CircleAddress.group(parent:address,id:"group").creationContainer,address)
        }
    }
}
