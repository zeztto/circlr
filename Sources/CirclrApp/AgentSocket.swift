import Foundation
import Darwin

/// User-only local IPC. Each connection contains one UTF-8 JSON line and one reply.
final class AgentSocket {
    private final class Client {
        let fd:Int32
        var bytes=Data()
        var reader:DispatchSourceRead?
        var deadline:DispatchSourceTimer?
        init(fd:Int32) {self.fd=fd}
    }
    /// Event handlers retain only this state, never the published socket
    /// owner. STOP can therefore unlink the path immediately, even while an
    /// accepted request or a cancellation handler is being drained.
    private final class ListenerState {
        private final class Reply {
            let id:Int
            let fd:Int32
            let requestByteCount:Int
            var request:Data?
            var responseByteCount=0
            var writing=false
            var deadline:DispatchSourceTimer?
            weak var state:ListenerState?
            init(id:Int,fd:Int32,request:Data,state:ListenerState) {
                self.id=id;self.fd=fd;self.request=request
                requestByteCount=request.count;self.state=state
            }
        }
        private static let maximumActiveRequests=32
        static let hardBufferedByteLimit=32*1_048_576
        private static let maximumReplyBytes=8_388_608
        let fd:Int32
        let queue=DispatchQueue(label:"com.circlr.agent.ipc",qos:.utility)
        private let queueKey=DispatchSpecificKey<Bool>()
        private var clients=[Int:Client]()
        private var replies=[Int:Reply]()
        private var nextClientID=0
        private var bufferedBytes=0
        // Accepted replies survive socket owner teardown just long enough to
        // return the STOP/stale result or reach their finite deadline.
        private var acceptedReplyLifetime:ListenerState?
        private var source:DispatchSourceRead?
        let maximumRequestBytes:Int
        let maximumBufferedBytes:Int
        let preflight:((Data)->Bool)?
        let onRequest:(Data,@escaping(Data)->Void)->Void
        let replyTimeout:TimeInterval

        init(fd:Int32,maximumRequestBytes:Int,maximumBufferedBytes:Int,
             replyTimeout:TimeInterval,
             preflight:((Data)->Bool)?,
             onRequest:@escaping(Data,@escaping(Data)->Void)->Void) {
            self.fd=fd
            self.maximumRequestBytes=maximumRequestBytes
            self.maximumBufferedBytes=maximumBufferedBytes
            self.preflight=preflight
            self.onRequest=onRequest
            self.replyTimeout=replyTimeout
            queue.setSpecific(key:queueKey,value:true)
            let watch=DispatchSource.makeReadSource(fileDescriptor:fd,queue:queue)
            source=watch
            watch.setEventHandler {[weak self] in self?.acceptClient()}
            watch.setCancelHandler {Darwin.close(fd)}
            watch.resume()
        }

        /// The listening queue never waits on a peer. Each accepted
        /// descriptor has its own read source and a 3-second deadline.
        private func acceptClient() {
            let clientFD=accept(fd,nil,nil)
            guard clientFD>=0 else{return}
            var uid:uid_t=0,gid:gid_t=0
            guard getpeereid(clientFD,&uid,&gid)==0,uid==getuid(),
                  clients.count+replies.count<Self.maximumActiveRequests else {
                Darwin.close(clientFD);return
            }
            let flags=fcntl(clientFD,F_GETFL,0)
            guard flags>=0,fcntl(clientFD,F_SETFL,flags|O_NONBLOCK)==0 else {
                Darwin.close(clientFD);return
            }
            var timeout=timeval(tv_sec:3,tv_usec:0),one:Int32=1
            setsockopt(clientFD,SOL_SOCKET,SO_SNDTIMEO,&timeout,
                       socklen_t(MemoryLayout<timeval>.size))
            setsockopt(clientFD,SOL_SOCKET,SO_NOSIGPIPE,&one,
                       socklen_t(MemoryLayout<Int32>.size))
            let id=nextClientID;nextClientID &+= 1
            let client=Client(fd:clientFD)
            clients[id]=client
            let reader=DispatchSource.makeReadSource(fileDescriptor:clientFD,queue:queue)
            client.reader=reader
            reader.setEventHandler {[weak self,weak client] in
                guard let self,let client else{return}
                self.receive(client,id:id)
            }
            // The cancel handler is the sole owner of the original FD. A
            // complete request dup()s it before cancellation for its reply.
            reader.setCancelHandler {Darwin.close(clientFD)}
            let deadline=DispatchSource.makeTimerSource(queue:queue)
            client.deadline=deadline
            deadline.schedule(deadline:.now()+3)
            deadline.setEventHandler {[weak self,weak client] in
                guard let self,let client else{return}
                self.closeClient(client,id:id)
            }
            reader.resume();deadline.resume()
        }

