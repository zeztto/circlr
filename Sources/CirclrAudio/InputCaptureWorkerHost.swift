import AVFAudio
import Darwin
import Foundation
import CirclrCore

protocol InterruptibleAudioCaptureBackend:AudioCaptureBackend {
    func cancel()
    func onDelayedReap(_ callback:@escaping @Sendable ()->Void)
    var reaped:Bool {get}
    var telemetry:InputCaptureTelemetry {get}
    func takePeak()->Float
}

struct InputCaptureTelemetry {
    var frames:UInt64=0,peak:Float=0
    var reachedLimit=false,interrupted=false
}

/// Parent-side session. The child is the only process that opens the input device.
/// `start` and `stop` run on CaptureAttempt's serial queue; `cancel` is safe off-queue.
final class InputCaptureWorkerBackend:InterruptibleAudioCaptureBackend,@unchecked Sendable {
    private let executable:URL?,temporaryRoot:URL,stopTimeout:Double,grace:Double
    private let reapProbe:@Sendable (pid_t)->pid_t
    private let beforePublishRename:(@Sendable ()->Void)?
    private let session=UUID(),lock=NSCondition()
    private var pid:pid_t?,stdin:Pipe?,stdout:Pipe?,stage:URL?,destination:URL?
    private var launched=false,cancelled=false,readerDone=false,readerFailure:String?
    private var startEvent:InputCaptureWorkerMessage?,finishEvent:InputCaptureWorkerMessage?
    private var initialFormat:CaptureFormat?,maximumFrames:Int64=0,maximumSeconds:Double=0,metric=InputCaptureTelemetry()
    private var childReaped=false,committed=false
    private var backgroundReaper:DispatchSourceTimer?,delayedReapCallback:(@Sendable ()->Void)?
    init(executable:URL?=Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("circlr-input-worker"),
         temporaryRoot:URL=FileManager.default.temporaryDirectory,stopTimeout:Double=5,grace:Double=0.25,
         reapProbe:@escaping @Sendable (pid_t)->pid_t={Darwin.waitpid($0,nil,WNOHANG)},
         beforePublishRename:(@Sendable ()->Void)?=nil) {
        self.executable=executable;self.temporaryRoot=temporaryRoot;self.stopTimeout=stopTimeout;self.grace=grace;self.reapProbe=reapProbe
        self.beforePublishRename=beforePublishRename
    }
    func onDelayedReap(_ callback:@escaping @Sendable ()->Void) {
        lock.lock();delayedReapCallback=callback;lock.unlock()
    }
    var reaped:Bool {lock.lock();defer{lock.unlock()};return !launched || childReaped}
    var childPID:Int32? {lock.lock();defer{lock.unlock()};return launched ? pid:nil}
    var telemetry:InputCaptureTelemetry {lock.lock();defer{lock.unlock()};return metric}
    func takePeak()->Float {lock.lock();defer{lock.unlock()};let value=metric.peak;metric.peak=0;return value}
    func cancel() {
        lock.lock();cancelled=true
        // This host is the only waitpid owner. Until it reaps the child, even
        // an exited child retains its PID as a zombie, so this cannot hit a
        // newly reused PID. The signal and reap state share this lock.
        if launched && !childReaped,let pid {_ = Darwin.kill(pid,SIGTERM)}
        lock.broadcast();lock.unlock()
    }
    private func failed(_ reason:String) {
        lock.lock();if readerFailure==nil{readerFailure=reason};lock.broadcast();lock.unlock()
    }
    private func accept(_ message:InputCaptureWorkerMessage) {
        lock.lock();defer{lock.unlock()}
        guard message.session==session,!cancelled,readerFailure==nil else{
            readerFailure="입력 worker 세션이 변경되었거나 취소되었습니다";lock.broadcast();return
        }
        switch message.kind {
        case .started:
            guard startEvent==nil,finishEvent==nil,
                  let format=try? InputCaptureWorkerWire.checkedFormat(message) else{
                readerFailure="입력 worker 시작 응답이 올바르지 않습니다";break
            }
            initialFormat=format
            maximumFrames=Int64(floor(maximumSeconds*format.sampleRate))
            startEvent=message
        case .progress:
            // A meter timer can race a finished write; a validated final CAF
            // wins and late meter data must never invalidate the take.
            if finishEvent != nil {break}
            guard startEvent != nil,let frames=message.frames,frames>=0,
                  frames>=Int64(clamping:metric.frames),frames<=maximumFrames,
                  let peak=message.peak,peak.isFinite,peak>=0,peak<=32,
                  let limit=message.reachedLimit,let interrupted=message.interrupted else{
                readerFailure="입력 worker 진행 응답이 올바르지 않습니다";break
            }
            metric.frames=UInt64(frames);metric.peak=max(metric.peak,peak)
            metric.reachedLimit=limit;metric.interrupted=interrupted
        case .finished:
            guard startEvent != nil,finishEvent==nil,let frames=message.frames,frames>=0,
                  frames>=Int64(clamping:metric.frames),frames<=maximumFrames else{
                readerFailure="입력 worker 완료 응답이 올바르지 않습니다";break
            }
            if frames>0 {
                guard let format=try? InputCaptureWorkerWire.checkedFormat(message),format==initialFormat else{
                    readerFailure="입력 worker 완료 형식이 변경되었습니다";break
                }
            }
            metric.frames=UInt64(frames);metric.reachedLimit=message.reachedLimit ?? metric.reachedLimit
            metric.interrupted=message.interrupted ?? metric.interrupted;finishEvent=message
        case .failed:
            guard let error=message.error,!error.isEmpty,error.utf8.count<=1024 else{
                readerFailure="입력 worker 오류 응답이 올바르지 않습니다";break
            }
            readerFailure=error
        case .start,.stop:readerFailure="입력 worker 응답 종류가 올바르지 않습니다"
        }
        lock.broadcast()
    }
    private func readResponses(_ fd:Int32) {
        var pending=Data(),bytes=[UInt8](repeating:0,count:1024)
        while true {
            let count=bytes.withUnsafeMutableBytes{Darwin.read(fd,$0.baseAddress,$0.count)}
            if count<0 && errno==EINTR{continue}
            if count<=0 {if count<0{failed("입력 worker 응답을 읽지 못했습니다")};break}
            pending.append(contentsOf:bytes.prefix(count))
            if pending.count>InputCaptureWorkerWire.maximumLineBytes{failed("입력 worker 응답이 너무 큽니다");break}
            while let end=pending.firstIndex(of:10) {
                let line=Data(pending[..<end]);pending.removeSubrange(...end)
                do {accept(try InputCaptureWorkerWire.decode(line))}
                catch {failed(error.localizedDescription);break}
            }
        }
        lock.lock();readerDone=true;if !pending.isEmpty && readerFailure==nil{readerFailure="입력 worker 응답이 잘렸습니다"};lock.broadcast();lock.unlock()
    }
    private func write(_ message:InputCaptureWorkerMessage,deadline:Double)throws {
        guard let fd=stdin?.fileHandleForWriting.fileDescriptor else{throw CirclrError("입력 worker 명령 연결이 없습니다")}
        let data=try InputCaptureWorkerWire.encode(message)
        var offset=0
        while offset<data.count {
            lock.lock();let stopped=cancelled;lock.unlock()
            guard !stopped else{throw CancellationError()}
            let n=data.withUnsafeBytes{Darwin.write(fd,$0.baseAddress!.advanced(by:offset),$0.count-offset)}
            if n>0{offset+=n;continue}
            if n<0 && errno==EINTR{continue}
            guard n<0,(errno==EAGAIN || errno==EWOULDBLOCK),ProcessInfo.processInfo.systemUptime<deadline else{
                throw CirclrError("입력 worker 명령을 전달하지 못했습니다")
            }
            Thread.sleep(forTimeInterval:0.005)
        }
    }
    private func wait(_ kind:InputCaptureWorkerMessage.Kind,deadline:Double)throws->InputCaptureWorkerMessage {
        lock.lock();defer{lock.unlock()}
        while true {
            if cancelled{throw CancellationError()}
            if let readerFailure{throw CirclrError(readerFailure)}
            if kind == .started,let startEvent{return startEvent}
            if kind == .finished,let finishEvent{return finishEvent}
            if readerDone{throw CirclrError("입력 worker가 응답 없이 종료되었습니다")}
            let remaining=deadline-ProcessInfo.processInfo.systemUptime
            guard remaining>0 else{throw CirclrError("입력 worker 응답 제한 시간을 넘었습니다")}
            _ = lock.wait(until:Date(timeIntervalSinceNow:min(remaining,0.05)))
        }
    }
    func start(to url:URL,maximumSeconds:Double,control:CaptureControl)throws->CaptureFormat {
        guard control.enabled else{throw CancellationError()}
        guard let executable,FileManager.default.isExecutableFile(atPath:executable.path) else{
            throw CirclrError("입력 녹음 helper를 찾을 수 없습니다. 앱 설치를 확인하세요")
        }
        guard maximumSeconds.isFinite,maximumSeconds>0,maximumSeconds<=86400 else{throw CirclrError("녹음 시간 범위를 확인하세요")}
        let directory=temporaryRoot.appendingPathComponent("circlr-input-"+session.uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        let input=Pipe(),output=Pipe()
        lock.lock();stage=directory;destination=url;stdin=input;stdout=output
        self.maximumSeconds=maximumSeconds
        lock.unlock()
        do {
            let inFD=input.fileHandleForWriting.fileDescriptor
            guard fcntl(inFD,F_SETNOSIGPIPE,1)==0,
                  fcntl(inFD,F_SETFL,fcntl(inFD,F_GETFL)|O_NONBLOCK)==0 else{
                throw CirclrError("입력 worker IPC를 준비하지 못했습니다")
            }
            let spawned=try Self.spawn(executable:executable,input:input,output:output,temporaryRoot:temporaryRoot)
            lock.lock();pid=spawned;launched=true
            if cancelled{_ = Darwin.kill(spawned,SIGTERM)}
            lock.unlock()
            try? input.fileHandleForReading.close();try? output.fileHandleForWriting.close()
            let outFD=output.fileHandleForReading.fileDescriptor
            DispatchQueue(label:"circlr.input-worker.reader."+session.uuidString).async {[self] in readResponses(outFD)}
            try write(InputCaptureWorkerMessage(session:session,kind:.start,directory:directory.path,maximumSeconds:maximumSeconds),deadline:ProcessInfo.processInfo.systemUptime+1)
            let event=try wait(.started,deadline:ProcessInfo.processInfo.systemUptime+min(60,max(10,maximumSeconds)))
            return try InputCaptureWorkerWire.checkedFormat(event)
        }catch {
            cancel();_ = try? cleanup()
            throw error
        }
    }
    private static func spawn(executable:URL,input:Pipe,output:Pipe,temporaryRoot:URL)throws->pid_t {
        var actions:posix_spawn_file_actions_t?=nil
        guard posix_spawn_file_actions_init(&actions)==0 else{throw CirclrError("입력 worker 프로세스 준비 실패")}
        defer{posix_spawn_file_actions_destroy(&actions)}
        var attributes:posix_spawnattr_t?=nil
        guard posix_spawnattr_init(&attributes)==0 else{throw CirclrError("입력 worker 프로세스 속성 준비 실패")}
        defer{posix_spawnattr_destroy(&attributes)}
        guard posix_spawnattr_setflags(&attributes,Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))==0 else{
            throw CirclrError("입력 worker 파일 설명자 격리 실패")
        }
        let inputRead=input.fileHandleForReading.fileDescriptor,inputWrite=input.fileHandleForWriting.fileDescriptor
        let outputRead=output.fileHandleForReading.fileDescriptor,outputWrite=output.fileHandleForWriting.fileDescriptor
        let null=Darwin.open("/dev/null",O_WRONLY)
        guard null>=0 else{throw CirclrError("입력 worker 진단 출력 준비 실패")}
        defer{Darwin.close(null)}
        for (from,to) in [(inputRead,STDIN_FILENO),(outputWrite,STDOUT_FILENO),(null,STDERR_FILENO)] {
            guard posix_spawn_file_actions_adddup2(&actions,from,to)==0 else{
                throw CirclrError("입력 worker IPC 연결 실패")
            }
        }
        for fd in [inputRead,inputWrite,outputRead,outputWrite,null] where fd>STDERR_FILENO {
            guard posix_spawn_file_actions_addclose(&actions,fd)==0 else{throw CirclrError("입력 worker IPC 정리 실패")}
        }
        let path=strdup(executable.path)
        guard let path else{throw CirclrError("입력 worker 경로 준비 실패")}
        defer{free(path)}
        var arguments:[UnsafeMutablePointer<CChar>?]=[path,nil]
        let tmp=strdup("TMPDIR="+temporaryRoot.path)
        guard let tmp else{throw CirclrError("입력 worker 임시 환경 준비 실패")}
        defer{free(tmp)}
        // The worker needs only the private temp root; do not inherit app tokens.
        var environment:[UnsafeMutablePointer<CChar>?]=[tmp,nil]
        var result:pid_t=0
        let status=posix_spawn(&result,path,&actions,&attributes,&arguments,&environment)
        guard status==0,result>0 else{throw CirclrError("입력 worker 실행 실패 (\(status))")}
        return result
    }
    func stop()throws->CapturedAudio? {
        lock.lock();let active=launched && !childReaped,wasCancelled=cancelled;lock.unlock()
        guard active else{_ = try? cleanup();return nil}
        if wasCancelled {
            lock.lock();let deferred=backgroundReaper != nil;lock.unlock()
            if deferred{throw CirclrError("입력 worker 종료 확인 전 재시도를 보류합니다")}
            try cleanup();return nil
        }
        do {
            let deadline=ProcessInfo.processInfo.systemUptime+stopTimeout
            try write(InputCaptureWorkerMessage(session:session,kind:.stop),deadline:deadline)
            let event=try wait(.finished,deadline:deadline)
            try cleanup(preserveTake:true)
            guard let frames=event.frames,frames>0 else{
                if let stage{try? FileManager.default.removeItem(at:stage)}
                return nil
            }
            guard let stage=stage,let destination=destination else{throw CirclrError("입력 worker 파일 경로가 없습니다")}
            let fileURL=stage.appendingPathComponent("take.caf")
            let attributes=try FileManager.default.attributesOfItem(atPath:fileURL.path)
            let fileBytes=(attributes[.size] as? NSNumber)?.int64Value ?? 0
            let formatFromMessage=try InputCaptureWorkerWire.checkedFormat(event)
            let maximumBytes=maximumFrames*Int64(formatFromMessage.channels)*4+1_048_576
            guard fileBytes>=4,fileBytes<=maximumBytes else{throw CirclrError("입력 worker CAF 크기가 올바르지 않습니다")}
            let handle=try FileHandle(forReadingFrom:fileURL)
            let magic=try handle.read(upToCount:4);try? handle.close()
            guard magic==Data([0x63,0x61,0x66,0x66]) else{throw CirclrError("입력 worker 결과가 CAF 파일이 아닙니다")}
            let file=try AVAudioFile(forReading:fileURL)
            let format=CaptureFormat(sampleRate:file.processingFormat.sampleRate,channels:file.processingFormat.channelCount)
            guard format == initialFormat,format == formatFromMessage,
                  file.length==frames,file.length<=maximumFrames,file.length>0 else{
                throw CirclrError("입력 worker CAF의 프레임 또는 형식이 일치하지 않습니다")
            }
            lock.lock();let stopped=cancelled;lock.unlock()
            guard !stopped else{throw CancellationError()}
            try publish(fileURL,to:destination)
            try? FileManager.default.removeItem(at:stage)
            return CapturedAudio(url:destination,format:format,frames:frames)
        }catch {
            cancel();_ = try? cleanup();throw error
        }
    }
    /// The child never sees the destination. A private sibling keeps the final
    /// rename on the same volume and RENAME_EXCL protects an existing take.
    private func publish(_ source:URL,to destination:URL)throws {
        let parent=destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at:parent,withIntermediateDirectories:true)
        let publishDirectory=parent.appendingPathComponent(".circlr-input-publish-"+session.uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:publishDirectory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        defer{try? FileManager.default.removeItem(at:publishDirectory)}
        let staged=publishDirectory.appendingPathComponent("take.caf")
        try FileManager.default.copyItem(at:source,to:staged)
        beforePublishRename?()
        let result=staged.path.withCString {from in
            destination.path.withCString {to in
                lock.lock();defer{lock.unlock()}
                guard !cancelled else{return Int32(-2)}
                let value=Darwin.renameatx_np(AT_FDCWD,from,AT_FDCWD,to,UInt32(RENAME_EXCL))
                if value==0{committed=true}
                return value
            }
        }
        if result == -2{throw CancellationError()}
        guard result==0 else{throw CirclrError(errno==EEXIST ? "녹음 대상 파일이 이미 있습니다":"녹음 take를 최종 위치에 게시하지 못했습니다")}
    }
    /// Runs only on the capture worker queue. No retry is allowed before this returns.
    @discardableResult private func cleanup(preserveTake:Bool=false)throws->Bool {
        try? stdin?.fileHandleForWriting.close()
        if launched && !reaped {
            let first=ProcessInfo.processInfo.systemUptime+grace
            while ProcessInfo.processInfo.systemUptime<first {if try pollReap(){break};Thread.sleep(forTimeInterval:0.005)}
            signal(SIGTERM)
            let second=ProcessInfo.processInfo.systemUptime+grace
            while ProcessInfo.processInfo.systemUptime<second {if try pollReap(){break};Thread.sleep(forTimeInterval:0.005)}
            signal(SIGKILL)
            let third=ProcessInfo.processInfo.systemUptime+1
            while ProcessInfo.processInfo.systemUptime<third {if try pollReap(){break};Thread.sleep(forTimeInterval:0.005)}
            guard try pollReap() else{
                scheduleBackgroundReap()
                throw CirclrError("입력 worker PID 종료 확인 실패 · 종료될 때까지 재시도를 보류합니다")
            }
        }
        if !preserveTake,let stage{try? FileManager.default.removeItem(at:stage)}
        return true
    }
    private func signal(_ number:Int32) {
        lock.lock();defer{lock.unlock()}
        if launched && !childReaped,let pid {_ = Darwin.kill(pid,number)}
    }
    private func pollReap()throws->Bool {
        lock.lock();defer{lock.unlock()}
        if childReaped{return true}
        guard launched,let pid else{return true}
        let result=reapProbe(pid)
        if result==pid {childReaped=true;return true}
        if result==0 || (result<0 && errno==EINTR){return false}
        throw CirclrError("입력 worker 종료 소유권 확인 실패 · 재시도를 보류합니다")
    }
    private func scheduleBackgroundReap() {
        lock.lock()
        guard backgroundReaper==nil,!childReaped else{lock.unlock();return}
        let timer=DispatchSource.makeTimerSource(queue:DispatchQueue(label:"circlr.input-worker.reap."+session.uuidString,qos:.utility))
        backgroundReaper=timer
        lock.unlock()
        timer.schedule(deadline:.now()+0.1,repeating:.milliseconds(100))
        // Intentionally retain the host until its owned PID is reaped even if
        // the window/AudioRecorder has gone away. Break this cycle on reap.
        timer.setEventHandler {[self] in
            guard (try? pollReap()) == true else{return}
            self.lock.lock()
            let callback=delayedReapCallback,stage=stage,ownedTimer=backgroundReaper
            backgroundReaper=nil;delayedReapCallback=nil
            self.lock.unlock()
            if let stage{try? FileManager.default.removeItem(at:stage)}
            ownedTimer?.setEventHandler {} // release the strong host capture
            ownedTimer?.cancel();callback?()
        }
        timer.resume()
    }
}
