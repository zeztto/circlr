import Foundation
import AudioToolbox
import CirclrCore

public struct SoundBankLoadAddress:Equatable {
    public let program:UInt8
    public let bankMSB:UInt8
    public let bankLSB:UInt8
}

extension AudioUnitHost {
    /// AudioToolbox reads DLS/SF2 metadata without creating an instrument or audio engine.
    public static func soundBankCatalog(at url:URL=bankURL)throws->[SoundBankPreset] {
        var info:Unmanaged<CFArray>?
        let status=CopyInstrumentInfoFromSoundBank(url as CFURL,&info)
        let value=info?.takeRetainedValue()
        guard status==noErr,let entries=value as? [[String:Any]] else{throw CirclrError("macOS Sound Bank 목록을 읽을 수 없습니다 (\(status))")}
        return SoundBankPreset.ordered(entries.compactMap {entry in
            guard let name=entry[kInstrumentInfoKey_Name] as? String,
                  let msb=entry[kInstrumentInfoKey_MSB] as? Int,let lsb=entry[kInstrumentInfoKey_LSB] as? Int,
                  let program=entry[kInstrumentInfoKey_Program] as? Int,
                  msb==kAUSampler_DefaultMelodicBankMSB || msb==kAUSampler_DefaultPercussionBankMSB else{return nil}
            return SoundBankPreset(name:name,program:program,bankLSB:lsb,drums:msb==kAUSampler_DefaultPercussionBankMSB)
        })
    }
    public static func soundBankLoadAddress(_ config:Instrument)throws->SoundBankLoadAddress {
        guard config.kind == .soundBank,(0...127).contains(config.program),(0...127).contains(config.bankLSB ?? 0) else{throw CirclrError("Sound Bank 음색·변형 번호를 확인하세요")}
        return SoundBankLoadAddress(program:UInt8(config.program),bankMSB:UInt8(config.drums ? kAUSampler_DefaultPercussionBankMSB:kAUSampler_DefaultMelodicBankMSB),bankLSB:UInt8(config.bankLSB ?? 0))
    }
}