        private func receive(_ client:Client,id:Int) {
            guard clients[id] === client else{return}
            var buffer=[UInt8](repeating:0,count:8192)
            while true {
                let permitted=min(buffer.count,maximumRequestBytes-client.bytes.count+1)
                guard permitted>0 else {closeClient(client,id:id);return}
                let count=Darwin.read(client.fd,&buffer,permitted)
                if count<0 {
                    if errno==EINTR {continue}
                    if errno==EAGAIN || errno==EWOULDBLOCK {return}
                    closeClient(client,id:id);return
                }
                guard count>0 else {closeClient(client,id:id);return}
                guard bufferedBytes+count<=maximumBufferedBytes else {
                    closeClient(client,id:id);return
                }
                client.bytes.append(contentsOf:buffer.prefix(count))
                bufferedBytes+=count
                guard client.bytes.count<=maximumRequestBytes else {
                    closeClient(client,id:id);return
                }
                if let newline=client.bytes.firstIndex(of:10) {
                    let request=Data(client.bytes[..<newline])
                    // A rejecting preflight never reaches the UI/main queue.
                    guard preflight?(request) ?? true else {
                        closeClient(client,id:id);return
                    }
                    let replyFD=dup(client.fd)
                    closeClient(client,id:id)
                    guard replyFD>=0 else{return}
                    guard bufferedBytes+request.count<=maximumBufferedBytes else {
                        Darwin.close(replyFD);return
                    }
                    let reply=Reply(id:id,fd:replyFD,request:request,state:self)
                    replies[id]=reply
                    bufferedBytes+=request.count
                    acceptedReplyLifetime=self
                    let deadline=DispatchSource.makeTimerSource(queue:queue)
                    reply.deadline=deadline
                    deadline.schedule(deadline:.now()+replyTimeout)
                    deadline.setEventHandler {[weak self,weak reply] in
                        guard let self,let reply else{return}
                        self.expireReply(reply)
                    }
                    deadline.resume()
                    // The MainActor closure captures only the small Reply
                    // handle. Expiry clears request bytes even if the main
                    // queue remains blocked by unrelated UI work.
                    DispatchQueue.main.async {[weak reply] in
                        guard let reply,let state=reply.state,
                              let request=state.takeRequest(reply) else{return}
                        let handler=state.onRequest
                        handler(request) {[weak reply] response in
                            guard let reply,let state=reply.state else{return}
                            state.enqueueResponse(reply,response)
                        }
                    }
                    return
                }
            }
        }

        private func closeClient(_ client:Client,id:Int) {
            guard clients[id] === client else{return}
            clients.removeValue(forKey:id)
            bufferedBytes-=client.bytes.count
            client.deadline?.cancel()
            client.reader?.cancel()
        }

        private func takeRequest(_ reply:Reply) -> Data? {
            let take={ () -> Data? in
                guard self.replies[reply.id] === reply else{return nil}
                let request=reply.request
                reply.request=nil
                return request
            }
            return DispatchQueue.getSpecific(key:queueKey)==true ? take() : queue.sync(execute:take)
        }

