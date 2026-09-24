import Foundation
import XCTest
@testable import CirclrAudio
import CirclrCore

private actor StemStopCompletion {
    private var finished=false
    func mark() {finished=true}
    func value() -> Bool {finished}
}

final class SequentialStemExportTests:XCTestCase {
    private func fixture() throws -> (Project,ID,ID) {
        var project=Project()
        let lead=project.addTrack(name:"리드"),duck=project.addTrack(name:"검출")
        _=project.addSection(name:"검증",at:Point(),bars:1)
        project.sections[0].lanes[0].notes=[Note(beat:0,length:3,pitch:60,velocity:80)]
        project.sections[0].lanes[1].notes=[Note(beat:0,length:3,pitch:48,velocity:110)]
        let leadSource=try XCTUnwrap(project.signal.nodes.first{$0.trackID==lead})
        let duckSource=try XCTUnwrap(project.signal.nodes.first{$0.trackID==duck})
        let master=try XCTUnwrap(project.signal.nodes.first{$0.kind == .master})
        var compressor=SignalNode(kind:.effect,name:"sidechain compressor")
        compressor.effect=Effect(.compressor,amount:0,secondary:0.9)
        var sidechain=SignalEdge(from:duckSource.id,to:compressor.id)
        sidechain.sidechain=true
        project.signal.nodes.append(compressor)
        project.signal.edges=[SignalEdge(from:leadSource.id,to:compressor.id),sidechain,
                              SignalEdge(from:compressor.id,to:master.id)]
        return (project,lead,duck)
    }
    private func directory() throws -> URL {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-stem-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        return url
    }
    private func seedOldExport(_ url:URL,plan:ExecutionPlan,legacy:Bool = false) throws {
        let fm=FileManager.default
        try fm.createDirectory(at:url,withIntermediateDirectories:false)
        var manifest:[String:Any]=["format":"circlr-stems-v1","musicRevision":plan.revision,
            "arrangementID":plan.arrangementID,"bodySeconds":plan.duration,"tailSeconds":2.0,
            "sampleRate":PCM.rate,"bitDepth":24]
        if !legacy {manifest["stemFiles"]=["기존-ABCDEF.wav"]}
        try JSONSerialization.data(withJSONObject:manifest).write(to:url.appendingPathComponent("circlr-export.json"))
        try Data("old".utf8).write(to:url.appendingPathComponent("내보내기 정보.txt"))
        try PCM(frames:480).writeWAV(url.appendingPathComponent("전체 mix.wav"))
        try PCM(frames:480).writeWAV(url.appendingPathComponent("기존-ABCDEF.wav"))
    }
    private func snapshot(_ url:URL) throws -> [String:Data] {
        try Dictionary(uniqueKeysWithValues:FileManager.default.contentsOfDirectory(atPath:url.path)
            .sorted().map { name in (name,try Data(contentsOf:url.appendingPathComponent(name))) })
    }
    func testSequentialStemsMatchOriginalSidechainAndManifest() async throws {
        let root=try directory();defer{try? FileManager.default.removeItem(at:root)}
        let (project,lead,duck)=try fixture(),plan=try ArrangementCompiler.compile(project)
        let reference=try await ArrangementRenderer.render(project:project,root:nil,plan:plan,tailSeconds:nil,includeStems:true)
        let legacy=root.appendingPathComponent("legacy")
        try AudioExport.save(reference,to:legacy,stemNames:[lead:"리드",duck:"검출"])
        let output=root.appendingPathComponent("stems")
        try await AudioExport.saveStems(project:project,root:nil,plan:plan,to:output,
                                        stemNames:[lead:"리드",duck:"검출"])
        let leadWAV=try PCM.read(output.appendingPathComponent("리드-\(lead.prefix(6)).wav"))
        let duckWAV=try PCM.read(output.appendingPathComponent("검출-\(duck.prefix(6)).wav"))
        let mixWAV=try PCM.read(output.appendingPathComponent("전체 mix.wav"))
        XCTAssertEqual(leadWAV.rms,reference.stems[lead]!.rms,accuracy:0.000001)
        XCTAssertEqual(duckWAV.rms,reference.stems[duck]!.rms,accuracy:0.000001)
        XCTAssertEqual(mixWAV.rms,reference.mix.rms,accuracy:0.000001)
        for filename in ["리드-\(lead.prefix(6)).wav","검출-\(duck.prefix(6)).wav","전체 mix.wav"] {
            XCTAssertEqual(try Data(contentsOf:output.appendingPathComponent(filename)),
                           try Data(contentsOf:legacy.appendingPathComponent(filename)))
        }
        XCTAssertGreaterThan(leadWAV.rms,0.001)
        XCTAssertEqual(duckWAV.peak,0)
        let manifest=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:output.appendingPathComponent("circlr-export.json"))) as? [String:Any])
        XCTAssertEqual(manifest["format"] as? String,"circlr-stems-v1")
        XCTAssertEqual(manifest["musicRevision"] as? Int,project.musicRevision)
        XCTAssertEqual(manifest["arrangementID"] as? String,plan.arrangementID)
        XCTAssertEqual(manifest["bodySeconds"] as? Double,plan.duration)
        XCTAssertEqual(manifest["tailSeconds"] as? Double,reference.tailSeconds)
        XCTAssertEqual(manifest["sampleRate"] as? Double,PCM.rate)
        XCTAssertEqual(manifest["bitDepth"] as? Int,24)
        XCTAssertEqual(Set(manifest["stemFiles"] as? [String] ?? []),
                       Set(["리드-\(lead.prefix(6)).wav","검출-\(duck.prefix(6)).wav"]))
    }
    func testTwoCompositionAlbumWAVAndStemsContainLaterSong() async throws {
        let root=try directory();defer{try? FileManager.default.removeItem(at:root)}
        var project=Project()
        let track=project.addTrack(name:"둘째 곡 악기")
        _=project.addSection(name:"첫째 곡",at:Point(),bars:1)
        let firstArrangement=project.activeArrangementID
        project.enableAlbum()
        let second=try AlbumEditing.add(name:"둘째 곡",kind:.song,in:&project)
        project.activeArrangementID=try XCTUnwrap(project.album?.composition(second)?.selectedArrangementID)
        _=project.addSection(name:"둘째 곡 구간",at:Point(),bars:1)
        project.sections[1].lanes[0].notes=[Note(beat:0,length:4,pitch:72,velocity:95)]
        project.activeArrangementID=firstArrangement
        let album=try AlbumCompiler.compile(project),plan=try AlbumCompiler.executionPlan(project)
        let activeOnly=try ArrangementCompiler.compile(project)
        XCTAssertEqual(album.compositions.count,2)
        XCTAssertGreaterThan(plan.duration,activeOnly.duration)
        let prepared=try await ArrangementRenderer.render(project:project,root:nil,plan:plan,includeStems:false)
        let wav=root.appendingPathComponent("album.wav"),stems=root.appendingPathComponent("stems")
        try AudioExport.save(prepared,to:wav)
        try await AudioExport.saveStems(project:project,root:nil,plan:plan,to:stems,stemNames:[track:"둘째 곡 악기"])
        let stemName=try XCTUnwrap(AudioExport.stemFilenames(tracks:project.tracks,names:[track:"둘째 곡 악기"])[track])
        let albumWAV=try PCM.read(wav),mixWAV=try PCM.read(stems.appendingPathComponent("전체 mix.wav"))
        let stemWAV=try PCM.read(stems.appendingPathComponent(stemName))
        let expectedFrames=try RenderTailPlanner.frameCount(bodySeconds:plan.duration,tailSeconds:prepared.tailSeconds)
        XCTAssertEqual(albumWAV.count,expectedFrames)
        XCTAssertEqual(mixWAV.count,expectedFrames)
        XCTAssertEqual(stemWAV.count,expectedFrames)
        let laterStart=Int((album.compositions[1].start+0.5)*PCM.rate)
        let laterEnd=min(expectedFrames,laterStart+Int(0.5*PCM.rate))
        XCTAssertGreaterThan(albumWAV.slice(laterStart..<laterEnd).rms,0.001)
        XCTAssertGreaterThan(mixWAV.slice(laterStart..<laterEnd).rms,0.001)
        XCTAssertGreaterThan(stemWAV.slice(laterStart..<laterEnd).rms,0.001)
        XCTAssertEqual(albumWAV.left,mixWAV.left)
        XCTAssertEqual(albumWAV.right,mixWAV.right)
    }
    func testCancellationKeepsExistingExportAndRemovesStage() async throws {
        let root=try directory();defer{try? FileManager.default.removeItem(at:root)}
        let (project,lead,duck)=try fixture(),plan=try ArrangementCompiler.compile(project)
        let output=root.appendingPathComponent("stems")
        try seedOldExport(output,plan:plan)
        let prior=try Data(contentsOf:output.appendingPathComponent("기존-ABCDEF.wav"))
        do {
            try await AudioExport.saveStems(project:project,root:nil,plan:plan,to:output,
                                            stemNames:[lead:"리드",duck:"검출"]) { message,_ in
                if message.contains("stem 준비") { withUnsafeCurrentTask{$0?.cancel()} }
            }
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
        XCTAssertEqual(try Data(contentsOf:output.appendingPathComponent("기존-ABCDEF.wav")),prior)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path).sorted(),["stems"])
    }
    func testStopAtPrePublishBoundaryPreservesEveryPreviousStemByte() async throws {
        let root=try directory();defer{try? FileManager.default.removeItem(at:root)}
        let (project,lead,duck)=try fixture(),plan=try ArrangementCompiler.compile(project)
        let output=root.appendingPathComponent("stems")
        try seedOldExport(output,plan:plan)
        let original=try snapshot(output),gate=WAVExportCommitGate()
        let release=DispatchSemaphore(value:0)
        let staged=expectation(description:"all stems staged before publication")
        let worker=Task.detached { () throws -> Void in
            try await AudioExport.saveStems(project:project,root:nil,plan:plan,to:output,
                stemNames:[lead:"리드",duck:"검출"],commitGate:gate,
                beforePublish:{staged.fulfill();release.wait()},afterCommitStarted:{})
        }
        await fulfillment(of:[staged],timeout:10)
        XCTAssertEqual(try snapshot(output),original)
        gate.cancel()
        release.signal()
        do {try await worker.value;XCTFail("STOP published stems")}
        catch is CancellationError {}
        XCTAssertEqual(try snapshot(output),original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path).sorted(),["stems"])
    }
    func testStopWaitsWhenStemPublicationAlreadyEnteredGate() async throws {
        let root=try directory();defer{try? FileManager.default.removeItem(at:root)}
        let (project,lead,duck)=try fixture(),plan=try ArrangementCompiler.compile(project)
        let output=root.appendingPathComponent("stems")
        try seedOldExport(output,plan:plan)
        let original=try snapshot(output),gate=WAVExportCommitGate()
        let release=DispatchSemaphore(value:0)
        let publishing=expectation(description:"stem publication entered gate")
        let worker=Task.detached { () throws -> Void in
            try await AudioExport.saveStems(project:project,root:nil,plan:plan,to:output,
                stemNames:[lead:"리드",duck:"검출"],commitGate:gate,
                beforePublish:{},afterCommitStarted:{publishing.fulfill();release.wait()})
        }
        await fulfillment(of:[publishing],timeout:10)
        XCTAssertEqual(try snapshot(output),original)
        let completion=StemStopCompletion()
        let stopping=expectation(description:"STOP attempted")
        let stopper=Task.detached {stopping.fulfill();gate.cancel();await completion.mark()}
        await fulfillment(of:[stopping],timeout:2)
        try await Task.sleep(for:.milliseconds(30))
        let returnedBeforePublish=await completion.value()
        XCTAssertFalse(returnedBeforePublish)
        release.signal()
        try await worker.value
        await stopper.value
        let returnedAfterPublish=await completion.value()
        XCTAssertTrue(returnedAfterPublish)
        XCTAssertNotEqual(try snapshot(output),original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path).sorted(),["stems"])
    }
    func testExistingExportIsAtomicallyReplaced() async throws {
        let root=try directory();defer{try? FileManager.default.removeItem(at:root)}
        let (project,lead,duck)=try fixture(),plan=try ArrangementCompiler.compile(project)
        let output=root.appendingPathComponent("stems")
        try seedOldExport(output,plan:plan)
        try await AudioExport.saveStems(project:project,root:nil,plan:plan,to:output,
                                        stemNames:[lead:"리드",duck:"검출"])
        XCTAssertFalse(FileManager.default.fileExists(atPath:output.appendingPathComponent("기존-ABCDEF.wav").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath:output.appendingPathComponent("전체 mix.wav").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path).sorted(),["stems"])
    }
    func testLegacyExportWithoutStemInventoryIsPreserved() async throws {
        let root=try directory();defer{try? FileManager.default.removeItem(at:root)}
        let (project,lead,duck)=try fixture(),plan=try ArrangementCompiler.compile(project)
        let output=root.appendingPathComponent("stems")
        try seedOldExport(output,plan:plan,legacy:true)
        let personal=output.appendingPathComponent("personal-ABCDEF.wav")
        try PCM(frames:480).writeWAV(personal)
        let original=try Data(contentsOf:personal)
        do {
            try await AudioExport.saveStems(project:project,root:nil,plan:plan,to:output,
                                            stemNames:[lead:"리드",duck:"검출"])
            XCTFail("Expected legacy export rejection")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("파일 목록"))
        }
        XCTAssertEqual(try Data(contentsOf:personal),original)
        XCTAssertTrue(FileManager.default.fileExists(atPath:output.appendingPathComponent("기존-ABCDEF.wav").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path).sorted(),["stems"])
    }
    func testLaterStemFailurePreservesExistingExport() async throws {
        let root=try directory();defer{try? FileManager.default.removeItem(at:root)}
        var (project,lead,duck)=try fixture()
        project.tracks[1].gain=100
        let duckSource=try XCTUnwrap(project.signal.nodes.first{$0.trackID==duck})
        let master=try XCTUnwrap(project.signal.nodes.first{$0.kind == .master})
        project.signal.edges.append(SignalEdge(from:duckSource.id,to:master.id))
        let plan=try ArrangementCompiler.compile(project),output=root.appendingPathComponent("stems")
        try seedOldExport(output,plan:plan)
        let prior=try Data(contentsOf:output.appendingPathComponent("기존-ABCDEF.wav"))
        do {
            try await AudioExport.saveStems(project:project,root:nil,plan:plan,to:output,
                                            stemNames:[lead:"리드",duck:"검출"])
            XCTFail("Expected clipping rejection")
        } catch {}
        XCTAssertEqual(try Data(contentsOf:output.appendingPathComponent("기존-ABCDEF.wav")),prior)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path).sorted(),["stems"])
    }
    func testUnsafeTargetAndExtraFilesArePreserved() async throws {
        let root=try directory();defer{try? FileManager.default.removeItem(at:root)}
        let (project,lead,duck)=try fixture(),plan=try ArrangementCompiler.compile(project)
        let output=root.appendingPathComponent("stems")
        try seedOldExport(output,plan:plan)
        try Data("private".utf8).write(to:output.appendingPathComponent("personal.wav"))
        do {
            try await AudioExport.saveStems(project:project,root:nil,plan:plan,to:output,
                                            stemNames:[lead:"리드",duck:"검출"])
            XCTFail("Expected extra file rejection")
        } catch {}
        XCTAssertEqual(try Data(contentsOf:output.appendingPathComponent("personal.wav")),Data("private".utf8))
        let link=root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:output)
        do {
            try await AudioExport.saveStems(project:project,root:nil,plan:plan,to:link,
                                            stemNames:[lead:"리드",duck:"검출"])
            XCTFail("Expected symlink rejection")
        } catch {}
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath:link.path),output.path)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path).sorted(),["link","stems"])
    }
    func testFilenameCollisionAndPathSeparators() throws {
        var first=Track(name:"같은 이름"),second=Track(name:"같은 이름")
        first.id="abc/def1";second.id="abc/def2"
        let filenames=try AudioExport.stemFilenames(tracks:[first,second],names:[first.id:first.name,second.id:second.name])
        XCTAssertEqual(Set(filenames.values).count,2)
        XCTAssertTrue(filenames.values.allSatisfy{!$0.contains("/") && $0.hasSuffix(".wav")})
        XCTAssertEqual(filenames[first.id],"같은 이름-abc-de.wav")
        first.id="ABCDEF1";first.name="Lead"
        second.id="abcdef2";second.name="lead"
        let caseVariants=try AudioExport.stemFilenames(tracks:[first,second],names:[first.id:first.name,second.id:second.name])
        XCTAssertEqual(caseVariants[first.id],"Lead-ABCDEF.wav")
        XCTAssertEqual(caseVariants[second.id],"lead-abcdef-2-1.wav")
        XCTAssertEqual(Set(caseVariants.values.map{$0.lowercased()}).count,2)
    }
    func testBuild211FixtureExportsAllStemsWhenRequested() async throws {
        guard let source=ProcessInfo.processInfo.environment["CIRCLR_QA_STEM_PROJECT"],
              let destination=ProcessInfo.processInfo.environment["CIRCLR_QA_STEM_OUTPUT"] else {
            throw XCTSkip("Set CIRCLR_QA_STEM_PROJECT and CIRCLR_QA_STEM_OUTPUT for native 16-track reproduction")
        }
        let loaded=try ProjectStore.load(URL(fileURLWithPath:source))
        let project=loaded.project,plan=try ArrangementCompiler.compile(project)
        XCTAssertEqual(project.tracks.count,16)
        let graphPeak=plan.occurrences.compactMap{$0.signalPlan.map{SectionGraphRenderer.workingBufferCount($0)}}.max() ?? 0
        print("NATIVE_PREFLIGHT BODY=\(plan.duration) TRACKS=\(project.tracks.count) PROCESSORS=\(project.signal.nodes.filter{$0.kind != .source}.count) GRAPH=\(graphPeak) LIMIT=\(ArrangementRenderer.preparationByteLimit)")
        let output=URL(fileURLWithPath:destination)
        try await AudioExport.saveStems(project:project,root:loaded.root,plan:plan,to:output,
                                        stemNames:Dictionary(uniqueKeysWithValues:project.tracks.map{($0.id,$0.name)}))
        let files=try FileManager.default.contentsOfDirectory(atPath:output.path)
        XCTAssertEqual(files.filter{$0.hasSuffix(".wav")}.count,17)
        XCTAssertTrue(files.contains("circlr-export.json"))
        print("NATIVE_STEMS_OUTPUT=\(output.path) TRACKS=\(project.tracks.count) WAVS=\(files.filter{$0.hasSuffix(".wav")}.count) BODY=\(plan.duration)")
    }
}
