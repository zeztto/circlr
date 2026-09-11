import Foundation

/// Opaque sRGB accents; background and text remain theme-owned.
public struct CircleColor: Codable, Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red; self.green = green; self.blue = blue
    }
    public enum Preset: String, CaseIterable {
        case mint, blue, coral, violet, amber, rose, teal, silver
        public var title: String {
            switch self {
            case .mint: return "민트"
            case .blue: return "블루"
            case .coral: return "코럴"
            case .violet: return "바이올렛"
            case .amber: return "앰버"
            case .rose: return "로즈"
            case .teal: return "틸"
            case .silver: return "실버"
            }
        }
        public var color: CircleColor {
            switch self {
            case .mint: return .init(red: 133, green: 224, blue: 186)
            case .blue: return .init(red: 158, green: 191, blue: 240)
            case .coral: return .init(red: 235, green: 156, blue: 134)
            case .violet: return .init(red: 188, green: 166, blue: 232)
            case .amber: return .init(red: 222, green: 192, blue: 126)
            case .rose: return .init(red: 220, green: 154, blue: 192)
            case .teal: return .init(red: 118, green: 200, blue: 207)
            case .silver: return .init(red: 171, green: 180, blue: 195)
            }
        }
    }
}

extension CircleSceneNode {
    public var baseColor: CircleColor {
        if let music {
            switch music.content {
            case .midi, .rhythmMIDI: return CircleColor.Preset.mint.color
            case .audio, .rhythmAudio: return CircleColor.Preset.blue.color
            case .effect: return CircleColor.Preset.coral.color
            case .instrument: return CircleColor.Preset.teal.color
            default: return CircleColor.Preset.silver.color
            }
        }
        if let signal {
            return (signal.kind == .effect ? CircleColor.Preset.coral : signal.kind == .source ? .teal : .silver).color
        }
        switch role {
        case .song, .movement: return CircleColor.Preset.violet.color
        case .section: return CircleColor.Preset.amber.color
        case .album: return CircleColor.Preset.rose.color
        default: return CircleColor.Preset.silver.color
        }
    }
}
