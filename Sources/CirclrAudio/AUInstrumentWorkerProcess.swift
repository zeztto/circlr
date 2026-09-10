import Foundation
import Darwin
import CirclrCore

public enum AUInstrumentWorkerProcessError:Error,LocalizedError {
    case invalidInput,invalidDeadline,unavailable,timedOut,childFailed(Int32)
    public var errorDescription:String? {
        switch self {
        case .invalidInput:return "Audio Unit 악기에 전달할 오디오를 확인하세요"
        case .invalidDeadline:return "Audio Unit 악기 처리 제한 시간을 확인하세요"
        case .unavailable:return "Audio Unit 악기 helper를 찾을 수 없습니다. 앱 설치를 확인하세요"
        case .timedOut:return "Audio Unit 악기 처리가 제한 시간을 넘었습니다"
        case .childFailed(let status):return "Audio Unit 악기 helper가 정상적으로 완료되지 않았습니다 (\(status))"
        }
    }
}

/// Each invocation owns an independent child and retains its files until that child is reaped.
/// Audio Units are never loaded into this host process.
public final class AUInstrumentWorkerProcess:@unchecked Sendable {
    private let executable:URL?
    private let timeout:Double?
    private let temporaryRoot:URL
    private let beforeLaunch:(@Sendable ()->Void)?

    public convenience init(executable:URL?=Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("circlr-au-instrument-worker"),timeout:Double?=nil) {
        self.init(executable:executable,timeout:timeout,temporaryRoot:FileManager.default.temporaryDirectory,beforeLaunch:nil)
    }
    init(executable:URL?,timeout:Double?,temporaryRoot:URL,beforeLaunch:(@Sendable ()->Void)?=nil) {
        self.executable=executable;self.timeout=timeout;self.temporaryRoot=temporaryRoot;self.beforeLaunch=beforeLaunch
    }
    static func deadlineSeconds(for duration:Double)->Double {min(1800,max(30,duration*4+15))}

    public func render(notes:[Note],instrument:Instrument,clock:MusicClock,tail:Double,hostContext:MusicContext? = nil) async throws->PCM {
        try Task.checkCancellation()
        let request = AUInstrumentWorkerRequest(session:UUID(),notes:notes,instrument:instrument,clock:clock,tail:tail,hostContext:hostContext)
        let frames = try AUInstrumentWorkerFiles.validate(request).frames
        if notes.isEmpty { return PCM(frames:frames) }
        let seconds=timeout ?? Self.deadlineSeconds(for:Double(frames)/PCM.rate)
        guard seconds.isFinite,seconds>0 else{throw AUInstrumentWorkerProcessError.invalidDeadline}
        let operation=Operation(executable:executable,timeout:seconds,temporaryRoot:temporaryRoot,beforeLaunch:beforeLaunch)
        let output:PCM=try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue(label:"circlr.au-instrument-host."+operation.id.uuidString).async {
                    do {continuation.resume(returning:try operation.run(request:request))}
                    catch {continuation.resume(throwing:error)}
                }
            }
        } onCancel: {operation.cancel()}
        // A cancellation arriving while the final result was being delivered still wins.
        try Task.checkCancellation()
        return output
    }

    private final class Operation:@unchecked Sendable {
        let id=UUID()
        private let executable:URL?
        private let timeout:Double
        private let temporaryRoot:URL
        private let beforeLaunch:(@Sendable ()->Void)?
        private let lock=NSLock()
        private var cancelled=false
        init(executable:URL?,timeout:Double,temporaryRoot:URL,beforeLaunch:(@Sendable ()->Void)?) {
            self.executable=executable;self.timeout=timeout;self.temporaryRoot=temporaryRoot;self.beforeLaunch=beforeLaunch
        }
        func cancel(){lock.lock();cancelled=true;lock.unlock()}
        private func check(_ deadline:Double)throws {
            lock.lock();let stopped=cancelled;lock.unlock()
            if stopped {throw CancellationError()}
            if ProcessInfo.processInfo.systemUptime>=deadline {throw AUInstrumentWorkerProcessError.timedOut}
        }
        func run(request:AUInstrumentWorkerRequest)throws->PCM {
            var request=request;request.session=id
            let frames=try AUInstrumentWorkerFiles.validate(request).frames
            let deadline=ProcessInfo.processInfo.systemUptime+timeout
            try check(deadline)
            guard let executable,FileManager.default.isExecutableFile(atPath:executable.path) else {throw AUInstrumentWorkerProcessError.unavailable}
            let directory=temporaryRoot.appendingPathComponent("circlr-au-instrument-"+id.uuidString,isDirectory:true)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
            let process=Process(),stdin=Pipe()
            var launched=false,reaped=false,cleaned=false
            defer {
                // No delayed callbacks or PID-only timers survive this invocation.
                try? stdin.fileHandleForWriting.close()
                if launched && !reaped {terminateAndReap(process)}
                try? stdin.fileHandleForReading.close()
                if !cleaned {try? FileManager.default.removeItem(at:directory)}
            }
            try AUInstrumentWorkerFiles.writeRequest(request,to:directory)
            try check(deadline)
            beforeLaunch?()
            try check(deadline)
            process.executableURL=executable
            process.arguments=["--session",id.uuidString,"--directory",directory.path]
            process.standardInput=stdin
            process.standardOutput=FileHandle.nullDevice
            process.standardError=FileHandle.nullDevice
            try process.run();launched=true
            try? stdin.fileHandleForReading.close()
            while process.isRunning {
                try check(deadline)
                Thread.sleep(forTimeInterval:0.01)
            }
            process.waitUntilExit();reaped=true
            try check(deadline)
            guard process.terminationReason == .exit,process.terminationStatus==0 else {
                throw AUInstrumentWorkerProcessError.childFailed(process.terminationStatus)
            }
            let result=try AUEffectWorkerFiles.readResult(in:directory,session:id,frames:frames,checkCancellation:{try self.check(deadline)})
            try check(deadline)
            try FileManager.default.removeItem(at:directory);cleaned=true
            return result
        }
        private func terminateAndReap(_ process:Process) {
            if process.isRunning {
                // Only this still-owned Process may be signalled; its PID has not been released.
                _ = Darwin.kill(process.processIdentifier,SIGTERM)
                let grace=ProcessInfo.processInfo.systemUptime+0.2
                while process.isRunning && ProcessInfo.processInfo.systemUptime<grace {Thread.sleep(forTimeInterval:0.01)}
                if process.isRunning {_ = Darwin.kill(process.processIdentifier,SIGKILL)}
            }
            process.waitUntilExit()
        }
    }
}
