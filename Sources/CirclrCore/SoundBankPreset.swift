import Foundation

/// Names come from the installed bank. No wave data or bank metadata is stored in a song.
public struct SoundBankPreset: Equatable, Identifiable {
    public let name:String
    public let program:Int
    public let bankLSB:Int
    public let drums:Bool
    public var id:SoundChoice {.soundBank(program:program,bankLSB:bankLSB,drums:drums)}
    public init?(name:String,program:Int,bankLSB:Int,drums:Bool) {
        let name=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty,name.count<=256,(0...127).contains(program),(0...127).contains(bankLSB) else{return nil}
        self.name=name;self.program=program;self.bankLSB=bankLSB;self.drums=drums
    }
    public var family:String {
        if drums{return "드럼 킷"}
        return ["피아노","건반 타악기","오르간","기타","베이스","현악기","앙상블","브라스",
                "리드 관악기","피리","신스 리드","신스 패드","신스 효과","민속 악기","타악기","효과음"][program/8]
    }
    public var detail:String {"Sound Bank · "+family+" · #\(program+1) · "+(bankLSB==0 ? "기본 뱅크":"변형 \(bankLSB)")}
    public var selectionName:String {name+" · #\(program+1)"+(drums ? " · 드럼 킷":"")+(bankLSB==0 ? "":" · 변형 \(bankLSB)")}
    public static func ordered(_ presets:[Self])->[Self] {
        var seen=Set<SoundChoice>()
        return presets.filter{seen.insert($0.id).inserted}.sorted {
            if $0.drums != $1.drums{return !$0.drums}
            return ($0.program,$0.bankLSB)<($1.program,$1.bankLSB)
        }
    }
}
