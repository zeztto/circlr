import Foundation

/// Discovery metadata is not persisted into a song or an Audio Unit state.
public struct AudioUnitCatalogEntry: Equatable {
    public let descriptor: PluginDescriptor
    public let manufacturerName: String
    public init(descriptor: PluginDescriptor, manufacturerName: String) {
        self.descriptor=descriptor; self.manufacturerName=manufacturerName
    }
}

public enum SoundChoice: Hashable {
    case synth(SynthVoice), soundBank, audioUnit(String)
}
public enum SoundCategory: String, CaseIterable, Identifiable {
    case synth, soundBank, instrument, effect
    public var id: Self {self}
    public var label: String {
        switch self {case .synth:return "내장 신스";case .soundBank:return "Sound Bank"
        case .instrument:return "AU 악기";case .effect:return "AU 이펙트"}
    }
}
public struct SoundCatalogItem: Identifiable, Equatable {
    public let id: SoundChoice
    public let category: SoundCategory
    public let title: String
    public let detail: String
    public let plugin: PluginDescriptor?
}

public enum SoundSelection {
    // AudioComponentDescription types: aumu (music device), aufx (effect).
    public static let instrumentType: UInt32 = 0x61756D75
    public static let effectType: UInt32 = 0x61756678
    public static func instruments(_ plugins: [AudioUnitCatalogEntry]) -> [SoundCatalogItem] {
        SynthVoice.allCases.map {SoundCatalogItem(id:.synth($0),category:.synth,title:$0.label,detail:"내장 신스 · "+String(describing:$0),plugin:nil)}
        + [.init(id:.soundBank,category:.soundBank,title:"기본 Sound Bank",detail:"GM Program · 멜로디 / 드럼",plugin:nil)]
        + audioUnits(plugins,type:instrumentType,category:.instrument)
    }
    public static func effects(_ plugins: [AudioUnitCatalogEntry]) -> [SoundCatalogItem] {
        audioUnits(plugins,type:effectType,category:.effect)
    }
    private static func audioUnits(_ entries:[AudioUnitCatalogEntry],type:UInt32,category:SoundCategory)->[SoundCatalogItem] {
        var seen=Set<String>()
        return entries.filter{$0.descriptor.type==type && seen.insert($0.descriptor.id).inserted}.map {
            .init(id:.audioUnit($0.descriptor.id),category:category,title:$0.descriptor.name,
                  detail:category.label+" · "+$0.manufacturerName,plugin:$0.descriptor)
        }.sorted {
            let a=$0.title.localizedStandardCompare($1.title)
            if a != .orderedSame{return a == .orderedAscending}
            return ($0.detail,$0.plugin!.id)<($1.detail,$1.plugin!.id)
        }
    }
    public static func search(_ entries:[SoundCatalogItem],query:String,category:SoundCategory?=nil)->[SoundCatalogItem] {
        let terms=folded(query).split(whereSeparator:{$0.isWhitespace})
        return entries.filter {entry in
            guard category==nil || category==entry.category else{return false}
            let text=folded(entry.title+" "+entry.detail+" "+entry.category.label)
            return terms.allSatisfy{text.contains($0)}
        }
    }
    private static func folded(_ value:String)->String {
        value.folding(options:[.caseInsensitive,.diacriticInsensitive,.widthInsensitive],locale:Locale(identifier:"en_US_POSIX")).precomposedStringWithCanonicalMapping
    }
    public static func choice(in instrument:Instrument)->SoundChoice? {
        switch instrument.kind {case .synthesizer:return .synth((instrument.synth ?? SynthPatch()).voice)
        case .soundBank:return .soundBank;case .audioUnit:return instrument.plugin.map{.audioUnit($0.id)};case .sampler:return nil}
    }
    public static func instrument(_ choice:SoundChoice,current:Instrument,catalog:[SoundCatalogItem]) throws -> Instrument {
        guard let entry=catalog.first(where:{$0.id==choice}),entry.category != .effect else{throw CirclrError("사용 가능한 악기를 다시 선택하세요")}
        var next=current
        if self.choice(in:current)==choice {return current}
        switch choice {
        case .synth(let voice):
            next.kind = .synthesizer
            if current.synth?.voice != voice {next.synth=SynthPatch(voice)}
        case .soundBank:next.kind = .soundBank
        case .audioUnit:
            guard let plugin=entry.plugin,plugin.type==instrumentType else{throw CirclrError("AU 악기를 선택하세요")}
            next.kind = .audioUnit
            if current.plugin?.id != plugin.id {next.plugin=plugin}
        }
        return next
    }
    public static func effect(_ choice:SoundChoice,current:Effect,catalog:[SoundCatalogItem]) throws -> Effect {
        guard let entry=catalog.first(where:{$0.id==choice}),entry.category == .effect,
              let plugin=entry.plugin,plugin.type==effectType else{throw CirclrError("사용 가능한 AU 이펙트를 다시 선택하세요")}
        if current.kind == .audioUnit && current.plugin?.id==plugin.id{return current}
        var next=current;next.kind = .audioUnit
        if current.plugin?.id != plugin.id {next.plugin=plugin}
        return next
    }
}
