import Foundation

public struct AuditionStatus:Equatable,Codable,Sendable {
    public enum Phase:String,Codable,Sendable {case idle,preparing,ready,stopping,failed}
    public var phase:Phase = .idle
    public var attempts=0
    public var heldNotes=0
    public var elapsedSeconds=0
    public var message:String?
    public var trace:AuditionTrace?
    public var pending:Bool {phase == .preparing || phase == .stopping}
    public init(){}
}

public struct AuditionTraceEvent:Equatable,Codable,Sendable {
    public enum Stage:String,Codable,Sendable,CaseIterable {
        case backendPreparation,sourceLoad,auInstantiation,engineCreation,mixerAcquisition,routing,engineStart,note,cleanup
    }
    public enum Phase:String,Codable,Sendable {case entered,completed}
    public let sequence:UInt64
    public let stage:Stage
    public let phase:Phase
    public let elapsedSeconds:Double
}
public typealias AuditionDiagnosticReporter = @Sendable (AuditionTraceEvent.Stage,AuditionTraceEvent.Phase)->Void

public struct AuditionTraceInterruption:Equatable,Codable,Sendable {
    public enum Reason:String,Codable,Sendable {case cancelled,timedOut,superseded,failed}
    public let reason:Reason
    public let elapsedSeconds:Double
    /// Frozen at the first interruption; subsequent cleanup cannot overwrite it.
    public let inFlight:AuditionTraceEvent?
}
public struct AuditionTrace:Equatable,Codable,Sendable {
    public static let maximumEvents=64
    public let sessionID:UUID
    public private(set) var events:[AuditionTraceEvent]=[]
    public private(set) var inFlight:AuditionTraceEvent?
    public private(set) var interruption:AuditionTraceInterruption?
    init(sessionID:UUID){self.sessionID=sessionID}
    mutating func record(_ stage:AuditionTraceEvent.Stage,_ phase:AuditionTraceEvent.Phase,elapsed:Double) {
        guard elapsed.isFinite,elapsed>=0,elapsed >= (events.last?.elapsedSeconds ?? 0),
              (events.last?.sequence ?? 0)<UInt64.max else{return}
        switch phase {
        case .entered:
            // Cleanup may follow a thrown/blocked operation after it returns.
            guard inFlight == nil || stage == .cleanup else{return}
        case .completed:guard inFlight?.stage == stage else{return}
        }
        let event=AuditionTraceEvent(sequence:(events.last?.sequence ?? 0)+1,stage:stage,phase:phase,elapsedSeconds:elapsed)
        events.append(event)
        if events.count>Self.maximumEvents {events.removeFirst(events.count-Self.maximumEvents)}
        inFlight=phase == .entered ? event:nil
    }
    mutating func interrupt(_ reason:AuditionTraceInterruption.Reason,elapsed:Double) {
        guard interruption == nil,elapsed.isFinite,elapsed>=0 else{return}
        interruption=AuditionTraceInterruption(reason:reason,elapsedSeconds:max(elapsed,events.last?.elapsedSeconds ?? 0),inFlight:inFlight)
    }
}
