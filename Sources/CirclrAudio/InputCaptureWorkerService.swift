import AVFAudio
import Darwin
import Foundation
import CirclrCore

/// One request per child. The native input engine exists only in this process.
public enum InputCaptureWorkerService {
    private static func privateDirectory(_ raw:String)throws->URL {
        let url=URL(fileURLWithPath:raw,isDirectory:true)
        let parent=url.deletingLastPathComponent().resolvingSymlinksInPath()
        let temporary=FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        guard url.lastPathComponent.hasPrefix("circlr-input-"),parent==temporary,
              url.standardizedFileURL.path==url.path else{throw CirclrError("입력 worker 임시 경로가 올바르지 않습니다")}
        var value=stat()
        guard lstat(url.path,&value)==0,(value.st_mode & S_IFMT)==S_IFDIR,
              (value.st_mode & 0o777)==0o700,value.st_uid==getuid() else{
            throw CirclrError("입력 worker 임시 디렉터리 권한이 올바르지 않습니다")
        }
        return url
    }
    private final class Session {
        let id:UUID,control:CaptureControl,backend=EngineCaptureBackend(),url:URL
        let lock=NSLock()
        var started=false,finished=false,peak:Float=0
        init(_ id:UUID,_ url:URL)throws {self.id=id;self.url=url;control=try CaptureControl()}
        func setStarted(){lock.lock();started=true;lock.unlock()}
        func canStop()->Bool{lock.lock();defer{lock.unlock()};return started && !finished}
        func setFinished(){lock.lock();finished=true;lock.unlock()}
    }
    private final class Output {
        let lock=NSLock()
        func send(_ message:InputCaptureWorkerMessage) {
            lock.lock();defer{lock.unlock()}
            guard let data=try? InputCaptureWorkerWire.encode(message) else{return}
            do {try FileHandle.standardOutput.write(contentsOf:data)}catch{_exit(2)}
        }
    }
    public static func run() -> Int32 {
        let output=Output(),queue=DispatchQueue(label:"circlr.input-worker.native")
        var session:Session?
        var pending=Data(),bytes=[UInt8](repeating:0,count:1024)
        while true {
            let count=bytes.withUnsafeMutableBytes {Darwin.read(STDIN_FILENO,$0.baseAddress,$0.count)}
            if count==0{return 0}
            if count<0 {if errno==EINTR{continue};return 2}
            pending.append(contentsOf:bytes.prefix(count))
            guard pending.count<=InputCaptureWorkerWire.maximumLineBytes else{return 2}
            guard let end=pending.firstIndex(of:10) else{continue}
            let line=Data(pending[..<end]);pending.removeSubrange(...end)
            guard pending.isEmpty,let message=try? InputCaptureWorkerWire.decode(line) else{return 2}
            if session == nil {
                guard message.kind == .start,let raw=message.directory,
                      let maximum=message.maximumSeconds,maximum.isFinite,maximum>0,maximum<=86400,
                      message.sampleRate == nil,message.frames == nil else{return 2}
                do {
                    let directory=try privateDirectory(raw)
                    let url=directory.appendingPathComponent("take.caf")
                    guard !FileManager.default.fileExists(atPath:url.path) else{return 2}
                    let current=try Session(message.session,url);session=current
                    queue.async {
                        do {
                            let format=try current.backend.start(to:url,maximumSeconds:maximum,control:current.control)
                            current.setStarted()
                            output.send(InputCaptureWorkerMessage(session:current.id,kind:.started,sampleRate:format.sampleRate,channels:format.channels))
                            let timer=DispatchSource.makeTimerSource(queue:DispatchQueue(label:"circlr.input-worker.meter"))
                            timer.schedule(deadline:.now()+0.1,repeating:.milliseconds(100))
                            timer.setEventHandler {
                                guard current.canStop() else{timer.cancel();return}
                                output.send(InputCaptureWorkerMessage(session:current.id,kind:.progress,frames:Int64(clamping:current.control.frames),peak:current.control.takePeak(),reachedLimit:current.control.reachedLimit,interrupted:current.control.interrupted))
                            }
                            timer.resume()
                        }catch{
                            current.control.disable();_ = try? current.backend.stop()
                            current.setFinished()
                            output.send(InputCaptureWorkerMessage(session:current.id,kind:.failed,error:error.localizedDescription))
                        }
                    }
                }catch{return 2}
            }else if let current=session,message.session==current.id,message.kind == .stop {
                current.control.disable()
                queue.async {
                    guard current.canStop() else{return}
                    do {
                        let result=try current.backend.stop()
                        current.setFinished()
                        output.send(InputCaptureWorkerMessage(session:current.id,kind:.finished,
                            sampleRate:result?.format.sampleRate,channels:result?.format.channels,
                            frames:result?.frames ?? 0,peak:current.control.takePeak(),
                            reachedLimit:current.control.reachedLimit,interrupted:current.control.interrupted))
                    }catch{
                        current.setFinished()
                        output.send(InputCaptureWorkerMessage(session:current.id,kind:.failed,error:error.localizedDescription))
                    }
                }
            }else{return 2}
        }
    }
}
