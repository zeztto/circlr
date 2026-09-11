import XCTest
import AVFAudio
import CirclrCore
@testable import CirclrAudio

final class AudioFileImportTests:XCTestCase {
    func fixture(_ root:URL)throws->URL {
        var pcm=PCM(frames:4800);for i in 0..<pcm.count {pcm.left[i]=Float(i%31)/512;pcm.right[i] = -Float(i%23)/512}
        let url=root.appendingPathComponent("원본.wav");try pcm.writeWAV(url);return url
    }
    func testCopyHashPortableSaveAndRenderAfterRemovingOriginal()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(newID());defer{try? FileManager.default.removeItem(at:root)}
        let url=try fixture(root),original=try Data(contentsOf:url)
        let staged=try AudioFileImport.stage([url],under:root.appendingPathComponent("imports"))
        XCTAssertEqual(try Data(contentsOf:url),original)
        XCTAssertEqual(staged.assets[0].checksum,try ProjectStore.checksum(url))
        XCTAssertEqual(try Data(contentsOf:URL(fileURLWithPath:staged.assets[0].path)),original)
        var p=Project();let track=p.addTrack(name:"샘플");p.tracks[0].gain=1;let use=p.addSection(name:"루프",at:Point(),bars:1)
        p=try SectionGraphMigration.migrate(p)
        _=try AudioImportEditing.apply(staged.assets,to:.section(arrangementID:p.active.id,useID:use,trackID:track,beat:0,position:nil,original:false),projectID:p.id,revision:p.musicRevision,in:&p)
        let before=try await ArrangementRenderer.render(project:p,root:nil,plan:ArrangementCompiler.compile(p),tailSeconds:0)
        XCTAssertGreaterThan(before.mix.peak,0.01)
        let package=root.appendingPathComponent("portable.circlr");_=try ProjectStore.save(p,to:package,mediaRoot:nil)
        try FileManager.default.removeItem(at:url);staged.discard()
        let loaded=try ProjectStore.load(package)
        let after=try await ArrangementRenderer.render(project:loaded.project,root:loaded.root,plan:ArrangementCompiler.compile(loaded.project),tailSeconds:0)
        XCTAssertEqual(after.mix.left,before.mix.left);XCTAssertEqual(after.mix.right,before.mix.right)
    }
    func testInvalidSecondFileCleansOnlyOwnedDirectoryAndRejectsUnsupportedInput()throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(newID());defer{try? FileManager.default.removeItem(at:root)}
        let url=try fixture(root),bad=root.appendingPathComponent("broken.wav"),imports=root.appendingPathComponent("imports")
        try Data("invalid wav".utf8).write(to:bad);try FileManager.default.createDirectory(at:imports,withIntermediateDirectories:true)
        let keep=imports.appendingPathComponent("keep.txt");try Data("preserve".utf8).write(to:keep)
        XCTAssertThrowsError(try AudioFileImport.stage([url,bad],under:imports))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:imports.path),["keep.txt"])
        XCTAssertEqual(try String(contentsOf:keep),"preserve")
        XCTAssertThrowsError(try AudioFileImport.stage([keep],under:imports))
        let directory=root.appendingPathComponent("folder.wav");try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        XCTAssertThrowsError(try AudioFileImport.stage([directory],under:imports))
        XCTAssertThrowsError(try AudioFileImport.stage(Array(repeating:url,count:65),under:imports))
    }
    func testSaveUndoSaveRedoKeepsImportedMediaAlive()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(newID());defer{try? FileManager.default.removeItem(at:root)}
        let input=try fixture(root),staged=try AudioFileImport.stage([input],under:root.appendingPathComponent("imports"))
        var p=Project();let track=p.addTrack(name:"오디오");let use=p.addSection(name:"구간",at:Point(),bars:1)
        p=try SectionGraphMigration.migrate(p);let before=p,package=root.appendingPathComponent("undo.circlr")
        _=try AudioImportEditing.apply(staged.assets,to:.section(arrangementID:p.active.id,useID:use,trackID:track,beat:0,position:nil,original:false),projectID:p.id,revision:p.musicRevision,in:&p)
        p=try ProjectStore.saveSession(p,to:package,mediaRoot:nil)
        let redo=p,embedded=try ProjectStore.load(package).project.assets[0].path
        XCTAssertFalse(embedded.hasPrefix("/"));XCTAssertEqual(p.assets[0].path,staged.assets[0].path)
        p=try CircleHistory.restore(before,layoutOnly:false,current:p)
        p=try ProjectStore.saveSession(p,to:package,mediaRoot:package)
        XCTAssertFalse(FileManager.default.fileExists(atPath:package.appendingPathComponent(embedded).path))
        p=try CircleHistory.restore(redo,layoutOnly:false,current:p)
        try FileManager.default.removeItem(at:input)
        let rendered=try await ArrangementRenderer.render(project:p,root:package,plan:ArrangementCompiler.compile(p),tailSeconds:0)
        XCTAssertGreaterThan(rendered.mix.peak,0.01)
        _=try ProjectStore.saveSession(p,to:package,mediaRoot:package)
        let loaded=try ProjectStore.load(package)
        XCTAssertEqual(loaded.project.assets[0].checksum,staged.assets[0].checksum)
    }
    func testCancellationDuringCopyLeavesNoStagingOrChangedSource()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(newID());defer{try? FileManager.default.removeItem(at:root)}
        let url=try fixture(root),before=try Data(contentsOf:url),imports=root.appendingPathComponent("imports")
        let worker=Task.detached {try AudioFileImport.stage([url],under:imports){_ in withUnsafeCurrentTask{$0?.cancel()}}}
        do {_=try await worker.value;XCTFail("Cancelled import succeeded")}catch{XCTAssertTrue(error is CancellationError)}
        XCTAssertEqual(try Data(contentsOf:url),before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:imports.path),[])
    }
    func testMultichannelMediaRejectedBeforeDocumentMutation()throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(newID());defer{try? FileManager.default.removeItem(at:root)}
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let url=root.appendingPathComponent("surround.wav")
        func le(_ value:Int,_ bytes:Int)->[UInt8] {(0..<bytes).map{UInt8((value >> ($0*8)) & 255)}}
        let body=[UInt8](repeating:0,count:128*6*2)
        let header=Array("RIFF".utf8)+le(36+body.count,4)+Array("WAVEfmt ".utf8)+le(16,4)+le(1,2)+le(6,2)+le(48000,4)+le(48000*12,4)+le(12,2)+le(16,2)+Array("data".utf8)+le(body.count,4)
        try Data(header+body).write(to:url)
        XCTAssertEqual(try AVAudioFile(forReading:url).processingFormat.channelCount,6)
        XCTAssertThrowsError(try AudioFileImport.stage([url],under:root.appendingPathComponent("imports")))
    }
}
