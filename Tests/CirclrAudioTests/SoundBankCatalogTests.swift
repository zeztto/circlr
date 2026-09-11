import XCTest
import AudioToolbox
import CirclrCore
@testable import CirclrAudio

final class SoundBankCatalogTests:XCTestCase {
    func testInstalledMetadataUsesTheSameBankAddressesAsTheRenderer()throws {
        guard FileManager.default.fileExists(atPath:AudioUnitHost.bankURL.path) else{throw XCTSkip("macOS Sound Bank가 없는 환경")}
        let presets=try AudioUnitHost.soundBankCatalog()
        XCTAssertFalse(presets.isEmpty);XCTAssertEqual(Set(presets.map(\.id)).count,presets.count)
        for preset in presets {
            let config=Instrument(program:preset.program,drums:preset.drums,bankLSB:preset.bankLSB)
            let address=try AudioUnitHost.soundBankLoadAddress(config)
            XCTAssertEqual(Int(address.program),preset.program);XCTAssertEqual(Int(address.bankLSB),preset.bankLSB)
            XCTAssertEqual(Int(address.bankMSB),preset.drums ? kAUSampler_DefaultPercussionBankMSB:kAUSampler_DefaultMelodicBankMSB)
            XCTAssertEqual(preset.name,preset.name.trimmingCharacters(in:.whitespacesAndNewlines))
        }
    }
    func testLegacyDefaultAndInvalidLoadAddresses()throws {
        let melodic=try AudioUnitHost.soundBankLoadAddress(Instrument(program:4))
        XCTAssertEqual(melodic.program,4);XCTAssertEqual(melodic.bankMSB,121);XCTAssertEqual(melodic.bankLSB,0)
        let drums=try AudioUnitHost.soundBankLoadAddress(Instrument(program:25,drums:true,bankLSB:0))
        XCTAssertEqual(drums.bankMSB,120)
        XCTAssertThrowsError(try AudioUnitHost.soundBankLoadAddress(Instrument(program:128)))
        XCTAssertThrowsError(try AudioUnitHost.soundBankLoadAddress(Instrument(bankLSB:-1)))
        XCTAssertThrowsError(try AudioUnitHost.soundBankLoadAddress(.synthesizer(.pad)))
    }
    func testMissingBankDoesNotInventPresets() {
        XCTAssertThrowsError(try AudioUnitHost.soundBankCatalog(at:URL(fileURLWithPath:"/nonexistent-circlr-qa-sound-bank.dls")))
    }
}
