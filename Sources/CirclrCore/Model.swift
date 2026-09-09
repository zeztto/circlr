import Foundation

public typealias ID = String
public func newID() -> ID { UUID().uuidString }

public enum SettingSource: String, Codable, CaseIterable { case inherit, global, local }
public struct Setting<T: Codable & Equatable>: Codable, Equatable {
    public var source: SettingSource = .inherit
    public var value: T?
    public init(_ value: T? = nil, source: SettingSource = .inherit) { self.value = value; self.source = source }
    public static func local(_ value: T) -> Self { Self(value, source: .local) }
}
public struct Meter: Codable, Equatable, Hashable {
    public var numerator: Int
    public var denominator: Int
    public init(_ numerator: Int = 4, _ denominator: Int = 4) { self.numerator = numerator; self.denominator = denominator }
    public var quarters: Double { Double(numerator) * 4 / Double(denominator) }
    public var label: String { "\(numerator)/\(denominator)" }
}
public struct Scale: Codable, Equatable {
    public var root: Int
    public var name: String
    public var intervals: [Int]
    public init(root: Int = 0, name: String = "minor", intervals: [Int] = [0,2,3,5,7,8,10]) { self.root = root; self.name = name; self.intervals = intervals }
    public static let roots = ["C","C♯","D","E♭","E","F","F♯","G","A♭","A","B♭","B"]
    public static let modes: [(String, [Int])] = [("major",[0,2,4,5,7,9,11]),("minor",[0,2,3,5,7,8,10]),("Dorian",[0,2,3,5,7,9,10]),("Phrygian",[0,1,3,5,7,8,10]),("Lydian",[0,2,4,6,7,9,11]),("Mixolydian",[0,2,4,5,7,9,10]),("Locrian",[0,1,3,5,6,8,10]),("chromatic",Array(0...11))]
    public var label: String { "\(Self.roots[((root % 12) + 12) % 12]) \(name)" }
    public func contains(_ pitch: Int) -> Bool { intervals.contains(((pitch - root) % 12 + 12) % 12) }
}
public struct BeatGrid: Codable, Equatable {
    public var subdivisions: Int = 4
    public var accents: [Int] = []
    public var swing: Double = 0
    public init(subdivisions: Int = 4, accents: [Int] = [], swing: Double = 0) { self.subdivisions = subdivisions; self.accents = accents; self.swing = swing }
}
public struct RhythmAssignment: Codable, Equatable {
    public var patternID: ID?
    public init(_ patternID: ID? = nil) { self.patternID = patternID }
}
public struct MusicContext: Codable, Equatable {
    public var tempo: Double = 120
    public var scale = Scale()
    public var meter = Meter()
    public var beatGrid = BeatGrid()
    public var rhythm = RhythmAssignment()
    public init() {}
}
public struct ContextSettings: Codable, Equatable {
    public var tempo = Setting<Double>()
    public var scale = Setting<Scale>()
    public var meter = Setting<Meter>()
    public var beatGrid = Setting<BeatGrid>()
    public var rhythm = Setting<RhythmAssignment>()
    public init() {}
}
public struct MeterChange: Codable, Equatable { public var bar: Int; public var meter: Meter; public init(bar: Int, meter: Meter) { self.bar = bar; self.meter = meter } }
public struct TempoChange: Codable, Equatable { public var beat: Double; public var bpm: Double; public init(beat: Double, bpm: Double) { self.beat = beat; self.bpm = bpm } }
public struct Note: Codable, Equatable, Identifiable {
    public var id: ID = newID()
    public var beat: Double
    public var length: Double
    public var pitch: Int
    public var velocity: Int
    public init(beat: Double, length: Double = 0.5, pitch: Int = 60, velocity: Int = 96) { self.beat = beat; self.length = length; self.pitch = pitch; self.velocity = velocity }
    public init(from decoder:Decoder) throws {
        let values=try decoder.container(keyedBy:CodingKeys.self)
        id=try values.decodeIfPresent(ID.self,forKey:.id) ?? newID()
        beat=try values.decode(Double.self,forKey:.beat);length=try values.decode(Double.self,forKey:.length)
        pitch=try values.decode(Int.self,forKey:.pitch);velocity=try values.decode(Int.self,forKey:.velocity)
    }
}
public struct AudioClip: Codable, Equatable, Identifiable {
    public var id: ID = newID()
    public var assetID: ID
    public var beat: Double = 0
    public var sourceStart: Double = 0
    public var duration: Double
    public var gain: Double = 1
    public var followsTempo: Bool = false
    public var sourceBPM: Double = 120
    public var preservesTail: Bool?
    public var fadeIn: Double?
    public var fadeOut: Double?
    public var renderWindow: AudioRenderWindow?
    public init(assetID: ID, duration: Double, beat: Double = 0) { self.assetID = assetID; self.duration = duration; self.beat = beat }
}
public struct Lane: Codable, Equatable, Identifiable {
    public var id: ID = newID()
    public var trackID: ID
    public var notes: [Note] = []
    public var audio: [AudioClip] = []
    public init(trackID: ID) { self.trackID = trackID }
}
public struct PluginDescriptor: Codable, Equatable, Identifiable, Sendable {
    public var name: String
    public var type: UInt32
    public var subtype: UInt32
    public var manufacturer: UInt32
    public var state: Data?
    public var id: String { "\(type)-\(subtype)-\(manufacturer)" }
    public init(name: String, type: UInt32, subtype: UInt32, manufacturer: UInt32, state: Data? = nil) { self.name = name; self.type = type; self.subtype = subtype; self.manufacturer = manufacturer; self.state = state }
}
public struct Instrument: Codable, Equatable {
    public enum Kind: String, Codable, CaseIterable { case soundBank, audioUnit, synthesizer, sampler }
    public var kind: Kind = .soundBank
    public var program: Int = 0
    public var drums = false
    /// Missing in older songs means the original default Sound Bank variation.
    public var bankLSB: Int?
    public var plugin: PluginDescriptor?
    public var synth: SynthPatch?
    public var sample: SampleInstrument?
    public init(program: Int = 0, drums: Bool = false, bankLSB: Int? = nil) { self.program = program; self.drums = drums; self.bankLSB=bankLSB }
}
public struct Track: Codable, Equatable, Identifiable {
    public var id: ID = newID()
    public var name: String
    public var instrument: Instrument
    public var gain: Double = 0.7
    public var muted = false
    public init(name: String, instrument: Instrument = Instrument()) { self.name = name; self.instrument = instrument }
}
public enum EffectKind: String, Codable, CaseIterable { case gain, lowpass, delay, reverb, drive, pan, compressor, audioUnit }
public struct Effect: Codable, Equatable {
    public var renderVersion: Int?
    public var kind: EffectKind = .gain
    public var amount: Double = 0.5
    public var secondary: Double = 0.25
    public var plugin: PluginDescriptor?
    public init(_ kind: EffectKind = .gain, amount: Double = 0.5, secondary: Double = 0.25) { self.kind = kind; self.amount = amount; self.secondary = secondary; self.renderVersion = kind == .reverb ? 2:nil }
}
public struct Section: Codable, Equatable, Identifiable {
    public var id: ID = newID()
    public var name: String
    public var bars: Int = 8
    public var settings = ContextSettings()
    public var tempoChanges: [TempoChange] = []
    public var meterChanges: [MeterChange] = []
    public var lanes: [Lane] = []
    public var graph: SectionGraph?
    public init(name: String, bars: Int = 8) { self.name = name; self.bars = bars }
}
public struct SectionUse: Codable, Equatable, Identifiable {
    public var id: ID = newID()
    public var sectionID: ID
    public var name: String
    public var repeatCount: Int = 1
    public var isEnd = true
    public var settings = ContextSettings()
    public var barsOverride: Int?
    public var laneOverrides: [ID: Lane] = [:]
    public var addedLanes: [Lane] = []
    public var excludedLaneIDs: [ID] = []
    public var effects: [Effect] = []
    public var gain: Double = 1
    public var graphEdits: SectionGraphEdits?
    public init(sectionID: ID, name: String) { self.sectionID = sectionID; self.name = name }
    public var isVariant: Bool { !laneOverrides.isEmpty || !addedLanes.isEmpty || !excludedLaneIDs.isEmpty || barsOverride != nil || !effects.isEmpty || settings != ContextSettings() || gain != 1 || graphEdits.map({ !$0.isEmpty }) == true }
}
public struct RhythmPattern: Codable, Equatable, Identifiable {
    public var id: ID = newID()
    public var name: String
    public var length: Double = 4
    public var meter = Meter()
    public var trackID: ID
    public var notes: [Note] = []
    public var audio: [AudioClip] = []
    public init(name: String, trackID: ID) { self.name = name; self.trackID = trackID }
}
public enum TransitionMode: String, Codable, CaseIterable { case within, insert, overlap }
public enum TransitionAnchor: String, Codable, CaseIterable { case sourceBars, targetBars, seconds }
public struct Transition: Codable, Equatable {
    public var mode: TransitionMode = .within
    public var anchor: TransitionAnchor = .sourceBars
    public var length: Double = 0
    public var effect = Effect(.gain, amount: 1)
    public var patternID: ID?
    public var replaceTrackID: ID?
    public init() {}
}
public struct FlowEdge: Codable, Equatable, Identifiable {
    public var id: ID = newID()
    public var from: ID
    public var to: ID
    public var transition = Transition()
    public init(from: ID, to: ID) { self.from = from; self.to = to }
}
public struct Point: Codable, Equatable, Sendable { public var x: Double; public var y: Double; public init(_ x: Double = 0, _ y: Double = 0) { self.x = x; self.y = y } }
public struct CanvasGroup: Codable, Equatable, Identifiable {
    public var id: ID = newID()
    public var name: String
    public var members: [ID]
    public var collapsed = false
    public init(name: String, members: [ID]) { self.name = name; self.members = members }
}
public struct Layout: Codable, Equatable {
    public var positions: [ID: Point] = [:]
    public var groups: [CanvasGroup] = []
    public var pan = Point(100, 150)
    public var zoom: Double = 1
    public var grid = true
    public var snap = true
    public var spacing: Double = 24
    public init() {}
}
public struct Arrangement: Codable, Equatable, Identifiable {
    public var id: ID = newID()
    public var name: String
    public var uses: [SectionUse] = []
    public var edges: [FlowEdge] = []
    public var chosenEdges: [ID: ID] = [:]
    public var startID: ID?
    public var layout = Layout()
    public init(name: String = "편곡 A") { self.name = name }
}
public enum SignalKind: String, Codable { case source, effect, bus, master }
public struct SignalNode: Codable, Equatable, Identifiable {
    public var id: ID = newID()
    public var kind: SignalKind
    public var name: String
    public var trackID: ID?
    public var effect = Effect()
    public init(kind: SignalKind, name: String, trackID: ID? = nil) { self.kind = kind; self.name = name; self.trackID = trackID }
}
public struct SignalEdge: Codable, Equatable, Identifiable {
    public var id: ID = newID()
    public var from: ID
    public var to: ID
    public var gain: Double = 1
    public var sidechain = false
    public init(from: ID, to: ID) { self.from = from; self.to = to }
}
public struct SignalGraph: Codable, Equatable {
    public var nodes: [SignalNode] = []
    public var edges: [SignalEdge] = []
    public var layout = Layout()
    public init() {}
}
public struct Asset: Codable, Equatable, Identifiable {
    public var id: ID = newID()
    public var name: String
    public var path: String
    public var duration: Double
    public var sampleRate: Double
    public var checksum: String = ""
    public init(name: String, path: String, duration: Double, sampleRate: Double) { self.name = name; self.path = path; self.duration = duration; self.sampleRate = sampleRate }
}
public struct RecordedTake: Codable, Equatable, Identifiable {
    public var id: ID = newID()
    public var useID: ID
    public var targetLaneID: ID?
    public var arrangementID: ID?
    public var name: String
    public var lane: Lane
    public init(useID: ID, name: String, lane: Lane) { self.useID = useID; self.name = name; self.lane = lane }
}
public struct Project: Codable, Equatable {
    public var schemaVersion = 1
    public var album: Album?
    public var hierarchyView: HierarchyViewport?
    public var circleLayout: CircleLayout?
    public var portLayout:CirclePortLayout?
    /// Appearance overrides belong to a circle occurrence, not its shared musical content.
    /// Optional storage keeps manifests written before custom colors compatible.
    public var circleColors: [CircleAddress: CircleColor]?
    public var usesOrbits: Bool { circleLayout != .freeform }
    public var id: ID = newID()
    public var name = "새 곡"
    public var musicRevision: Int = 0
    public var global = MusicContext()
    public var tracks: [Track] = []
    public var sections: [Section] = []
    public var patterns: [RhythmPattern] = []
    public var arrangements: [Arrangement] = [Arrangement()]
    public var activeArrangementID: ID
    public var assets: [Asset] = []
    public var takes: [RecordedTake]? = []
    public var signal = SignalGraph()
    public init() {
        activeArrangementID = arrangements[0].id
        signal.nodes = [SignalNode(kind: .master, name: "출력")]
    }
    public var activeIndex: Int { arrangements.firstIndex(where: { $0.id == activeArrangementID }) ?? 0 }
    public var active: Arrangement { arrangements[activeIndex] }
    public mutating func addTrack(name: String, drums: Bool = false) -> ID {
        let track = Track(name: name, instrument: drums ? Instrument(program:0,drums:true):.synthesizer(.keys))
        tracks.append(track)
        let node = SignalNode(kind: .source, name: name, trackID: track.id)
        signal.nodes.append(node)
        signal.layout.positions[node.id] = Point(100, Double(tracks.count - 1) * 220)
        if let master = signal.nodes.first(where: { $0.kind == .master }) {
            signal.edges.append(SignalEdge(from: node.id, to: master.id))
            if signal.layout.positions[master.id] == nil {signal.layout.positions[master.id] = Point(650, 100)}
        }
        return track.id
    }
    @discardableResult public mutating func addSection(name: String, at point: Point, bars: Int = 8) -> ID {
        var section = Section(name: name, bars: bars)
        section.lanes = tracks.map { Lane(trackID: $0.id) }
        sections.append(section)
        let use = SectionUse(sectionID: section.id, name: name)
        arrangements[activeIndex].uses.append(use)
        arrangements[activeIndex].layout.positions[use.id] = point
        if arrangements[activeIndex].startID == nil { arrangements[activeIndex].startID = use.id }
        return use.id
    }
}
