import Foundation
import Darwin
import CirclrCore

/// One persistent child per target. Only the transport's serial queue sends note operations.
final class WorkerAuditionBackend:AuditionBackend,@unchecked Sendable {
    private let process=Process(),input=Pipe(),output=Pipe(),reader=DispatchGroup()
    private let operations=NSRecursiveLock()
    private let state:WorkerState
    private let control:MediaPreviewCancellation
    private let directory:URL
    private let noteTimeout:Double
    private let grace:Double
    private var sequence:UInt64=0
    private var tokens:[Int:UUID]=[:]
    private var launched=false,stopped=false,ownsDirectory=false
    init(target:AuditionTarget,control:MediaPreviewCancellation,report:@escaping AuditionDiagnosticReporter,
         executable:URL?=Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("circlr-audition-worker"),
         temporaryRoot:URL=FileManager.default.temporaryDirectory,prepareTimeout:Double=8,noteTimeout:Double=2,stopGrace:Double=0.2)throws {
        let session=UUID();state=WorkerState(session:session,report:report);self.control=control
        directory=temporaryRoot.appendingPathComponent("circlr-audition-"+session.uuidString,isDirectory:true)
        self.noteTimeout=noteTimeout;grace=stopGrace
        do {
            guard [prepareTimeout,noteTimeout,stopGrace].allSatisfy({$0.isFinite && $0>0}) else{throw AuditionWorkerFiles.invalid()}
            guard !control.isCancelled else{throw CancellationError()}
            guard let executable,FileManager.default.isExecutableFile(atPath:executable.path) else{throw CirclrError("악기 미리 듣기 helper를 찾을 수 없습니다. 앱 설치를 확인하세요")}
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
            ownsDirectory=true
            try AuditionWorkerFiles.write(try AuditionWorkerRequest(session:session,target:target),in:directory)
            guard !control.isCancelled else{throw CancellationError()}
            process.executableURL=executable;process.arguments=["--session",session.uuidString,"--directory",directory.path]
            process.standardInput=input;process.standardOutput=output;process.standardError=FileHandle.nullDevice
            let incoming=input.fileHandleForWriting.fileDescriptor,outgoing=output.fileHandleForReading.fileDescriptor
            guard fcntl(incoming,F_SETNOSIGPIPE,1)==0 else{throw AuditionWorkerFiles.invalid()}
            for fd in [incoming,outgoing] {let flags=fcntl(fd,F_GETFL);guard flags>=0,fcntl(fd,F_SETFL,flags|O_NONBLOCK)==0 else{throw AuditionWorkerFiles.invalid()}}
            let state=state
            process.terminationHandler={ child in state.fail("악기 미리 듣기 worker가 종료되었습니다 (\(child.terminationStatus))") }
            try process.run();launched=true
            try? input.fileHandleForReading.close();try? output.fileHandleForWriting.close()
            let reader=reader;reader.enter()
            DispatchQueue(label:"circlr.audition-worker.stdout").async {Self.read(fd:outgoing,state:state);reader.leave()}
            try wait(sequence:nil,deadline:now+prepareTimeout)
        }catch{stop();throw error}
    }
    deinit{stop()}
    private var now:Double{ProcessInfo.processInfo.systemUptime}
    func installFailureHandler(_ handler:@escaping @Sendable(String)->Void){state.install(handler)}
    func note(_ pitch:Int,velocity:Int,on:Bool,isCurrent:@escaping @Sendable()->Bool)throws {
        operations.lock();defer{operations.unlock()}
        guard !stopped,!control.isCancelled else{throw CancellationError()}
        guard (0...127).contains(pitch),(0...127).contains(velocity),(!on || velocity>0) else{throw AuditionWorkerFiles.invalid()}
        if on {
            guard isCurrent() else{return}
            let token=UUID();tokens[pitch]=token
            let seq=try send(kind:.note,pitch:pitch,velocity:velocity,token:token,waitForAck:true)
            var released=false
            try wait(sequence:seq,deadline:now+noteTimeout){
                if !released && !isCurrent() {
                    released=true
                    _ = try self.send(kind:.release,pitch:pitch,token:token,waitForAck:false)
                    if self.tokens[pitch]==token{self.tokens[pitch]=nil}
                }
            }
        }else if let token=tokens.removeValue(forKey:pitch) {
            let seq=try send(kind:.release,pitch:pitch,token:token,waitForAck:true)
            try wait(sequence:seq,deadline:now+noteTimeout)
        }
    }
    private func send(kind:AuditionWorkerCommand.Kind,pitch:Int?=nil,velocity:Int?=nil,token:UUID?=nil,waitForAck:Bool)throws->UInt64 {
        guard sequence<UInt64.max else{throw AuditionWorkerFiles.invalid()};sequence+=1
        let command=AuditionWorkerCommand(session:state.session,sequence:sequence,kind:kind,token:token,pitch:pitch,velocity:velocity)
        var bytes=try JSONEncoder().encode(command);bytes.append(10)
        guard bytes.count<=AuditionWorkerFiles.maximumLineBytes else{throw AuditionWorkerFiles.invalid()}
        try state.expect(sequence,kind:kind == .stop ? .stopped:.ack,wait:waitForAck)
        let deadline=now+min(noteTimeout,0.5),fd=input.fileHandleForWriting.fileDescriptor
        var offset=0
        while offset<bytes.count {
            let count=bytes.withUnsafeBytes{Darwin.write(fd,$0.baseAddress!.advanced(by:offset),$0.count-offset)}
            if count>0{offset+=count;continue}
            if count<0 && errno==EINTR{continue}
            guard count<0,(errno==EAGAIN || errno==EWOULDBLOCK),now<deadline else{throw CirclrError("악기 미리 듣기 worker에 요청을 전달하지 못했습니다")}
            if control.isCancelled && kind != .stop{throw CancellationError()}
            Thread.sleep(forTimeInterval:0.005)
        }
        return sequence
    }
    private func wait(sequence:UInt64?,deadline:Double,ignoreCancellation:Bool=false,tick:()throws->Void = {})throws {
        while true {
            if !ignoreCancellation && control.isCancelled{throw CancellationError()}
            try state.check(sequence)
            if state.completed(sequence){return}
            guard now<deadline else{throw CirclrError(sequence==nil ? "악기 미리 듣기 준비 제한 시간을 넘었습니다":"악기 미리 듣기 응답 제한 시간을 넘었습니다")}
            try tick();Thread.sleep(forTimeInterval:0.005)
        }
    }
    func stop() {
        operations.lock();defer{operations.unlock()}
        guard !stopped else{return};stopped=true;state.beginClosing()
        if launched && process.isRunning {
            if let seq=try? send(kind:.stop,waitForAck:true){try? wait(sequence:seq,deadline:now+grace,ignoreCancellation:true)}
        }
        // EOF is independently observed by the child even during a blocked native call.
        try? input.fileHandleForWriting.close()
        if launched {
            let eofDeadline=now+grace
            while process.isRunning && now<eofDeadline{Thread.sleep(forTimeInterval:0.005)}
            if process.isRunning {
                _ = Darwin.kill(process.processIdentifier,SIGTERM)
                let deadline=now+grace
                while process.isRunning && now<deadline{Thread.sleep(forTimeInterval:0.005)}
                if process.isRunning{_ = Darwin.kill(process.processIdentifier,SIGKILL)}
            }
            process.waitUntilExit()
        }
        state.stopReader();reader.wait()
        try? input.fileHandleForReading.close();try? output.fileHandleForWriting.close();try? output.fileHandleForReading.close()
        process.terminationHandler=nil;tokens=[:]
        if ownsDirectory{try? FileManager.default.removeItem(at:directory)}
    }
    private static func read(fd:Int32,state:WorkerState) {
        var pending=Data(),bytes=[UInt8](repeating:0,count:4096)
        while !state.readerStopped {
            var descriptor=pollfd(fd:fd,events:Int16(POLLIN|POLLHUP|POLLERR),revents:0)
            let ready=Darwin.poll(&descriptor,1,50)
            if ready<0 && errno==EINTR{continue}
            if ready==0{continue}
            guard ready>0 else{state.fail("악기 미리 듣기 응답을 읽지 못했습니다");return}
            let count=bytes.withUnsafeMutableBytes{Darwin.read(fd,$0.baseAddress,$0.count)}
            if count<0 && (errno==EINTR || errno==EAGAIN){continue}
            guard count>0 else{state.fail("악기 미리 듣기 응답 연결이 닫혔습니다");return}
            pending.append(contentsOf:bytes.prefix(count))
            while let end=pending.firstIndex(of:10) {
                let line=Data(pending[..<end]);pending.removeSubrange(...end)
                guard line.count<=AuditionWorkerFiles.maximumLineBytes,let event=try? JSONDecoder().decode(AuditionWorkerEvent.self,from:line) else{state.fail("악기 미리 듣기 응답 형식이 올바르지 않습니다");return}
                state.accept(event)
            }
            if pending.count>AuditionWorkerFiles.maximumLineBytes{state.fail("악기 미리 듣기 응답이 너무 큽니다");return}
        }
    }
}

