import XCTest
import AudioToolbox
import Darwin
import CirclrCore
@testable import CirclrAudio

final class AUInstrumentWorkerProtocolTests:XCTestCase {
    private func request(notes:[Note]=[],tail:Double=0,instrument:Instrument=Instrument())throws->AUInstrumentWorkerRequest {
        .init(session:UUID(),notes:notes,instrument:instrument,clock:try MusicClock(bars:1,context:MusicContext()),tail:tail,hostContext:nil)
    }
    func testExactClockAndRequestRoundTrip() throws {
        var context=MusicContext();context.tempo=137
        let parent=try MusicClock(bars:4,context:context,meterChanges:[MeterChange(bar:1,meter:Meter(7,8))],tempoChanges:[TempoChange(beat:2,bpm:93)])
        let clock=try MusicClock(parent:parent,start:0.625,length:6.125,context:context,inheritTempo:true,inheritMeter:true)
        let request=AUInstrumentWorkerRequest(session:UUID(),notes:[Note(beat:0,length:1,pitch:60,velocity:90)],instrument:Instrument(),clock:clock,tail:0.25,hostContext:context)
        let decoded=try JSONDecoder().decode(AUInstrumentWorkerRequest.self,from:JSONEncoder().encode(request))
        let result=try AUInstrumentWorkerFiles.validate(decoded)
        XCTAssertEqual(result.clock,clock);XCTAssertEqual(result.frames,Int(ceil((clock.seconds+0.25)*PCM.rate)))
        XCTAssertEqual(decoded.notes,request.notes);XCTAssertEqual(decoded.hostContext,context)
    }
    func testNumericAndInstrumentRejections() throws {
        for tail in [-1.0,Double.nan,Double.infinity,120.01] {XCTAssertThrowsError(try AUInstrumentWorkerFiles.validate(request(tail:tail)))}
        for note in [Note(beat:.nan,length:1,pitch:60,velocity:90),Note(beat:0,length:.infinity,pitch:60,velocity:90),Note(beat:0,length:0,pitch:60,velocity:90),Note(beat:0,length:1,pitch:128,velocity:90)] {
            XCTAssertThrowsError(try AUInstrumentWorkerFiles.validate(request(notes:[note])))
        }
        var instrument=Instrument();instrument.kind = .synthesizer
        XCTAssertThrowsError(try AUInstrumentWorkerFiles.validate(request(instrument:instrument)))
        instrument.kind = .audioUnit;instrument.plugin = PluginDescriptor(name:"wrong",type:kAudioUnitType_Effect,subtype:0,manufacturer:0)
        XCTAssertThrowsError(try AUInstrumentWorkerFiles.validate(request(instrument:instrument)))
        instrument.plugin?.type=kAudioUnitType_MusicDevice;instrument.plugin?.state=Data([1,2,3])
        XCTAssertThrowsError(try AUInstrumentWorkerFiles.validate(request(instrument:instrument)))
        var bad=try request();bad.version=2
        XCTAssertThrowsError(try AUInstrumentWorkerFiles.validate(bad))
    }
    func testBoundedRequestFilesAndSession() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);defer{try? FileManager.default.removeItem(at:dir)}
        let original=try request()
        try AUInstrumentWorkerFiles.writeRequest(original,to:dir)
        XCTAssertEqual(try AUInstrumentWorkerFiles.readRequest(in:dir,session:original.session).session,original.session)
        XCTAssertThrowsError(try AUInstrumentWorkerFiles.writeRequest(original,to:dir))
        XCTAssertThrowsError(try AUInstrumentWorkerFiles.readRequest(in:dir,session:UUID()))
        try FileManager.default.setAttributes([.posixPermissions:0o644],ofItemAtPath:dir.appendingPathComponent("request.json").path)
        XCTAssertThrowsError(try AUInstrumentWorkerFiles.readRequest(in:dir,session:original.session))
    }
    func testFIFORequestIsRejectedWithoutWaitingForWriter() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        defer { try? FileManager.default.removeItem(at:dir) }
        XCTAssertEqual(mkfifo(dir.appendingPathComponent("request.json").path,mode_t(0o600)),0)
        // No writer exists: a blocking open would never reach regular-file validation.
        let start=ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try AUInstrumentWorkerFiles.readRequest(in:dir,session:UUID()))
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime-start,1)
    }
    func testLongSongWithinExistingFrameCeiling() throws {
        var context=MusicContext();context.tempo=120
        let clock=try MusicClock(bars:400,context:context)
        let r=AUInstrumentWorkerRequest(session:UUID(),notes:[],instrument:Instrument(),clock:clock,tail:2,hostContext:nil)
        XCTAssertEqual(try AUInstrumentWorkerFiles.validate(r).frames,802*48_000)
    }
}
