import XCTest
import AVFAudio
import CoreMIDI
@testable import CirclrAudio
import CirclrCore

final class AudioTests:XCTestCase {
    func root() throws -> URL {let url=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-test-\(UUID().uuidString)");try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);return url}
    func tone(_ seconds:Double)->PCM {var p=PCM(frames:Int(seconds*PCM.rate));for i in p.left.indices{p.left[i]=Float(sin(Double(i)*2*Double.pi*440/PCM.rate)*0.1);p.right[i]=p.left[i]};return p}
    func testFileDSPAndStretch() throws {
        let dir=try root();defer{try? FileManager.default.removeItem(at:dir)}
        let p=tone(0.4),url=dir.appendingPathComponent("tone.wav");try p.writeWAV(url);let read=try PCM.read(url)
        XCTAssertEqual(read.duration,0.4,accuracy:0.001);XCTAssertEqual(read.rms,p.rms,accuracy:0.0001)
        let region=try PCM.read(url,start:0.1,duration:0.1);XCTAssertEqual(region.count,4800);XCTAssertEqual(region.rms,p.rms,accuracy:0.0001)
        let gain=try NativeDSP.process(p,effect:Effect(.gain,amount:0.5));XCTAssertEqual(gain.rms,p.rms/2,accuracy:0.00001)
        let pan=try NativeDSP.process(p,effect:Effect(.pan,amount:1));XCTAssertEqual(pan.left.max(),0);XCTAssertGreaterThan(pan.right.max() ?? 0,0.1)
        let filter=try NativeDSP.process(p,effect:Effect(.lowpass,amount:0));XCTAssertLessThan(filter.rms,p.rms/4)
        let stretched=try AudioUnitHost.stretch(p,rate:0.5);XCTAssertEqual(stretched.duration,0.8,accuracy:0.001);XCTAssertGreaterThan(stretched.rms,0.001)
    }
    func testTakeWriterPreservesSamples() throws {
        let dir=try root();defer{try? FileManager.default.removeItem(at:dir)}
        let source=tone(0.01),buffer=try source.buffer(),url=dir.appendingPathComponent("take.caf"),writer=try TakeWriter(url:url,format:buffer.format)
        for _ in 0..<20{writer.append(buffer)};try writer.finish()
        XCTAssertEqual(writer.frames,9600);let saved=try PCM.read(url);XCTAssertEqual(saved.count,9600);XCTAssertEqual(saved.rms,source.rms,accuracy:0.0001)
    }
    func testSamplerMIDIAndPattern() async throws {
        let clock=try MusicClock(bars:1,context:MusicContext())
        let p=try await AudioUnitHost.renderNotes([Note(beat:0.5,length:1,pitch:60)],instrument:Instrument(),clock:clock,tail:0.2)
        XCTAssertGreaterThan(p.rms,0.0001);XCTAssertLessThan(p.slice(0..<10000).rms,0.00001);XCTAssertGreaterThan(p.slice(13000..<24000).rms,0.0001)
        var pattern=RhythmPattern(name:"test",trackID:"drums");pattern.length=2;pattern.notes=[Note(beat:0,pitch:36),Note(beat:0.25,pitch:42)]
        let lane=ArrangementRenderer.expandPattern(pattern,length:4,grid:BeatGrid(subdivisions:4,swing:0.5))
        XCTAssertEqual(lane.notes.count,4);XCTAssertEqual(lane.notes[1].beat,0.375,accuracy:0.00001)
    }
    func testTransitionAndSoundNodeChangePCM() async throws {
        var project=Project();let track=project.addTrack(name:"tone");let a=project.addSection(name:"a",at:Point(),bars:1),b=project.addSection(name:"b",at:Point(200,0),bars:1)
        project.sections[0].lanes[0].notes=[Note(beat:0,length:4,pitch:60,velocity:80)]
        project.sections[1].lanes[0].notes=[Note(beat:0,length:4,pitch:60,velocity:80)]
        try ProjectEditing.connect(from:a,to:b,in:&project)
        let first=try await ArrangementRenderer.render(project:project,root:nil,plan:ArrangementCompiler.compile(project),tailSeconds:0)
        project.arrangements[0].edges[0].transition.length=1;project.arrangements[0].edges[0].transition.anchor = .seconds;project.arrangements[0].edges[0].transition.effect=Effect(.gain,amount:0)
        let second=try await ArrangementRenderer.render(project:project,root:nil,plan:ArrangementCompiler.compile(project),tailSeconds:0)
        XCTAssertEqual(first.mix.count,second.mix.count);XCTAssertLessThan(second.mix.slice(60000..<90000).rms,first.mix.slice(60000..<90000).rms*0.01)
        let source=project.signal.nodes.first{$0.trackID==track}!,master=project.signal.nodes.first{$0.kind == .master}!
        var gain=SignalNode(kind:.effect,name:"gain");gain.effect=Effect(.gain,amount:0.25);project.signal.nodes.append(gain);project.signal.edges=[SignalEdge(from:source.id,to:gain.id),SignalEdge(from:gain.id,to:master.id)]
        let processed=try await ArrangementRenderer.render(project:project,root:nil,plan:ArrangementCompiler.compile(project),tailSeconds:0)
        XCTAssertEqual(processed.mix.rms,second.mix.rms/4,accuracy:0.0001)
    }
    func testVirtualMIDIReceivesMultiplePackets() throws {
        let input=try MIDIInput(endpointName:"circlr-test-\(UUID().uuidString)"),done=expectation(description:"three actual MIDI messages");done.expectedFulfillmentCount=3
        let lock=NSLock();var pitches:[UInt8]=[]
        input.onMessage={status,pitch,velocity,_ in if status&0xF0==0x90 && velocity>0 {lock.lock();pitches.append(pitch);lock.unlock();done.fulfill()}}
        var client=MIDIClientRef(),port=MIDIPortRef();XCTAssertEqual(MIDIClientCreate("circlr test" as CFString,nil,nil,&client),noErr);defer{MIDIClientDispose(client)};XCTAssertEqual(MIDIOutputPortCreate(client,"test output" as CFString,&port),noErr)
        let destination=(0..<MIDIGetNumberOfDestinations()).map{MIDIGetDestination($0)}.first{endpoint in var name:Unmanaged<CFString>?;MIDIObjectGetStringProperty(endpoint,kMIDIPropertyName,&name);return (name?.takeRetainedValue() as String?)==input.endpointName}
        XCTAssertNotNil(destination)
        let raw=UnsafeMutableRawPointer.allocate(byteCount:1024,alignment:8);defer{raw.deallocate()};let list=raw.bindMemory(to:MIDIPacketList.self,capacity:1);var packet=MIDIPacketListInit(list)
        for pitch:UInt8 in [60,64,67] {let data:[UInt8]=[0x90,pitch,100];packet=data.withUnsafeBufferPointer{MIDIPacketListAdd(list,1024,packet,0,3,$0.baseAddress!)}}
        XCTAssertEqual(MIDISend(port,destination!,list),noErr);wait(for:[done],timeout:3);XCTAssertEqual(pitches,[60,64,67]);withExtendedLifetime(input){}
    }
    @MainActor func testPlaybackConstructionDoesNotAcquireOutput() {
        let playback = Playback()
        XCTAssertEqual(playback.outputStatus.phase,.idle)
        XCTAssertEqual(playback.outputStatus.transport.phase,.idle)
        XCTAssertFalse(playback.playing)
        playback.stop()
        XCTAssertEqual(playback.seconds,0)
    }
    @MainActor func testArrangementRenderExportAndPlayback() async throws {
        // This integration test uses SoundBank rendering and a physical output
        // worker. Production resolves both beside Bundle.main.executableURL;
        // SwiftPM's xctest host is not the packaged app. Copying helpers into
        // the test bundle does not satisfy that production lookup contract.
        let directory = Bundle.main.executableURL?.deletingLastPathComponent()
        let required = ["circlr-au-instrument-worker", "circlr-output-worker"]
        let missing = required.filter { name in
            guard let directory else { return true }
            return !FileManager.default.isExecutableFile(atPath: directory.appendingPathComponent(name).path)
        }
        guard missing.isEmpty else {
            throw XCTSkip("Packaged native playback integration requires executable helpers beside the main executable (\(directory?.path ?? "unavailable")); missing: \(missing.joined(separator: ", ")). Run packaged native QA separately; this is not a playback pass.")
        }
        let output=try ProcessInfo.processInfo.environment["CIRCLR_QA_OUTPUT"].map{URL(fileURLWithPath:$0)} ?? root()
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        var project=Project();project.name="QA · 송폼 검증";let piano=project.addTrack(name:"QA 피아노"),drums=project.addTrack(name:"QA 드럼",drums:true)
        let a=project.addSection(name:"QA Verse",at:Point(0,0),bars:2),b=project.addSection(name:"QA Bridge",at:Point(265,125),bars:2),c=project.addSection(name:"QA Chorus",at:Point(530,0),bars:2)
        for i in project.sections.indices {for beat in stride(from:0.0,to:8,by:1){project.sections[i].lanes[0].notes.append(Note(beat:beat,length:0.5,pitch:[48,51,55,58][Int(beat)%4],velocity:74))}}
        var pattern=RhythmPattern(name:"QA 리듬",trackID:drums);pattern.notes=[Note(beat:0,length:0.1,pitch:36,velocity:70),Note(beat:1,length:0.1,pitch:38,velocity:60),Note(beat:2,length:0.1,pitch:36,velocity:70),Note(beat:3,length:0.1,pitch:38,velocity:60)];project.patterns=[pattern];project.global.rhythm=RhythmAssignment(pattern.id)
        project.arrangements[0].uses[1].settings.tempo = .local(96);project.arrangements[0].uses[1].settings.meter = .local(Meter(7,8));project.arrangements[0].uses[1].settings.scale = .local(Scale(root:5));project.arrangements[0].uses[2].repeatCount=2
        try ProjectEditing.connect(from:a,to:b,in:&project);try ProjectEditing.connect(from:b,to:c,in:&project)
        project.arrangements[0].edges[0].transition.mode = .overlap;project.arrangements[0].edges[0].transition.anchor = .seconds;project.arrangements[0].edges[0].transition.length=0.5
        project.arrangements[0].layout.groups=[CanvasGroup(name:"QA 첫 파트",members:[a,b])];project.arrangements[0].layout.pan=Point(170,155)
        let source=output.appendingPathComponent("controlled-input.wav");try tone(0.3).writeWAV(source);let asset=Asset(name:"통제된 오디오 입력",path:source.path,duration:0.3,sampleRate:48000);project.assets=[asset];project.sections[2].lanes[0].audio=[AudioClip(assetID:asset.id,duration:0.3,beat:3)]
        let package=output.appendingPathComponent("검증.circlr");project=try ProjectStore.save(project,to:package,mediaRoot:nil)
        let plan=try ArrangementCompiler.compile(project);XCTAssertEqual(plan.duration,15.875,accuracy:0.000001)
        let result=try await ArrangementRenderer.render(project:project,root:package,plan:plan)
        XCTAssertEqual(result.mix.duration,plan.duration+2,accuracy:1/PCM.rate);XCTAssertGreaterThan(result.peak,0.01);XCTAssertLessThan(result.peak,1);XCTAssertEqual(result.stems.count,2)
        for pcm in result.stems.values{XCTAssertEqual(pcm.count,result.mix.count)}
        var sum=PCM(frames:result.mix.count);for pcm in result.stems.values{sum.mix(pcm)};XCTAssertEqual(sum.rms,result.mix.rms,accuracy:0.00001)
        try result.mix.writeWAV(output.appendingPathComponent("render.wav"));for (id,pcm) in result.stems{try pcm.writeWAV(output.appendingPathComponent("stem-\(id==piano ? "piano":"drums").wav"))}
        try AudioExport.save(result,to:output.appendingPathComponent("stereo-export.wav"))
        try AudioExport.save(result,to:output.appendingPathComponent("export-stems"),stemNames:[piano:"piano",drums:"drums"])
        XCTAssertThrowsError(try AudioExport.save(result,to:output,stemNames:[:]))
        let header=try Data(contentsOf:output.appendingPathComponent("stereo-export.wav"));XCTAssertEqual(String(data:header.prefix(4),encoding:.ascii),"RIFF");XCTAssertEqual(String(data:header[8..<12],encoding:.ascii),"WAVE")
        let exported=try PCM.read(output.appendingPathComponent("stereo-export.wav"));XCTAssertEqual(exported.rms,result.mix.rms,accuracy:0.00001)
        let playback=Playback();try await playback.play(result);XCTAssertTrue(playback.playing);try await Task.sleep(nanoseconds:350_000_000);XCTAssertGreaterThan(playback.seconds,0.1);playback.stop();XCTAssertFalse(playback.playing)
        let report="Actual native engine test\nBody: \(plan.duration) s\nWAV: \(result.mix.duration) s\nPeak: \(result.peak)\nRMS: \(result.mix.rms)\nStems: \(result.stems.count)\nPlayback clock advanced: true\n"
        try report.write(to:output.appendingPathComponent("audio-report.txt"),atomically:true,encoding:.utf8)
    }
}