private final class WorkerState:@unchecked Sendable {
    let session:UUID
    private let lock=NSLock()
    private let report:AuditionDiagnosticReporter
    private var ready=false,closing=false,readerDone=false
    private var failure:String?
    private var handler:(@Sendable(String)->Void)?
    private var pending:[UInt64:(AuditionWorkerEvent.Kind,Bool)]=[:]
    private var acknowledgements:Set<UInt64>=[]
    init(session:UUID,report:@escaping AuditionDiagnosticReporter){self.session=session;self.report=report}
    func install(_ callback:@escaping @Sendable(String)->Void){lock.lock();handler=callback;let message=failure;lock.unlock();if let message{callback(message)}}
    func fail(_ message:String) {
        lock.lock();guard !closing,failure==nil else{lock.unlock();return};failure=message;let callback=handler;lock.unlock();callback?(message)
    }
    func beginClosing(){lock.lock();closing=true;handler=nil;lock.unlock()}
    func stopReader(){lock.lock();readerDone=true;lock.unlock()}
    var readerStopped:Bool{lock.lock();defer{lock.unlock()};return readerDone}
    func expect(_ sequence:UInt64,kind:AuditionWorkerEvent.Kind,wait:Bool)throws {
        lock.lock();defer{lock.unlock()};guard pending.count<256 else{throw AuditionWorkerFiles.invalid()};pending[sequence]=(kind,wait)
    }
    func check(_ sequence:UInt64?)throws{lock.lock();defer{lock.unlock()};if let failure{throw CirclrError(failure)}}
    func completed(_ sequence:UInt64?)->Bool{lock.lock();defer{lock.unlock()};if let sequence{return acknowledgements.remove(sequence) != nil};return ready}
    func accept(_ event:AuditionWorkerEvent) {
        lock.lock()
        guard event.version==1,event.session==session else{lock.unlock();fail("오래된 악기 미리 듣기 응답을 거절했습니다");return}
        switch event.kind {
        case .ready:
            guard !ready,event.sequence==0,Set(event.capabilities ?? []).isSuperset(of:["notes","token-release","diagnostics"]) else{lock.unlock();fail("중복된 악기 준비 응답입니다");return};ready=true;lock.unlock()
        case .ack,.stopped:
            guard let expected=pending.removeValue(forKey:event.sequence),expected.0==event.kind else{lock.unlock();fail("악기 미리 듣기 응답 순서가 올바르지 않습니다");return}
            if expected.1{acknowledgements.insert(event.sequence)};lock.unlock()
        case .trace:
            guard !ready,event.sequence==0,let stage=event.stage,let phase=event.phase,stage != .note,stage != .cleanup else{lock.unlock();fail("악기 미리 듣기 진단 응답이 올바르지 않습니다");return}
            lock.unlock();report(stage,phase)
        case .failed:lock.unlock();fail(String((event.message ?? "악기 미리 듣기 worker 오류").prefix(512)))
        }
    }
}
