import Foundation
import XCTest
@testable import CirclrApp
@testable import CirclrAudio

final class MediaLibraryResultLookupTests:XCTestCase {
    private func entry(_ index:Int,kind:LibraryMediaKind = .audio)->LibraryEntry {
        LibraryEntry(folderID:"folder",folderName:"Folder",relativePath:"\(index).wav",
                     kind:kind,bytes:100,modified:Date(timeIntervalSince1970:0))
    }

    func testFiftyThousandResultsKeepChosenDisplayOrderAndBoundedValidation()throws {
        let results=(0..<50_000).map{entry($0)}
        let lookup=MediaLibraryResultLookup(results)
        let selected:Set<String>=[results[49_999].id,results[10].id,results[30_000].id]
        XCTAssertEqual(lookup.chosen(selected).map(\.id),[results[10].id,results[30_000].id,results[49_999].id])
        XCTAssertEqual(lookup.chosen(selected).map(\.id),try MediaLibrarySelection.entries(results,ids:selected).map(\.id))
        XCTAssertEqual(lookup.offset(for:results[49_999].id),49_999)
        XCTAssertEqual(lookup.entry(for:results[49_999].id)?.id,results[49_999].id)
        for _ in 0..<100 {try lookup.validate(selected)}
    }

    func testMissingOrInvalidSelectionKeepsOriginalErrors()throws {
        let audio=entry(0),midi=entry(1,kind:.midi)
        let lookup=MediaLibraryResultLookup([audio,midi])
        let missing:Set<String>=["missing"]
        XCTAssertEqual(lookup.chosen(missing),[])
        XCTAssertThrowsError(try lookup.validate(missing)) {error in
            XCTAssertEqual(error.localizedDescription,"검색 결과가 변경됐습니다. 파일을 다시 선택하세요")
        }
        XCTAssertThrowsError(try lookup.validate([audio.id,midi.id])) {error in
            XCTAssertEqual(error.localizedDescription,"MIDI는 한 파일씩 가져옵니다. 오디오와 따로 선택하세요")
        }
        XCTAssertThrowsError(try lookup.validate([])) {error in
            XCTAssertEqual(error.localizedDescription,"한 번에 1–64개 파일을 선택하세요")
        }
    }
}
