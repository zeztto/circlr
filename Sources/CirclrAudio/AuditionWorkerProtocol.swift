import Foundation
import Darwin
import CirclrCore

struct AuditionWorkerRequest:Codable {
    var version=1
    let session:UUID
    let instrument:Instrument
    let assets:[Asset]
    init(session:UUID,target:AuditionTarget)throws {
        self.session=session;instrument=target.instrument
        let ids=Set(instrument.kind == .sampler ? (instrument.sample.map{[$0.assetID]+($0.zones ?? []).map(\.assetID)} ?? []):[])
        assets=try ids.sorted().map{id in
            guard var asset=target.project.assets.first(where:{$0.id==id}) else{throw CirclrError("샘플 원본을 찾을 수 없습니다")}
            asset.path=try ProjectStore.assetURL(asset,root:target.root).path;return asset
        }
    }
    func target()->AuditionTarget {var project=Project();project.assets=assets;return AuditionTarget(key:session.uuidString,instrument:instrument,project:project,root:nil)}
}
struct AuditionWorkerCommand:Codable {
    enum Kind:String,Codable {case note,release,stop}
    var version=1
    let session:UUID
    let sequence:UInt64
    let kind:Kind
    var token:UUID?
    var pitch:Int?
    var velocity:Int?
}
struct AuditionWorkerEvent:Codable {
    enum Kind:String,Codable {case ready,ack,trace,failed,stopped}
    var version=1
    let session:UUID
    let kind:Kind
    var sequence:UInt64=0
    var stage:AuditionTraceEvent.Stage?
    var phase:AuditionTraceEvent.Phase?
    var message:String?
    var capabilities:[String]?
}
enum AuditionWorkerFiles {
    static let maximumRequestBytes=12*1024*1024
    static let maximumLineBytes=4096
    static func validate(_ request:AuditionWorkerRequest)throws {
        guard request.version==1,request.assets.count<=128,
              (0...127).contains(request.instrument.program),
              (request.instrument.plugin?.state?.count ?? 0)<=8*1024*1024 else{throw invalid()}
        if request.instrument.kind == .audioUnit {
            guard let plugin=request.instrument.plugin,plugin.type==0x61756d75,plugin.name.utf8.count<=1024 else{throw invalid()}
            if let data=plugin.state {guard (try? PropertyListSerialization.propertyList(from:data,format:nil)) is [String:Any] else{throw invalid()}}
        }
        if request.instrument.kind == .sampler {
            guard let sample=request.instrument.sample,(0...127).contains(sample.rootPitch),(sample.zones?.count ?? 0)<=128 else{throw invalid()}
            let ids=Set([sample.assetID]+(sample.zones ?? []).map(\.assetID))
            guard Set(request.assets.map(\.id))==ids,request.assets.count==ids.count,
                  (sample.zones ?? []).allSatisfy({(0...127).contains($0.pitch)}) else{throw invalid()}
        }else if !request.assets.isEmpty{throw invalid()}
        for asset in request.assets {
            guard asset.path.hasPrefix("/"),!asset.path.contains("\0"),asset.path.utf8.count<=4096,
                  asset.duration.isFinite,asset.duration>=0,asset.sampleRate.isFinite,asset.sampleRate>0 else{throw invalid()}
        }
    }
    static func invalid()->CirclrError {CirclrError("악기 미리 듣기 worker 요청 또는 응답을 확인하세요")}
    static func write(_ request:AuditionWorkerRequest,in directory:URL)throws {
        try AUEffectWorkerFiles.validateDirectory(directory);try validate(request)
        let bytes=try JSONEncoder().encode(request);guard bytes.count<=maximumRequestBytes else{throw invalid()}
        let fd=open(directory.appendingPathComponent("request.json").path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,mode_t(0o600))
        guard fd>=0 else{throw invalid()};let file=FileHandle(fileDescriptor:fd,closeOnDealloc:true);defer{try? file.close()}
        try file.write(contentsOf:bytes)
    }
    static func read(in directory:URL,session:UUID)throws->AuditionWorkerRequest {
        try AUEffectWorkerFiles.validateDirectory(directory)
        let fd=open(directory.appendingPathComponent("request.json").path,O_RDONLY|O_NOFOLLOW|O_NONBLOCK)
        guard fd>=0 else{throw invalid()};let file=FileHandle(fileDescriptor:fd,closeOnDealloc:true);defer{try? file.close()}
        var info=stat()
        guard fstat(fd,&info)==0,info.st_uid==geteuid(),info.st_mode&S_IFMT==S_IFREG,info.st_mode&0o077==0,info.st_nlink==1,
              info.st_size>=0,info.st_size<=maximumRequestBytes else{throw invalid()}
        let bytes=try file.read(upToCount:maximumRequestBytes+1) ?? Data();guard bytes.count<=maximumRequestBytes else{throw invalid()}
        let request=try JSONDecoder().decode(AuditionWorkerRequest.self,from:bytes)
        guard request.session==session else{throw invalid()};try validate(request);return request
    }
}

/// The independent stdin reader updates cancellation before native audio work can resume.
final class AuditionWorkerInbox:@unchecked Sendable {
    private let lock=NSLock()
    let session:UUID
    let control=MediaPreviewCancellation()
    private var sequence:UInt64=0
    private var commands:[AuditionWorkerCommand]=[]
    private var held:[Int:UUID]=[:]
    init(session:UUID){self.session=session}
    func accept(_ command:AuditionWorkerCommand)throws {
        lock.lock();defer{lock.unlock()}
        guard command.version==1,command.session==session,sequence<UInt64.max,command.sequence==sequence+1,commands.count<256,!control.isCancelled else{throw AuditionWorkerFiles.invalid()}
        if command.kind != .stop {
            guard let pitch=command.pitch,(0...127).contains(pitch),let token=command.token else{throw AuditionWorkerFiles.invalid()}
            if command.kind == .note {
                guard let velocity=command.velocity,(1...127).contains(velocity) else{throw AuditionWorkerFiles.invalid()}
                held[pitch]=token
            }else if held[pitch]==token {held[pitch]=nil}
        }else{held=[:];control.cancel()}
        sequence=command.sequence;commands.append(command)
    }
    func pop()->AuditionWorkerCommand? {lock.lock();defer{lock.unlock()};return commands.isEmpty ? nil:commands.removeFirst()}
    func current(pitch:Int,token:UUID)->Bool {lock.lock();defer{lock.unlock()};return !control.isCancelled && held[pitch]==token}
}