        private func enqueueResponse(_ reply:Reply,_ response:Data) {
            let admit={
                guard self.replies[reply.id] === reply,!reply.writing else{return}
                let overflow=Data(#"{"ok":false,"error":"response_too_large"}"#.utf8)
                let payload:Data
                if response.count<=Self.maximumReplyBytes,
                   self.bufferedBytes+response.count<=self.maximumBufferedBytes {
                    payload=response
                } else if self.bufferedBytes+overflow.count<=self.maximumBufferedBytes {
                    payload=overflow
                } else {
                    self.finishReply(reply);return
                }
                reply.writing=true
                reply.responseByteCount=payload.count
                self.bufferedBytes+=payload.count
                DispatchQueue.global(qos:.utility).async {[weak self,weak reply] in
                    guard let reply else{return}
                    // dup shares flags with the cancelled reader. Its timeout
                    // bounds a peer that stops reading the reply.
                    let flags=fcntl(reply.fd,F_GETFL,0)
                    if flags>=0 {_=fcntl(reply.fd,F_SETFL,flags & ~O_NONBLOCK)}
                    var fullySent=true
                    payload.withUnsafeBytes {raw in
                        var offset=0
                        while offset<raw.count {
                            let n=Darwin.write(reply.fd,raw.baseAddress!+offset,raw.count-offset)
                            if n<0 && errno==EINTR {continue}
                            if n<=0 {fullySent=false;break}
                            offset+=n
                        }
                    }
                    if fullySent {
                        var newline:UInt8=10
                        _=Darwin.write(reply.fd,&newline,1)
                    }
                    self?.queue.async {[weak self,weak reply] in
                        guard let self,let reply else{return}
                        self.finishReply(reply)
                    }
                }
            }
            if DispatchQueue.getSpecific(key:queueKey)==true {admit()}
            else {queue.sync(execute:admit)}
        }

        private func expireReply(_ reply:Reply) {
            guard replies[reply.id] === reply else{return}
            if reply.writing {
                // The writer owns the active syscall; shutdown wakes it, and
                // its completion closes the FD exactly once on our queue.
                _=Darwin.shutdown(reply.fd,SHUT_RDWR)
            } else {
                finishReply(reply)
            }
        }

        private func finishReply(_ reply:Reply) {
            guard replies[reply.id] === reply else{return}
            replies.removeValue(forKey:reply.id)
            bufferedBytes-=reply.requestByteCount+reply.responseByteCount
            reply.deadline?.cancel()
            reply.request=nil
            reply.state=nil
            Darwin.close(reply.fd)
            if replies.isEmpty {acceptedReplyLifetime=nil}
        }

        func shutdown() {
            let teardown={
                self.source?.cancel()
                for (id,client) in Array(self.clients) {self.closeClient(client,id:id)}
            }
            if DispatchQueue.getSpecific(key:queueKey)==true {teardown()}
            else {queue.sync(execute:teardown)}
        }
    }
    private struct SocketIdentity:Equatable {
        let device:dev_t
        let inode:ino_t
        let owner:uid_t
    }
    private static func socketIdentity(at path:String) throws -> SocketIdentity? {
        var info=stat()
        guard Darwin.lstat(path,&info)==0 else {
            if errno==ENOENT{return nil}
            throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))
        }
        guard info.st_mode & mode_t(S_IFMT)==mode_t(S_IFSOCK),info.st_uid==getuid() else {
            throw NSError(domain:"CirclrAgent",code:3,userInfo:[NSLocalizedDescriptionKey:"Agent socket 위치에 다른 파일이 있습니다"])
        }
        return SocketIdentity(device:info.st_dev,inode:info.st_ino,owner:info.st_uid)
    }
    private static func socketAddress(for path:String) throws -> sockaddr_un {
        var address=sockaddr_un();address.sun_family=sa_family_t(AF_UNIX);address.sun_len=UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes=Array(path.utf8)+[0]
        guard bytes.count<=MemoryLayout.size(ofValue:address.sun_path) else {
            throw NSError(domain:"CirclrAgent",code:2,userInfo:[NSLocalizedDescriptionKey:"Agent socket 경로가 너무 깁니다"])
        }
        withUnsafeMutableBytes(of:&address.sun_path){$0.copyBytes(from:bytes)}
        return address
    }
    private static func unlinkOwnedSocket(at path:String,identity:SocketIdentity) {
        if let current=try? socketIdentity(at:path),current==identity {Darwin.unlink(path)}
    }
    private let fd:Int32
    private let boundIdentity:SocketIdentity
    let path:String
    var ownsPublishedPath:Bool { (try? Self.socketIdentity(at:path)) == boundIdentity }
    private var state:ListenerState?
    init(directory:URL,name:String="agent.sock",maximumRequestBytes:Int=8_388_608,
         maximumBufferedBytes:Int=32*1_048_576,
         replyTimeout:TimeInterval=15,
         preflight:(@Sendable (Data)->Bool)?=nil,
         onRequest:@escaping(Data,@escaping(Data)->Void)->Void) throws {
        guard (1...8_388_608).contains(maximumRequestBytes) else {
            throw NSError(domain:"CirclrAgent",code:8,userInfo:[NSLocalizedDescriptionKey:"Agent 요청 크기 제한이 올바르지 않습니다"])
        }
        guard (maximumRequestBytes...ListenerState.hardBufferedByteLimit)
            .contains(maximumBufferedBytes) else {
            throw NSError(domain:"CirclrAgent",code:8,userInfo:[NSLocalizedDescriptionKey:"Agent 메모리 제한이 올바르지 않습니다"])
        }
        guard (0.1...60).contains(replyTimeout) else {
            throw NSError(domain:"CirclrAgent",code:8,userInfo:[NSLocalizedDescriptionKey:"Agent 응답 시간 제한이 올바르지 않습니다"])
        }
        let privateName=name.count==10 && (name.hasPrefix(".r") || name.hasPrefix(".t")) && name.dropFirst(2).allSatisfy{("0"..."9").contains(String($0)) || ("a"..."f").contains(String($0))}
        guard name=="agent.sock" || privateName else {
            throw NSError(domain:"CirclrAgent",code:7,userInfo:[NSLocalizedDescriptionKey:"Agent 연결 이름이 올바르지 않습니다"])
        }
        let fm=FileManager.default
        try fm.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        var directoryInfo=stat()
        guard Darwin.lstat(directory.path,&directoryInfo)==0,
              directoryInfo.st_mode & mode_t(S_IFMT)==mode_t(S_IFDIR),directoryInfo.st_uid==getuid() else {
            throw NSError(domain:"CirclrAgent",code:1,userInfo:[NSLocalizedDescriptionKey:"Agent 폴더의 소유자를 확인하세요"])
        }
        try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:directory.path)
        path=directory.appendingPathComponent(name).path
        _=try Self.socketAddress(for:path)
        if try Self.socketIdentity(at:path) != nil {
            // A live older process can be between bind() and listen(). A
            // connect probe would block the UI and cannot prove staleness.
            throw NSError(domain:"CirclrAgent",code:6,userInfo:[
                NSLocalizedDescriptionKey:"기존 Agent 연결 경로가 있습니다. 다른 앱을 확인하거나 이 앱에 새 연결을 선택하세요"
            ])
        }
        let descriptor=socket(AF_UNIX,SOCK_STREAM,0);fd=descriptor
        guard descriptor>=0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
        // Publish only a listening socket. The old app can bind the public
        // path at any time, so a prior lstat is not sufficient ownership proof.
        // The private basename is the same length as agent.sock to preserve
        // the existing Unix socket path-length limit.
        var privatePath:String?
        for _ in 0..<8 {
            let candidate=directory.appendingPathComponent(".a"+String(UUID().uuidString.replacingOccurrences(of:"-",with:"").prefix(8))).path
            var candidateAddress:sockaddr_un
            do {candidateAddress=try Self.socketAddress(for:candidate)}
            catch {Darwin.close(descriptor);throw error}
            let bound=withUnsafePointer(to:&candidateAddress){$0.withMemoryRebound(to:sockaddr.self,capacity:1){Darwin.bind(descriptor,$0,socklen_t(MemoryLayout<sockaddr_un>.size))}}
            if bound==0 {privatePath=candidate;break}
            let failure=errno
            guard failure==EADDRINUSE else {Darwin.close(descriptor);throw NSError(domain:NSPOSIXErrorDomain,code:Int(failure))}
        }
        guard let privatePath else {Darwin.close(descriptor);throw NSError(domain:"CirclrAgent",code:5,userInfo:[NSLocalizedDescriptionKey:"Agent 임시 socket 위치를 확보하지 못했습니다"])}
        guard let privateID=try? Self.socketIdentity(at:privatePath) else {
            Darwin.close(descriptor)
            throw NSError(domain:"CirclrAgent",code:5,userInfo:[NSLocalizedDescriptionKey:"Agent 임시 socket 위치가 변경되었습니다"])
        }
        guard listen(descriptor,8)==0,chmod(privatePath,0o600)==0 else {
            let failure=errno;Darwin.close(descriptor);Self.unlinkOwnedSocket(at:privatePath,identity:privateID)
            throw NSError(domain:NSPOSIXErrorDomain,code:Int(failure))
        }
        // An event source must never be able to block teardown in accept().
        let listenerFlags=fcntl(descriptor,F_GETFL,0)
        guard listenerFlags>=0,
              fcntl(descriptor,F_SETFL,listenerFlags|O_NONBLOCK)==0 else {
            let failure=errno;Darwin.close(descriptor);Self.unlinkOwnedSocket(at:privatePath,identity:privateID)
            throw NSError(domain:NSPOSIXErrorDomain,code:Int(failure))
        }
        // RENAME_EXCL is atomic: an older instance that won the public path
        // cannot be overwritten, even if it has not entered listen() yet.
        guard renamex_np(privatePath,path,UInt32(RENAME_EXCL))==0 else {
            let failure=errno;Darwin.close(descriptor);Self.unlinkOwnedSocket(at:privatePath,identity:privateID)
            throw NSError(domain:NSPOSIXErrorDomain,code:Int(failure))
        }
        guard let publicID=try? Self.socketIdentity(at:path),publicID==privateID else {
            Darwin.close(descriptor)
            throw NSError(domain:"CirclrAgent",code:5,userInfo:[NSLocalizedDescriptionKey:"Agent socket 경로가 게시 중 변경되었습니다"])
        }
        boundIdentity=privateID
        state=ListenerState(fd:descriptor,maximumRequestBytes:maximumRequestBytes,
                            maximumBufferedBytes:maximumBufferedBytes,
                            replyTimeout:replyTimeout,
                            preflight:preflight,onRequest:onRequest)
    }
    deinit{
        state?.shutdown()
        Self.unlinkOwnedSocket(at:path,identity:boundIdentity)
    }
}
