import Foundation
import Darwin

/// A fail-closed route for bundled MCP clients. A previous app's agent.sock is
/// never removed to repair a crash: users may choose a fresh .rXXXXXXXX socket.
struct AgentEndpointSelection:Codable,Equatable {
    let schema:String
    let endpoint:String
    let runID:String
    let bundleID:String

    init(endpoint:String,runID:String,bundleID:String) {
        schema="circlr-agent-endpoint-v1"
        self.endpoint=endpoint
        self.runID=runID
        self.bundleID=bundleID
    }

    static func current(in directory:URL)->AgentEndpointSelection? {
        var folder=stat()
        guard Darwin.lstat(directory.path,&folder)==0,
              folder.st_mode & mode_t(S_IFMT)==mode_t(S_IFDIR),folder.st_uid==getuid(),
              folder.st_mode & 0o077==0 else {return nil}
        let path=directory.appendingPathComponent("selected.json").path
        var before=stat()
        guard Darwin.lstat(path,&before)==0,
              before.st_mode & mode_t(S_IFMT)==mode_t(S_IFREG),before.st_uid==getuid(),
              before.st_mode & 0o777==0o600,before.st_size<=4096 else {return nil}
        let descriptor=Darwin.open(path,O_RDONLY|O_CLOEXEC|O_NOFOLLOW|O_NONBLOCK)
        guard descriptor>=0 else{return nil}
        defer {Darwin.close(descriptor)}
        var opened=stat()
        guard Darwin.fstat(descriptor,&opened)==0,opened.st_dev==before.st_dev,
              opened.st_ino==before.st_ino,
              opened.st_mode & mode_t(S_IFMT)==mode_t(S_IFREG),opened.st_uid==getuid(),
              opened.st_mode & 0o777==0o600,opened.st_size<=4096 else{return nil}
        var data=Data(),buffer=[UInt8](repeating:0,count:4097)
        while data.count<=4096 {
            let count=Darwin.read(descriptor,&buffer,buffer.count)
            guard count>=0 else{return nil}
            if count==0 {break}
            data.append(contentsOf:buffer.prefix(count))
        }
        let canonical=JSONEncoder();canonical.outputFormatting=[.sortedKeys]
        guard data.count<=4096,
              let raw=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
              Set(raw.keys)==Set(["schema","endpoint","runID","bundleID"]),
              let selected=try? JSONDecoder().decode(Self.self,from:data),
              selected.schema=="circlr-agent-endpoint-v1",
              (try? canonical.encode(selected))==data else{return nil}
        return selected
    }

    static func publish(_ selection:AgentEndpointSelection,in directory:URL) throws {
        let validAlternate=selection.endpoint.count==10 && selection.endpoint.hasPrefix(".r") &&
            selection.endpoint.dropFirst(2).allSatisfy{("0"..."9").contains(String($0)) || ("a"..."f").contains(String($0))}
        guard selection.schema=="circlr-agent-endpoint-v1",
              selection.endpoint=="agent.sock" || validAlternate,
              UUID(uuidString:selection.runID) != nil,
              !selection.bundleID.isEmpty else {
            throw NSError(domain:"CirclrAgentEndpoint",code:1,userInfo:[NSLocalizedDescriptionKey:"Agent 연결 선택 정보가 올바르지 않습니다"])
        }
        var folder=stat()
        guard Darwin.lstat(directory.path,&folder)==0,
              folder.st_mode & mode_t(S_IFMT)==mode_t(S_IFDIR),folder.st_uid==getuid(),
              folder.st_mode & 0o077==0 else {
            throw NSError(domain:"CirclrAgentEndpoint",code:2,userInfo:[NSLocalizedDescriptionKey:"Agent 폴더의 권한을 확인하세요"])
        }
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let data=try encoder.encode(selection)
        guard data.count<=4096 else {throw NSError(domain:"CirclrAgentEndpoint",code:3,userInfo:[NSLocalizedDescriptionKey:"Agent 연결 선택 정보가 너무 큽니다"])}
        let temporary=directory.appendingPathComponent(".s"+String(UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased().prefix(8))).path
        let destination=directory.appendingPathComponent("selected.json").path
        let descriptor=Darwin.open(temporary,O_WRONLY|O_CREAT|O_EXCL|O_CLOEXEC|O_NOFOLLOW,mode_t(0o600))
        guard descriptor>=0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
        var published=false
        defer {
            Darwin.close(descriptor)
            if !published {Darwin.unlink(temporary)}
        }
        try data.withUnsafeBytes { raw in
            guard let base=raw.baseAddress else {return}
            var offset=0
            while offset<raw.count {
                let written=Darwin.write(descriptor,base+offset,raw.count-offset)
                guard written>0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
                offset+=written
            }
        }
        guard fsync(descriptor)==0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
        guard Darwin.rename(temporary,destination)==0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
        published=true
    }
}
