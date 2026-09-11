import XCTest
@testable import CirclrAudio

final class OutputDeviceCatalogTests:XCTestCase {
    func testValidCatalogRoundTripAndMissingDefault()throws {
        let value=OutputDeviceCatalog(devices:[.init(uid:"a",name:"스피커")],defaultUID:"a")
        XCTAssertEqual(try OutputDeviceCatalog.decode(JSONEncoder().encode(value)),value)
        XCTAssertNoThrow(try OutputDeviceCatalog(devices:[]).validate())
    }
    func testRejectsDuplicateInvalidUIDAndForeignDefault()throws {
        for uid in ["",String(repeating:"한",count:342),"a\nb","a\0b"] {
            XCTAssertThrowsError(try OutputDeviceCatalog(devices:[.init(uid:uid,name:"장치")]).validate())
        }
        XCTAssertThrowsError(try OutputDeviceCatalog(devices:[.init(uid:"a",name:"A"),.init(uid:"a",name:"B")]).validate())
        XCTAssertThrowsError(try OutputDeviceCatalog(devices:[],defaultUID:"missing").validate())
        var version=OutputDeviceCatalog(devices:[]);version.version=2;XCTAssertThrowsError(try version.validate())
        XCTAssertThrowsError(try OutputDeviceCatalog.decode(Data(repeating:32,count:65_537)))
    }
}
