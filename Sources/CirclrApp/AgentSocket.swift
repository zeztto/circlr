import Foundation
import Darwin

/// User-only local IPC. Each connection contains one UTF-8 JSON line and one reply.
final class AgentSocket {
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
    private let queue=DispatchQueue(label:"com.circlr.agent.ipc",qos:.utility)
    private var source:DispatchSourceRead?
    init(directory:URL,onRequest:@escaping(Data,@escaping(Data)->Void)->Void) throws {
        let fm=FileManager.default
        try fm.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let attrs=try fm.attributesOfItem(atPath:directory.path)
        guard (attrs[.ownerAccountID] as? NSNumber)?.uint32Value==getuid(),attrs[.type] as? FileAttributeType == .typeDirectory else {throw NSError(domain:"CirclrAgent",code:1,userInfo:[NSLocalizedDescriptionKey:"Agent 폴더의 소유자를 확인하세요"])}
        try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:directory.path)
        path=directory.appendingPathComponent("agent.sock").path
        var address=try Self.socketAddress(for:path)
        if try Self.socketIdentity(at:path) != nil {
            let probe=socket(AF_UNIX,SOCK_STREAM,0)
            guard probe>=0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
            let connected=withUnsafePointer(to:&address){$0.withMemoryRebound(to:sockaddr.self,capacity:1){Darwin.connect(probe,$0,socklen_t(MemoryLayout<sockaddr_un>.size))}}==0
            let connectionError=errno
            Darwin.close(probe)
            guard !connected else {throw NSError(domain:"CirclrAgent",code:4,userInfo:[NSLocalizedDescriptionKey:"이미 실행 중인 Agent 연결이 있습니다"])}
            // A live older process can have bound the path but not reached
            // listen() yet. Even ECONNREFUSED cannot prove it is stale.
            throw NSError(domain:"CirclrAgent",code:6,userInfo:[
                NSLocalizedDescriptionKey:"기존 Agent socket이 응답하지 않습니다. 이전 앱 종료 후 다시 연결합니다",
                NSUnderlyingErrorKey:NSError(domain:NSPOSIXErrorDomain,code:Int(connectionError))
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
        let watch=DispatchSource.makeReadSource(fileDescriptor:descriptor,queue:queue);source=watch
        watch.setEventHandler {
            let client=accept(descriptor,nil,nil);guard client>=0 else{return}
            var uid:uid_t=0,gid:gid_t=0
            guard getpeereid(client,&uid,&gid)==0,uid==getuid() else {Darwin.close(client);return}
            var timeout=timeval(tv_sec:3,tv_usec:0),one:Int32=1
            setsockopt(client,SOL_SOCKET,SO_RCVTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size));setsockopt(client,SOL_SOCKET,SO_SNDTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size));setsockopt(client,SOL_SOCKET,SO_NOSIGPIPE,&one,socklen_t(MemoryLayout<Int32>.size))
            var data=Data(),buffer=[UInt8](repeating:0,count:8192)
            while data.count<=8_388_608 {
                let count=Darwin.read(client,&buffer,buffer.count)
                if count<=0 {Darwin.close(client);return}
                data.append(contentsOf:buffer.prefix(count))
                guard data.count<=8_388_608 else {Darwin.close(client);return}
                if let newline=data.firstIndex(of:10) {
                    let request=Data(data[..<newline])
                    DispatchQueue.main.async {onRequest(request){response in
                        DispatchQueue.global(qos:.utility).async {
                            let packet=response+Data([10]);packet.withUnsafeBytes{raw in var offset=0;while offset<raw.count {let n=Darwin.write(client,raw.baseAddress!+offset,raw.count-offset);if n<=0{break};offset+=n}}
                            Darwin.close(client)
                        }
                    }}
                    return
                }
            }
            Darwin.close(client)
        }
        watch.setCancelHandler {Darwin.close(descriptor)};watch.resume()
    }
    deinit{
        source?.cancel()
        Self.unlinkOwnedSocket(at:path,identity:boundIdentity)
    }
}
