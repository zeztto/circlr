import Foundation
import Darwin

/// User-only local IPC. Each connection contains one UTF-8 JSON line and one reply.
final class AgentSocket {
    private let fd:Int32
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
        var address=sockaddr_un();address.sun_family=sa_family_t(AF_UNIX);address.sun_len=UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes=Array(path.utf8)+[0]
        guard bytes.count<=MemoryLayout.size(ofValue:address.sun_path) else {throw NSError(domain:"CirclrAgent",code:2,userInfo:[NSLocalizedDescriptionKey:"Agent socket 경로가 너무 깁니다"])}
        withUnsafeMutableBytes(of:&address.sun_path){$0.copyBytes(from:bytes)}
        if fm.fileExists(atPath:path) {
            let old=try fm.attributesOfItem(atPath:path)
            guard old[.type] as? FileAttributeType == .typeSocket,(old[.ownerAccountID] as? NSNumber)?.uint32Value==getuid() else {throw NSError(domain:"CirclrAgent",code:3,userInfo:[NSLocalizedDescriptionKey:"Agent socket 위치에 다른 파일이 있습니다"])}
            let probe=socket(AF_UNIX,SOCK_STREAM,0)
            let connected=withUnsafePointer(to:&address){$0.withMemoryRebound(to:sockaddr.self,capacity:1){Darwin.connect(probe,$0,socklen_t(MemoryLayout<sockaddr_un>.size))}}==0
            Darwin.close(probe)
            guard !connected else {throw NSError(domain:"CirclrAgent",code:4,userInfo:[NSLocalizedDescriptionKey:"이미 실행 중인 Agent 연결이 있습니다"])}
            try fm.removeItem(atPath:path)
        }
        let descriptor=socket(AF_UNIX,SOCK_STREAM,0);fd=descriptor
        guard descriptor>=0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
        let bound=withUnsafePointer(to:&address){$0.withMemoryRebound(to:sockaddr.self,capacity:1){Darwin.bind(descriptor,$0,socklen_t(MemoryLayout<sockaddr_un>.size))}}
        guard bound==0,listen(descriptor,8)==0 else {Darwin.close(descriptor);throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
        guard chmod(path,0o600)==0 else {let failure=errno;Darwin.close(descriptor);unlink(path);throw NSError(domain:NSPOSIXErrorDomain,code:Int(failure))}
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
    deinit{source?.cancel();unlink(path)}
}
