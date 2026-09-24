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
        let id:UUID,control:CaptureControl,backend:AudioCaptureBackend,url:URL
        let lock=NSLock()
        var started=false,finished=false,peak:Float=0
        init(_ id:UUID,_ url:URL,selection:InputDeviceSelection)throws {
            self.id=id;self.url=url;control=try CaptureControl()
            switch selection {
            case .systemDefault:backend=EngineCaptureBackend()
            case .deviceUID:backend=SelectedInputCaptureBackend(selection:selection)
            }
        }
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
                if message.kind == .catalog {
                    guard message.directory == nil,message.maximumSeconds == nil,message.deviceUID == nil,
                          message.device == nil,message.sampleRate == nil,message.channels == nil,
                          message.frames == nil,message.peak == nil,message.error == nil else{return 2}
                    do {
                        let devices=try InputDeviceCatalog.available()
                        guard devices.count<=128 else{return 2}
                        for device in devices {
                            try InputDeviceSelection.deviceUID(device.uid).validate()
                            output.send(InputCaptureWorkerMessage(session:message.session,kind:.catalogDevice,device:device))
                        }
                        output.send(InputCaptureWorkerMessage(session:message.session,kind:.catalogFinished))
                        return 0
                    }catch {
                        output.send(InputCaptureWorkerMessage(session:message.session,kind:.failed,error:error.localizedDescription))
                        return 2
                    }
                }
                guard message.kind == .start,let raw=message.directory,
                      let maximum=message.maximumSeconds,maximum.isFinite,maximum>0,maximum<=86400,
                      message.device == nil,message.sampleRate == nil,message.channels == nil,
                      message.frames == nil,message.peak == nil,message.error == nil else{return 2}
                do {
                    let selection=try InputCaptureWorkerWire.checkedSelection(message)
                    let directory=try privateDirectory(raw)
                    let url=directory.appendingPathComponent("take.caf")
                    guard !FileManager.default.fileExists(atPath:url.path) else{return 2}
                    let current=try Session(message.session,url,selection:selection);session=current
                    queue.async {
                        do {
                            let format=try current.backend.start(to:url,maximumSeconds:maximum,control:current.control)
                            current.setStarted()
                            let confirmedUID:String?
                            if case .deviceUID(let uid)=selection {confirmedUID=uid} else{confirmedUID=nil}
                            output.send(InputCaptureWorkerMessage(session:current.id,kind:.started,
                                deviceUID:confirmedUID,sampleRate:format.sampleRate,channels:format.channels))
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
                    }catch let recovery as RecoverableSelectedInputError {
                        current.setFinished()
                        let reason=recovery.reason.utf8.count<=1024 && !recovery.reason.isEmpty
                            ? recovery.reason : "입력 장치가 녹음 중 중단되었습니다"
                        output.send(InputCaptureWorkerMessage(session:current.id,kind:.finished,
                            sampleRate:recovery.audio.format.sampleRate,channels:recovery.audio.format.channels,
                            frames:recovery.audio.frames,interrupted:true,error:reason))
                    }catch{
                        current.setFinished()
                        output.send(InputCaptureWorkerMessage(session:current.id,kind:.failed,error:error.localizedDescription))
                    }
                }
            }else{return 2}
        }
    }
}
