import Foundation

/// RPN sensitivity data bytes; values are preserved, including cents above 99.
public struct MIDIPitchBendRange:Codable,Equatable,Sendable {
    public var semitones:Int
    public var cents:Int
    public init(semitones:Int=2,cents:Int=0){self.semitones=semitones;self.cents=cents}
    public var totalSemitones:Double {Double(semitones)+Double(cents)/100}
    public func validate()throws {
        guard (0...127).contains(semitones),(0...127).contains(cents) else{throw CirclrError("피치 벤드 범위의 반음·센트 data byte는 0–127이어야 합니다")}
    }
}

public struct MIDIPitchBendEvent:Codable,Equatable,Sendable {
    public enum Kind:Codable,Equatable,Sendable {case value(Int),range(MIDIPitchBendRange)}
    public var beat:Double
    public var kind:Kind
    public init(beat:Double,kind:Kind){self.beat=beat;self.kind=kind}
    public func validate()throws {
        guard beat.isFinite,(0...131072).contains(beat) else{throw CirclrError("피치 벤드 위치는 유한한 0–131072박이어야 합니다")}
        switch kind {
        case .value(let value):guard (0...16383).contains(value) else{throw CirclrError("피치 벤드 raw 값은 0–16383이어야 합니다")}
        case .range(let range):try range.validate()
        }
    }
}

public struct MIDIPitchBendState:Equatable,Sendable {
    public let rawValue:Int
    public let range:MIDIPitchBendRange
    public init(rawValue:Int,range:MIDIPitchBendRange) {self.rawValue=rawValue;self.range=range}
    public var semitones:Double {(Double(rawValue)-8192)/8192*range.totalSemitones}
}

/// Standalone source-state contract. Not yet part of Project, Lane, or rendering.
public struct MIDIPitchBendSequence:Codable,Equatable,Sendable {
    public var channel:Int
    public var initialValue:Int
    public var initialRange:MIDIPitchBendRange
    public var events:[MIDIPitchBendEvent]
    public init(channel:Int=0,initialValue:Int=8192,initialRange:MIDIPitchBendRange = .init(),events:[MIDIPitchBendEvent]=[]) {
        self.channel=channel;self.initialValue=initialValue;self.initialRange=initialRange;self.events=events
    }
    public func validate()throws {
        guard (0...15).contains(channel),(0...16383).contains(initialValue),events.count<=100000 else{throw CirclrError("피치 벤드 채널·초기값·이벤트 수를 확인하세요")}
        try initialRange.validate()
        var previous=0.0
        for event in events {
            try event.validate()
            guard event.beat>=previous else{throw CirclrError("피치 벤드 이벤트는 시간순이어야 합니다")}
            previous=event.beat
        }
    }
    /// Hold evaluation includes all events at the query beat, in stored order.
    /// Validate the complete source so a malformed later event cannot be hidden.
    /// This checked convenience query is O(event count), not a per-sample render API.
    /// A future renderer must validate once and consume an ordered stream cursor.
    public func state(atBeat beat:Double)throws->MIDIPitchBendState {
        guard beat.isFinite,(0...131072).contains(beat) else{throw CirclrError("피치 벤드 조회 위치를 확인하세요")}
        try validate()
        var value=initialValue,range=initialRange
        for event in events {
            guard event.beat<=beat else{break}
            switch event.kind {case .value(let next):value=next;case .range(let next):range=next}
        }
        return MIDIPitchBendState(rawValue:value,range:range)
    }
}
