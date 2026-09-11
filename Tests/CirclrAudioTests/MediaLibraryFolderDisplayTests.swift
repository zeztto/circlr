import XCTest
@testable import CirclrAudio

final class MediaLibraryFolderDisplayTests:XCTestCase {
    func folder(_ id:String,_ path:String?,name:String="samples")->LibraryFolderLocation {LibraryFolderLocation(id:id,name:name,path:path)}
    func testDistinctNamesStayShortAndEmptyInputWorks() {
        XCTAssertEqual(MediaLibraryFolderDisplay.labels([]),[:])
        XCTAssertEqual(MediaLibraryFolderDisplay.labels([folder("a","/Music/drums",name:"drums"),folder("b",nil,name:"keys")]),["a":"drums","b":"keys"])
    }
    func testDuplicateNamesUseShortestDistinctParents() {
        let labels=MediaLibraryFolderDisplay.labels([folder("a","/Music/Nordic/samples"),folder("b","/Music/Citypop/samples")])
        XCTAssertEqual(labels,["a":"Nordic/samples","b":"Citypop/samples"])
    }
    func testSharedParentsExpandOnlyAsFarAsNeeded() {
        let labels=MediaLibraryFolderDisplay.labels([folder("a","/Volume/A/Album/samples"),folder("b","/Volume/B/Album/samples"),folder("c","/Volume/Other/samples")])
        XCTAssertEqual(labels,["a":"A/Album/samples","b":"B/Album/samples","c":"Other/samples"])
    }
    func testUnavailableAndIdenticalPathsHaveDistinctRegistrationFallback() {
        let labels=MediaLibraryFolderDisplay.labels([folder("a",nil),folder("b",nil),folder("c","/A/samples"),folder("d","/A/samples")])
        XCTAssertEqual(labels,["a":"samples · 등록 1","b":"samples · 등록 2","c":"samples · 등록 3","d":"samples · 등록 4"])
    }
    func testCanonicalUnicodeAndCaseCollisionsAreDisambiguated() {
        let labels=MediaLibraryFolderDisplay.labels([folder("a","/Music/A/샘플",name:"샘플"),folder("b","/Music/B/샘플",name:"샘플"),folder("c","/Music/A/Samples",name:"Samples"),folder("d","/Music/B/samples")])
        XCTAssertEqual(labels["a"],"A/샘플");XCTAssertEqual(labels["b"],"B/샘플")
        XCTAssertEqual(labels["c"],"A/Samples");XCTAssertEqual(labels["d"],"B/samples")
    }
}
