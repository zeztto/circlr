import XCTest
import CirclrCore
@testable import CirclrAudio

final class MediaLibraryTests:XCTestCase {
    var root:URL!
    override func setUpWithError()throws {root=FileManager.default.temporaryDirectory.appendingPathComponent(newID()).resolvingSymlinksInPath();try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)}
    override func tearDownWithError()throws {try FileManager.default.removeItem(at:root)}
    @discardableResult func write(_ name:String,_ data:Data=Data("data".utf8))throws->URL {
        let url=root.appendingPathComponent(name);try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true);try data.write(to:url);return url
    }
    func scan(_ limit:Int=50_000)throws->LibraryScan {try MediaLibrary.scan(root,folderID:"folder",folderName:"신스 모음",limit:limit)}
    func testRecursiveCatalogSkipsHiddenPackagesLinksAndDirectoriesWithMediaExtensions()throws {
        try write("드럼/Kick.WAV");try write("코드.mid");try write("Readme.txt");try write(".hidden.wav");try write(".cache/hidden.wav")
        try write("project.circlr/inside.wav");try write("Plugin.app/Contents/sample.wav");try write("nested.WAV/real.aiff")
        let outside=try write("outside/escape.wav")
        try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("link.wav"),withDestinationURL:outside)
        try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("linked"),withDestinationURL:outside.deletingLastPathComponent())
        let result=try scan()
        XCTAssertEqual(Set(result.entries.map(\.relativePath)),Set(["드럼/Kick.WAV","코드.mid","outside/escape.wav"]))
        XCTAssertEqual(result.entries.first{$0.name=="코드.mid"}?.kind,.midi)
        XCTAssertEqual(result.entries.first{$0.name=="Kick.WAV"}?.kind,.audio)
        XCTAssertFalse(result.limited)
    }
    func testSearchTermsCaseWidthAccentsFolderAndKindsAreDeterministic()throws {
        try write("Drums/Café KICK.wav");try write("Drums/Snare.wav");try write("Chords.mid")
        let entries=try scan().entries
        XCTAssertEqual(MediaLibrary.search(entries,query:"ＤＲＵＭＳ cafe kick").map(\.name),["Café KICK.wav"])
        XCTAssertEqual(MediaLibrary.search(entries,query:"신스 midi").map(\.name),["Chords.mid"])
        XCTAssertTrue(MediaLibrary.search(entries,query:"",folderID:"missing").isEmpty)
        XCTAssertEqual(MediaLibrary.search(entries,query:"",kind:.audio).count,2)
        XCTAssertEqual(MediaLibrary.search(Array(entries.reversed()),query:""),entries)
    }
    func testDuplicateNamesHaveStableDistinctIDsAndLimitsAreReported()throws {
        try write("A/kick.wav");try write("B/kick.wav");try write("C/kick.wav")
        let entries=try scan().entries
        XCTAssertEqual(Set(entries.map(\.id)).count,3)
        XCTAssertEqual(try scan().entries,entries)
        XCTAssertEqual(try scan(2).entries.count,2);XCTAssertTrue(try scan(2).limited)
        XCTAssertTrue(try MediaLibrary.scan(root,folderID:"f",folderName:"n",visitLimit:1).limited)
    }
    func testChangedDeletedReplacedAndEscapingFilesAreRejected()throws {
        let url=try write("original.wav"),entry=try XCTUnwrap(scan().entries.first)
        XCTAssertEqual(try MediaLibrary.file(entry,under:root),url.standardizedFileURL)
        try Data("longer data".utf8).write(to:url);XCTAssertThrowsError(try MediaLibrary.file(entry,under:root))
        try FileManager.default.removeItem(at:url);XCTAssertThrowsError(try MediaLibrary.file(entry,under:root))
        let outside=try write("other.wav")
        try FileManager.default.createSymbolicLink(at:url,withDestinationURL:outside)
        XCTAssertThrowsError(try MediaLibrary.file(entry,under:root))
        for path in ["../other.wav","/other.wav","a/../../other.wav","a//other.wav"] {
            let bad=LibraryEntry(folderID:entry.folderID,folderName:entry.folderName,relativePath:path,kind:.audio,bytes:entry.bytes,modified:entry.modified)
            XCTAssertThrowsError(try MediaLibrary.file(bad,under:root))
        }
        XCTAssertThrowsError(try MediaLibrary.scan(URL(string:"https://example.com/samples")!,folderID:"f",folderName:"n"))
    }
    func testReplacingParentWithSymlinkCannotEscapeTheRegisteredRoot()throws {
        try write("nested/clip.wav");let entry=try XCTUnwrap(scan().entries.first)
        let sibling=root.deletingLastPathComponent().appendingPathComponent(newID());defer{try? FileManager.default.removeItem(at:sibling)}
        try FileManager.default.moveItem(at:root.appendingPathComponent("nested"),to:sibling)
        try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("nested"),withDestinationURL:sibling)
        XCTAssertThrowsError(try MediaLibrary.file(entry,under:root))
    }
    func testActualMediaMetadataAndAtomicImportPreserveOriginal()throws {
        var pcm=PCM(frames:4800);for i in 0..<pcm.count{pcm.left[i]=0.1;pcm.right[i] = -0.1}
        let audio=root.appendingPathComponent("tone.wav");try pcm.writeWAV(audio)
        try write("notes.mid",MIDIFile.encode(lanes:[("keys",[Note(beat:0,length:1,pitch:60),Note(beat:1,length:1,pitch:64)])],tempo:120,meter:Meter()))
        let entries=try scan().entries,a=try XCTUnwrap(entries.first{$0.kind == .audio}),m=try XCTUnwrap(entries.first{$0.kind == .midi})
        let info=try MediaLibrary.inspect(a,under:root)
        XCTAssertEqual(try XCTUnwrap(info.duration),0.1,accuracy:0.0001);XCTAssertEqual(info.channels,2);XCTAssertEqual(info.sampleRate,48000)
        XCTAssertEqual(try MediaLibrary.inspect(m,under:root).notes,2)
        let original=try Data(contentsOf:audio),staged=try AudioFileImport.stage([MediaLibrary.file(a,under:root)],under:root.appendingPathComponent("imports"))
        XCTAssertEqual(try Data(contentsOf:audio),original);XCTAssertEqual(staged.assets[0].checksum,try ProjectStore.checksum(audio))
        staged.discard();XCTAssertEqual(try Data(contentsOf:audio),original)
    }
    func testBadMediaIsListedButCannotPassDecoderValidation()throws {
        try write("broken.wav");try write("broken.mid")
        let entries=try scan().entries;XCTAssertEqual(entries.count,2)
        for entry in entries{XCTAssertNoThrow(try MediaLibrary.file(entry,under:root));XCTAssertThrowsError(try MediaLibrary.inspect(entry,under:root))}
    }
    func testCancelledScanDoesNotReturnStaleResults()async throws {
        try write("clip.wav");let root=root!
        let task=Task.detached {withUnsafeCurrentTask{$0?.cancel()};return try MediaLibrary.scan(root,folderID:"f",folderName:"n")}
        do {_=try await task.value;XCTFail("Cancelled scan succeeded")} catch {XCTAssertTrue(error is CancellationError)}
    }
}
