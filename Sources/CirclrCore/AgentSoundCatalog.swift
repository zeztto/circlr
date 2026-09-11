import Foundation
import CryptoKit

public struct AgentSoundItem:Codable,Equatable,Identifiable {
    public let id:String
    public let category:String
    public let name:String
    public let detail:String
    public var synthVoice:SynthVoice?
    public var program:Int?
    public var bankLSB:Int?
    public var drums:Bool?
    public var plugin:PluginDescriptor?
    init(_ item:SoundCatalogItem) {
        category=item.category.rawValue;name=item.title;detail=item.detail
        switch item.id {
        case .synth(let voice):id="synth:\(voice.rawValue)";synthVoice=voice
        case .soundBank(let program,let lsb,let drums):
            id="bank:\(drums ? "drums":"melodic"):\(program):\(lsb)"
            self.program=program;bankLSB=lsb;self.drums=drums
        case .audioUnit(let component):
            id="au:"+component;plugin=item.plugin;plugin?.state=nil
        }
    }
}

public struct AgentSoundPage:Codable,Equatable {
    public let schema:String
    public let catalogID:String
    public let soundTarget:String
    public let query:String
    public let category:String?
    public let bankDrums:Bool?
    public let offset:Int
    public let limit:Int
    public let total:Int
    public let nextOffset:Int?
    public let items:[AgentSoundItem]
    public let notices:[String]
}

/// A startup snapshot shared with the GUI. Queries never instantiate audio units or edit a project.
public struct AgentSoundCatalog {
    public let id:String
    private let instruments:[SoundCatalogItem]
    private let effects:[SoundCatalogItem]
    private let notices:[String]
    public init(instruments:[SoundCatalogItem],effects:[SoundCatalogItem],bankNotice:String="")throws {
        self.instruments=instruments;self.effects=effects
        notices=bankNotice.isEmpty ? []:[bankNotice]
        struct Identity:Encodable {let schema:String;let instruments:[AgentSoundItem];let effects:[AgentSoundItem];let notices:[String]}
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        let data=try encoder.encode(Identity(schema:"circlr-sounds-v1",instruments:instruments.map(AgentSoundItem.init),effects:effects.map(AgentSoundItem.init),notices:notices))
        id=SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
    }
    public func page(_ args:AgentArguments)throws->AgentSoundPage {
        let target=args.soundTarget ?? "instrument",query=args.query ?? "",offset=args.offset ?? 0,limit=args.limit ?? 64
        guard ["instrument","effect"].contains(target),query.unicodeScalars.count<=256,(0...1_000_000).contains(offset),(1...128).contains(limit) else{throw CirclrError("음색 조회 대상·검색어(256자)·offset(0–1000000)·limit(1–128)을 확인하세요")}
        let category=args.category.flatMap(SoundCategory.init(rawValue:))
        if args.category != nil && category == nil {throw CirclrError("음색 category를 확인하세요")}
        if target=="effect" {
            guard category==nil || category == .effect,args.bankDrums==nil else{throw CirclrError("AU 이펙트 조회에는 악기 종류·드럼 필터를 사용할 수 없습니다")}
        }else{
            guard category != .effect,args.bankDrums==nil || category==nil || category == .soundBank else{throw CirclrError("드럼 필터는 Sound Bank에만 사용할 수 있습니다")}
        }
        if let expected=args.catalogID,expected != id {throw CirclrError("stale_catalog: 음색 목록이 바뀌었습니다. catalogID 없이 첫 페이지부터 다시 조회하세요")}
        let rows=SoundSelection.search(target=="instrument" ? instruments:effects,query:query,category:category,bankDrums:args.bankDrums)
        let start=min(offset,rows.count),end=min(start+limit,rows.count)
        return AgentSoundPage(schema:"circlr-sounds-v1",catalogID:id,soundTarget:target,query:query,category:category?.rawValue,bankDrums:args.bankDrums,offset:offset,limit:limit,total:rows.count,nextOffset:end<rows.count ? end:nil,items:rows[start..<end].map(AgentSoundItem.init),notices:target=="instrument" ? notices:[])
    }
}
