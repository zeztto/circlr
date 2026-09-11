import XCTest
import Darwin
import CirclrCore
@testable import CirclrAudio

private final class AuditionWorkerFlag:@unchecked Sendable {
    private let lock=NSLock();private var flag=false
    func set(){lock.lock();flag=true;lock.unlock()}
    var value:Bool{lock.lock();defer{lock.unlock()};return flag}
}
private final class ImmediateFailureBackend:AuditionBackend,@unchecked Sendable {
    func note(_ pitch:Int,velocity:Int,on:Bool,isCurrent:@escaping @Sendable()->Bool)throws {}
    func stop() {}
    func installFailureHandler(_ handler:@escaping @Sendable(String)->Void){handler("buffered worker failure")}
}
private final class CleanupFailureBackend:AuditionBackend,@unchecked Sendable {
    let entered=AuditionWorkerFlag()
    let proceed=DispatchSemaphore(value:0)
    let failOnNote:Bool
    init(failOnNote:Bool){self.failOnNote=failOnNote}
    func note(_ pitch:Int,velocity:Int,on:Bool,isCurrent:@escaping @Sendable()->Bool)throws {throw CirclrError("note failure")}
    func stop(){entered.set();_ = proceed.wait(timeout:.now()+2)}
    func installFailureHandler(_ handler:@escaping @Sendable(String)->Void){if !failOnNote{handler("buffered failure")}}
}
@MainActor final class AuditionWorkerTests:XCTestCase {
    private var roots:[URL]=[]
    override func tearDown(){for root in roots{try? FileManager.default.removeItem(at:root)};roots=[]}
    private func fixture()throws->(URL,URL) {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-audition-tests-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);roots.append(root)
        let script=root.appendingPathComponent("worker")
        let source = #"""
#!/usr/bin/python3
import os,sys,json,time,signal,uuid
session=sys.argv[2]; directory=sys.argv[4]; root=os.path.dirname(directory)
r=json.load(open(directory+'/request.json')); mode=r['instrument']['plugin']['name']
assert set(r)=={'version','session','instrument','assets'} and r['assets']==[]
open(root+'/'+session+'.pid','w').write(str(os.getpid()))
def emit(kind,seq=0,**fields):
 print(json.dumps(dict(version=1,session=session,kind=kind,sequence=seq,**fields)),flush=True)
if mode in ['hangprepare','hangnote']: signal.signal(signal.SIGTERM,signal.SIG_IGN)
if mode=='hangprepare':
 while True: time.sleep(.01)
if mode=='stale': session=str(uuid.uuid4())
if mode=='oversized': print('x'*5000,flush=True)
emit('trace',stage='engineCreation',phase='entered');emit('trace',stage='engineCreation',phase='completed');emit('ready',capabilities=[] if mode=='missingcapability' else ['notes','token-release','diagnostics'])
if mode=='crashready': time.sleep(.15);os.kill(os.getpid(),signal.SIGKILL)
if mode=='forkpipe':
 child=os.fork()
 if child==0:
  time.sleep(.5);open(root+'/child.done','w').write('done');os._exit(0)
 time.sleep(.1);os._exit(0)
pending=None
for line in sys.stdin:
 c=json.loads(line)
 with open(root+'/events.jsonl','a') as f: f.write(json.dumps(c)+'\n')
 if c['kind']=='stop': emit('stopped',c['sequence']);sys.exit(0)
 if mode=='hangnote' and c['kind']=='note':
  while True: time.sleep(.01)
 if mode=='cancelnote' and c['kind']=='note': pending=c;continue
 if mode=='cancelnote' and c['kind']=='release':
  assert pending['token']==c['token'];open(root+'/released','w').write('yes');emit('ack',pending['sequence']);pending=None
 emit('ack',c['sequence'])
"""#
        try source.write(to:script,atomically:false,encoding:.utf8);try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:script.path)
        return(root,script)
    }
    private func target(_ mode:String)->AuditionTarget {
        var instrument=Instrument();instrument.kind = .audioUnit;instrument.plugin = .init(name:mode,type:0x61756d75,subtype:0x73616d70,manufacturer:0x6170706c)
        return .init(key:mode,instrument:instrument,project:Project(),root:nil)
    }
    private func backend(_ mode:String,root:URL,script:URL,control:MediaPreviewCancellation = .init(),timeout:Double=1)throws->WorkerAuditionBackend {
        try WorkerAuditionBackend(target:target(mode),control:control,report:{_,_ in},executable:script,temporaryRoot:root,prepareTimeout:mode=="hangprepare" ? timeout:1,noteTimeout:timeout,stopGrace:0.03)
    }
    private func assertClean(_ root:URL,file:StaticString=#filePath,line:UInt=#line)throws {
        let files=try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)
        XCTAssertFalse(files.contains{$0.lastPathComponent.hasPrefix("circlr-audition-")},file:file,line:line)
        for marker in files where marker.pathExtension=="pid" {
            let pid=try XCTUnwrap(Int32(String(contentsOf:marker)),file:file,line:line)
            XCTAssertEqual(kill(pid,0),-1,file:file,line:line);XCTAssertEqual(errno,ESRCH,file:file,line:line)
        }
    }
    func testPersistentNotesUseOneProcessAndTokenRelease()throws {
        let(root,script)=try fixture();let worker=try backend("normal",root:root,script:script)
        try worker.note(60,velocity:90,on:true,isCurrent:{true});try worker.note(60,velocity:0,on:false,isCurrent:{true})
        try worker.note(64,velocity:100,on:true,isCurrent:{true});worker.stop();worker.stop()
        let lines=try String(contentsOf:root.appendingPathComponent("events.jsonl")).split(separator:"\n").map{try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]}
        XCTAssertEqual(lines.map{$0["kind"] as! String},["note","release","note","stop"])
        XCTAssertEqual(lines[0]["token"] as? String,lines[1]["token"] as? String)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path).filter{$0.hasSuffix(".pid")}.count,1)
        try assertClean(root)
    }
    func testPreparationTimeoutKillsUnresponsiveChild()throws {
        let(root,script)=try fixture();let start=ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try backend("hangprepare",root:root,script:script,timeout:0.5))
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime-start,2);try assertClean(root)
    }
    func testCancelledPreparationReapsBeforeReturning()throws {
        let(root,script)=try fixture(),control=MediaPreviewCancellation()
        let observed=AuditionWorkerFlag()
        DispatchQueue.global().async {
            let deadline=ProcessInfo.processInfo.systemUptime+1
            while ProcessInfo.processInfo.systemUptime<deadline {
                if ((try? FileManager.default.contentsOfDirectory(atPath:root.path)) ?? []).contains(where:{$0.hasSuffix(".pid")}){observed.set();break}
                Thread.sleep(forTimeInterval:0.005)
            }
            control.cancel()
        }
        XCTAssertThrowsError(try backend("hangprepare",root:root,script:script,control:control)){XCTAssertTrue($0 is CancellationError)}
        XCTAssertTrue(observed.value);try assertClean(root)
    }
    func testPreCancelledNeverLaunches()throws {
        let(root,script)=try fixture(),control=MediaPreviewCancellation();control.cancel()
        XCTAssertThrowsError(try backend("normal",root:root,script:script,control:control))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path),["worker"])
    }
    func testNoteTimeoutDoesNotTrapCleanup()throws {
        let(root,script)=try fixture();let worker=try backend("hangnote",root:root,script:script,timeout:0.15)
        XCTAssertThrowsError(try worker.note(60,velocity:90,on:true,isCurrent:{true}));worker.stop();try assertClean(root)
    }
    func testReleaseWhileWaitingForNoteAckIsDelivered()throws {
        let(root,script)=try fixture();let worker=try backend("cancelnote",root:root,script:script),released=AuditionWorkerFlag()
        DispatchQueue.global().asyncAfter(deadline:.now()+0.06){released.set()}
        try worker.note(60,velocity:90,on:true,isCurrent:{!released.value})
        XCTAssertTrue(FileManager.default.fileExists(atPath:root.appendingPathComponent("released").path));worker.stop();try assertClean(root)
    }
    func testMalformedAndStaleResponseRejectAndReap()throws {
        for mode in ["stale","oversized","missingcapability"] {
            let(root,script)=try fixture();XCTAssertThrowsError(try backend(mode,root:root,script:script));try assertClean(root)
        }
    }
    func testIdleCrashBufferedUntilFailureHandlerInstalled()throws {
        let(root,script)=try fixture();let worker=try backend("crashready",root:root,script:script)
        Thread.sleep(forTimeInterval:0.25);let flag=AuditionWorkerFlag();worker.installFailureHandler{_ in flag.set()}
        XCTAssertTrue(flag.value);worker.stop();try assertClean(root)
    }
    func testInheritedStdoutDoesNotBlockParentCleanup()throws {
        let(root,script)=try fixture();let worker=try backend("forkpipe",root:root,script:script)
        Thread.sleep(forTimeInterval:0.16);let start=ProcessInfo.processInfo.systemUptime
        worker.stop();XCTAssertLessThan(ProcessInfo.processInfo.systemUptime-start,0.3);try assertClean(root)
        Thread.sleep(forTimeInterval:0.4);XCTAssertTrue(FileManager.default.fileExists(atPath:root.appendingPathComponent("child.done").path))
    }
    func testBufferedFailureSurvivesQueuedDrainUntilCancel()async throws {
        let worker=AuditionTransport(timeout:1,diagnosticFactory:{_,_,_ in ImmediateFailureBackend()})
        defer {worker.shutdown()}
        _ = worker.note(target:target("buffered"),pitch:60,velocity:90,on:true)
        try await Task.sleep(for:.milliseconds(150))
        XCTAssertEqual(worker.status.phase,.failed)
        XCTAssertEqual(worker.status.message,"buffered worker failure")
        XCTAssertEqual(worker.status.heldNotes,0)
        worker.cancel()
        try await Task.sleep(for:.milliseconds(100))
        XCTAssertEqual(worker.status.phase,.idle)
        XCTAssertNil(worker.status.message)
    }
    func testCancelDuringFailureCleanupWins()async throws {
        for failOnNote in [false,true] {
            let backend=CleanupFailureBackend(failOnNote:failOnNote)
            let worker=AuditionTransport(timeout:1,diagnosticFactory:{_,_,_ in backend})
            _ = worker.note(target:target("cleanup"),pitch:60,velocity:90,on:true)
            let deadline=ProcessInfo.processInfo.systemUptime+1
            while !backend.entered.value && ProcessInfo.processInfo.systemUptime<deadline{try await Task.sleep(for:.milliseconds(5))}
            XCTAssertTrue(backend.entered.value)
            worker.cancel();backend.proceed.signal()
            try await Task.sleep(for:.milliseconds(100))
            XCTAssertEqual(worker.status.phase,.idle,"failOnNote=\(failOnNote)")
            XCTAssertNil(worker.status.message)
            worker.shutdown()
        }
    }
    func testTransportLeavesReadyAfterIdleWorkerCrash()async throws {
        let(root,script)=try fixture()
        let worker=AuditionTransport(timeout:2,diagnosticFactory:{target,control,report in
            try WorkerAuditionBackend(target:target,control:control,report:report,executable:script,temporaryRoot:root,prepareTimeout:1,noteTimeout:1,stopGrace:0.03)
        })
        _ = worker.note(target:target("crashready"),pitch:60,velocity:90,on:true)
        let deadline=ProcessInfo.processInfo.systemUptime+3
        while worker.status.phase != .failed && ProcessInfo.processInfo.systemUptime<deadline{try await Task.sleep(for:.milliseconds(10))}
        XCTAssertEqual(worker.status.phase,.failed);XCTAssertEqual(worker.status.heldNotes,0);worker.shutdown();try assertClean(root)
    }
    func testInboxRejectsStaleSequenceAndOldReleaseKeepsNewToken()throws {
        let id=UUID(),a=UUID(),b=UUID(),inbox=AuditionWorkerInbox(session:UUID())
        let session=inbox.session
        try inbox.accept(.init(session:session,sequence:1,kind:.note,token:a,pitch:60,velocity:90))
        try inbox.accept(.init(session:session,sequence:2,kind:.note,token:b,pitch:60,velocity:90))
        try inbox.accept(.init(session:session,sequence:3,kind:.release,token:a,pitch:60))
        XCTAssertTrue(inbox.current(pitch:60,token:b));XCTAssertFalse(inbox.current(pitch:60,token:a))
        XCTAssertThrowsError(try inbox.accept(.init(session:id,sequence:4,kind:.stop)))
        XCTAssertThrowsError(try inbox.accept(.init(session:session,sequence:3,kind:.stop)))
        try inbox.accept(.init(session:session,sequence:4,kind:.stop));XCTAssertTrue(inbox.control.isCancelled);XCTAssertFalse(inbox.current(pitch:60,token:b))
    }
    func testInboxQueueBoundAndInvalidPitch()throws {
        let inbox=AuditionWorkerInbox(session:UUID())
        XCTAssertThrowsError(try inbox.accept(.init(session:inbox.session,sequence:1,kind:.note,token:UUID(),pitch:128,velocity:90)))
        for seq in 1...256 {try inbox.accept(.init(session:inbox.session,sequence:UInt64(seq),kind:.note,token:UUID(),pitch:60,velocity:90))}
        XCTAssertThrowsError(try inbox.accept(.init(session:inbox.session,sequence:257,kind:.note,token:UUID(),pitch:60,velocity:90)))
    }
    func testManifestCarriesOnlyNeededAssetsAndRejectsLoosePermissions()throws {
        let(root,_)=try fixture();var project=Project()
        let asset=Asset(name:"used",path:"/tmp/used.wav",duration:1,sampleRate:48000)
        project.assets=[asset,Asset(name:"unused",path:"/tmp/private.wav",duration:1,sampleRate:48000)]
        var instrument=Instrument();instrument.kind = .sampler;instrument.sample = .init(assetID:asset.id,rootPitch:60)
        let request=try AuditionWorkerRequest(session:UUID(),target:.init(key:"sample",instrument:instrument,project:project,root:nil))
        XCTAssertEqual(request.assets,[asset]);try AuditionWorkerFiles.write(request,in:root)
        XCTAssertEqual(try AuditionWorkerFiles.read(in:root,session:request.session).assets,[asset])
        try FileManager.default.setAttributes([.posixPermissions:0o644],ofItemAtPath:root.appendingPathComponent("request.json").path)
        XCTAssertThrowsError(try AuditionWorkerFiles.read(in:root,session:request.session))
    }
}
