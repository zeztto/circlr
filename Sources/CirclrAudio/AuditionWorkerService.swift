import Foundation
import Darwin

/// Persistent instrument lifetime lives here, never in the app's default audition path.
public enum AuditionWorkerService {
    public static func run(arguments:[String])->Never {
        guard arguments.count==4,arguments[0]=="--session",let session=UUID(uuidString:arguments[1]),arguments[2]=="--directory" else{exit(64)}
        signal(SIGPIPE,SIG_IGN)
        let request:AuditionWorkerRequest
        do {request=try AuditionWorkerFiles.read(in:URL(fileURLWithPath:arguments[3],isDirectory:true),session:session)}catch{exit(65)}
        let inbox=AuditionWorkerInbox(session:session),writer=Writer(session:session)
        DispatchQueue(label:"circlr.audition-worker.stdin").async {
            var pending=Data(),bytes=[UInt8](repeating:0,count:1024)
            while true {
                let count=bytes.withUnsafeMutableBytes{Darwin.read(STDIN_FILENO,$0.baseAddress,$0.count)}
                if count<0 && errno==EINTR{continue}
                // Parent EOF must end even a native initializer/deinitializer that never returns.
                guard count>0 else{inbox.control.cancel();_exit(count==0 ? 0:66)}
                pending.append(contentsOf:bytes.prefix(count))
                while let end=pending.firstIndex(of:10) {
                    let line=Data(pending[..<end]);pending.removeSubrange(...end)
                    guard line.count<=AuditionWorkerFiles.maximumLineBytes else{_exit(66)}
                    do {try inbox.accept(JSONDecoder().decode(AuditionWorkerCommand.self,from:line))}catch{_exit(66)}
                }
                if pending.count>AuditionWorkerFiles.maximumLineBytes{_exit(66)}
            }
        }
        Task { @MainActor in
            do {
                let backend=try await NativeAuditionBackend(target:request.target(),control:inbox.control,report:{stage,phase in
                    guard stage != .note,stage != .cleanup else{return}
                    writer.send(.init(session:session,kind:.trace,stage:stage,phase:phase))
                })
                writer.send(.init(session:session,kind:.ready,capabilities:["notes","token-release","diagnostics"]))
                var sounding:[Int:UUID]=[:]
                while true {
                    guard let command=inbox.pop() else{try await Task.sleep(for:.milliseconds(2));continue}
                    if command.kind == .stop {
                        backend.stop();writer.send(.init(session:session,kind:.stopped,sequence:command.sequence));exit(0)
                    }
                    let pitch=command.pitch!,token=command.token!
                    if command.kind == .note {
                        if sounding[pitch] != nil {try backend.note(pitch,velocity:0,on:false,isCurrent:{true});sounding[pitch]=nil}
                        if inbox.current(pitch:pitch,token:token) {
                            try backend.note(pitch,velocity:command.velocity!,on:true,isCurrent:{inbox.current(pitch:pitch,token:token)})
                            if inbox.current(pitch:pitch,token:token){sounding[pitch]=token}
                            else{try backend.note(pitch,velocity:0,on:false,isCurrent:{true})}
                        }
                    }else if sounding[pitch]==token {
                        try backend.note(pitch,velocity:0,on:false,isCurrent:{true});sounding[pitch]=nil
                    }
                    writer.send(.init(session:session,kind:.ack,sequence:command.sequence))
                }
            }catch{
                writer.send(.init(session:session,kind:.failed,message:String(error.localizedDescription.prefix(512))));exit(70)
            }
        }
        RunLoop.main.run();exit(70)
    }
    private final class Writer:@unchecked Sendable {
        let session:UUID
        private let lock=NSLock()
        init(session:UUID){self.session=session}
        func send(_ event:AuditionWorkerEvent) {
            lock.lock();defer{lock.unlock()}
            do {var bytes=try JSONEncoder().encode(event);guard bytes.count<=AuditionWorkerFiles.maximumLineBytes else{_exit(70)};bytes.append(10);try FileHandle.standardOutput.write(contentsOf:bytes)}catch{_exit(70)}
        }
    }
}
