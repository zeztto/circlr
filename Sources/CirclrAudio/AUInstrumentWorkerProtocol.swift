import Foundation
import AudioToolbox
import Darwin
import CirclrCore

struct InstrumentClockSnapshot: Codable, Equatable {
    let barStarts: [Double]
    let barContinuationBeat: Double
    let meters: [Meter]
    let tempos: [TempoChange]
    init(_ clock: MusicClock) {
        barStarts=clock.barStarts;barContinuationBeat=clock.barContinuationBeat;meters=clock.meters;tempos=clock.tempos
    }
    func clock() throws -> MusicClock {
        try MusicClock(barStarts:barStarts,barContinuationBeat:barContinuationBeat,meters:meters,tempos:tempos)
    }
}
struct AUInstrumentWorkerRequest: Codable {
    var version=1
    var session: UUID
    let notes: [Note]
    let instrument: Instrument
    let clock: InstrumentClockSnapshot
    let tail: Double
    let hostContext: MusicContext?
    init(session:UUID,notes:[Note],instrument:Instrument,clock:MusicClock,tail:Double,hostContext:MusicContext?) {
        self.session=session;self.notes=notes;self.instrument=instrument;self.clock=InstrumentClockSnapshot(clock)
        self.tail=tail;self.hostContext=hostContext
    }
}
enum AUInstrumentWorkerFiles {
    static func validate(_ request:AUInstrumentWorkerRequest)throws->(clock:MusicClock,frames:Int) {
        guard request.version==1,request.notes.count<=100_000,request.tail.isFinite,(0...120).contains(request.tail),
              request.instrument.kind == .soundBank || request.instrument.kind == .audioUnit else {throw invalid()}
        let clock=try request.clock.clock()
        let frames=ceil((clock.seconds+request.tail)*PCM.rate)
        guard frames.isFinite,frames>0,frames<=Double(AUEffectWorkerFiles.maximumFrames) else {throw invalid()}
        if let host=request.hostContext {try ContextResolver.validate(host)}
        for note in request.notes {
            guard note.beat.isFinite,note.beat>=0,note.length.isFinite,note.length>0,(note.beat+note.length).isFinite,
                  (0...127).contains(note.pitch),(0...127).contains(note.velocity) else {throw invalid()}
        }
        if request.instrument.kind == .audioUnit {
            guard let descriptor=request.instrument.plugin,descriptor.type==kAudioUnitType_MusicDevice,
                  descriptor.name.utf8.count<=1024,(descriptor.state?.count ?? 0)<=AUEffectWorkerFiles.maximumStateBytes else {throw invalid()}
            if let state=descriptor.state {
                guard (try? PropertyListSerialization.propertyList(from:state,format:nil)) is [String:Any] else {throw invalid()}
            }
        } else { _ = try AudioUnitHost.soundBankLoadAddress(request.instrument) }
        return (clock,Int(frames))
    }
    private static func invalid()->CirclrError {CirclrError("Audio Unit 악기 요청을 확인하세요")}
    static func writeRequest(_ request:AUInstrumentWorkerRequest,to directory:URL)throws {
        try AUEffectWorkerFiles.validateDirectory(directory);_ = try validate(request)
        let bytes=try JSONEncoder().encode(request)
        guard bytes.count<=AUEffectWorkerFiles.maximumRequestBytes else {throw invalid()}
        let fd=open(directory.appendingPathComponent("request.json").path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,mode_t(0o600))
        guard fd>=0 else {throw invalid()}
        let file=FileHandle(fileDescriptor:fd,closeOnDealloc:true);defer{try? file.close()}
        try file.write(contentsOf:bytes)
    }
    static func readRequest(in directory:URL,session:UUID)throws->AUInstrumentWorkerRequest {
        try AUEffectWorkerFiles.validateDirectory(directory)
        let fd=open(directory.appendingPathComponent("request.json").path,O_RDONLY|O_NOFOLLOW|O_NONBLOCK)
        guard fd>=0 else {throw invalid()}
        let file=FileHandle(fileDescriptor:fd,closeOnDealloc:true);defer{try? file.close()}
        var info=stat()
        guard fstat(fd,&info)==0,info.st_uid==geteuid(),info.st_mode&S_IFMT==S_IFREG,info.st_mode&0o077==0,info.st_nlink==1,
              info.st_size>=0,info.st_size<=AUEffectWorkerFiles.maximumRequestBytes else {throw invalid()}
        let bytes=try file.read(upToCount:AUEffectWorkerFiles.maximumRequestBytes+1) ?? Data()
        guard bytes.count<=AUEffectWorkerFiles.maximumRequestBytes else {throw invalid()}
        let request=try JSONDecoder().decode(AUInstrumentWorkerRequest.self,from:bytes)
        guard request.session==session else {throw invalid()};_ = try validate(request);return request
    }
}
