import Foundation

public struct PlaybackOutputStatus:Equatable,Codable,Sendable {
    public enum Phase:String,Codable,Sendable {case idle,connecting,ready}
    public enum Step:String,Codable,Sendable {case player,device,routing,ready}
    public enum Request:String,Codable,Sendable {case none,waiting,timedOut,cancelled}
    public var phase:Phase = .idle
    public var step:Step?
    public var request:Request = .none
    public var attemptID:UUID?
    public var attempts=0
    public var elapsedSeconds=0
    public init() {}
}

public enum PlaybackOutputWaitError:LocalizedError {
    case timedOut,invalidTimeout
    public var errorDescription:String? {
        switch self {
        case .timedOut:return "출력 장치 응답을 기다리고 있습니다. 준비되면 다시 재생하세요. 음악 편집은 계속할 수 있습니다."
        case .invalidTimeout:return "출력 연결 대기 시간이 올바르지 않습니다"
        }
    }
}

/// A caller may stop waiting; the system's in-flight device call still has exactly one owner.
@MainActor final class PlaybackOutputConnection {
    typealias Report = @Sendable (PlaybackOutputStatus.Step) async -> Void
    private let connect:@Sendable (@escaping Report) async -> Void
    private var worker:Task<Void,Never>?
    private var value=PlaybackOutputStatus()
    private var startedAt:TimeInterval?
    private var finishedAt:TimeInterval?
    private var requestGeneration=0
    var onChange:(()->Void)?
    init(connect:@escaping @Sendable (@escaping Report) async -> Void){self.connect=connect}
    var status:PlaybackOutputStatus {
        var result=value
        if let startedAt {result.elapsedSeconds=Int(max(0,(finishedAt ?? ProcessInfo.processInfo.systemUptime)-startedAt))}
        return result
    }
    private func startIfNeeded() {
        guard worker==nil else{return}
        value.phase = .connecting;value.step = .player;value.attemptID=UUID();value.attempts+=1
        startedAt=ProcessInfo.processInfo.systemUptime
        let connect=connect
        worker=Task.detached(priority:.userInitiated){[weak self] in
            await connect{[weak self] step in await self?.report(step)}
            await self?.completed()
        }
        onChange?()
    }
    private func report(_ step:PlaybackOutputStatus.Step) {value.step=step;onChange?()}
    private func completed() {
        finishedAt=ProcessInfo.processInfo.systemUptime;value.phase = .ready;value.step = .ready;onChange?()
    }
    func cancelWait() {
        requestGeneration+=1
        if value.request == .waiting {value.request = .cancelled;onChange?()}
    }
    func waitUntilReady(timeout:TimeInterval=10) async throws {
        guard timeout.isFinite,timeout>0 else{throw PlaybackOutputWaitError.invalidTimeout}
        try Task.checkCancellation()
        requestGeneration+=1;let ticket=requestGeneration
        value.request = .waiting;startIfNeeded();onChange?()
        let deadline=ProcessInfo.processInfo.systemUptime+timeout
        do {
            while value.phase != .ready {
                try Task.checkCancellation()
                guard ticket==requestGeneration else{throw CancellationError()}
                guard ProcessInfo.processInfo.systemUptime<deadline else {
                    value.request = .timedOut;onChange?();throw PlaybackOutputWaitError.timedOut
                }
                try await Task.sleep(for:.milliseconds(40))
            }
            try Task.checkCancellation()
            guard ticket==requestGeneration else{throw CancellationError()}
            value.request = .none;onChange?()
        } catch {
            if ticket==requestGeneration,error is CancellationError {value.request = .cancelled;onChange?()}
            throw error
        }
    }
}
