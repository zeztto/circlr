import XCTest
import AVFAudio
import AudioToolbox
import CirclrCore
@testable import CirclrAudio

/// Opt-in. Run this method in its own externally bounded test process: even the
/// in-process reference plugin can hang. Neither path starts a physical engine.
final class AUInstrumentWorkerIntegrationTests:XCTestCase {
    func testSoundBankAndCapturedSamplerMatchOfflineReference() async throws {
        guard let path=ProcessInfo.processInfo.environment["CIRCLR_AU_INSTRUMENT_WORKER_TEST_EXECUTABLE"],!path.isEmpty else {
            throw XCTSkip("별도 bounded runner와 instrument helper 경로가 필요합니다")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath:AudioUnitHost.bankURL.path))
        var context=MusicContext();context.tempo=120
        let parent=try MusicClock(bars:2,context:context,meterChanges:[MeterChange(bar:1,meter:Meter(3,4))],tempoChanges:[TempoChange(beat:1,bpm:160)])
        let clock=try MusicClock(parent:parent,start:0.5,length:4.25,context:context,inheritTempo:true,inheritMeter:true)
        let notes=[Note(beat:0,length:0.5,pitch:60,velocity:90),Note(beat:0.25,length:0.75,pitch:60,velocity:75),Note(beat:1,length:0.5,pitch:64,velocity:85),Note(beat:9,length:1,pitch:72,velocity:80)]
        let bank=Instrument(program:4)
        let unit=try await AudioUnitHost.instrument(bank)
        var sampler=Instrument();sampler.kind = .audioUnit
        sampler.plugin=PluginDescriptor(name:"Apple sampler captured QA",type:kAudioUnitType_MusicDevice,subtype:kAudioUnitSubType_Sampler,manufacturer:kAudioUnitManufacturer_Apple,state:try AudioUnitHost.capture(unit))
        XCTAssertNotNil(sampler.plugin?.state)
        let worker=AUInstrumentWorkerProcess(executable:URL(fileURLWithPath:path),timeout:15)
        for instrument in [bank,sampler] {
            for host in [nil,context] as [MusicContext?] {
                let expected=try await AudioUnitHost.renderNotes(notes,instrument:instrument,clock:clock,tail:0.2,hostContext:host)
                let actual=try await worker.render(notes:notes,instrument:instrument,clock:clock,tail:0.2,hostContext:host)
                XCTAssertEqual(actual.count,expected.count)
                XCTAssertTrue((actual.left + actual.right).allSatisfy { $0.isFinite })
                XCTAssertTrue((expected.left + expected.right).allSatisfy { $0.isFinite })
                XCTAssertGreaterThan(actual.left.map { abs($0) }.max() ?? 0, 0.00001)
                XCTAssertGreaterThan(expected.left.map{abs($0)}.max() ?? 0,0.00001)
                let maximum=zip(actual.left+actual.right,expected.left+expected.right).map{abs($0-$1)}.max() ?? 0
                XCTAssertLessThanOrEqual(maximum,0.000001)
                print("AU_INSTRUMENT_PCM_MATCH kind=\(instrument.kind.rawValue) host=\(host == nil ? "clock" : "override") frames=\(actual.count) maxError=\(maximum)")
            }
        }
    }
}
