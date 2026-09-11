import XCTest
import Darwin
import CirclrCore
@testable import CirclrAudio

@MainActor final class AUEffectWorkerProcessTests:XCTestCase {
    private var roots:[URL]=[]
    override func tearDown(){for root in roots {try? FileManager.default.removeItem(at:root)};roots=[]}
    private func fixture()throws->(URL,URL) {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("circlr-effect-test-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);roots.append(root)
        let script=root.appendingPathComponent("worker")
        let source = #"""
#!/usr/bin/python3
import os,sys,json,signal,time,shutil,struct,uuid
session=sys.argv[2]; directory=sys.argv[4]
r=json.load(open(directory+'/request.json')); mode=r['descriptor']['name']
open(os.path.dirname(directory)+'/'+session+'.pid','w').write(str(os.getpid()))
if mode=='hang':
 signal.signal(signal.SIGTERM,signal.SIG_IGN)
 while True: time.sleep(.01)
if mode=='crash': os.kill(os.getpid(),signal.SIGKILL)
if mode=='missing': sys.exit(0)
shutil.copyfile(directory+'/input.caf',directory+'/result.caf'); os.chmod(directory+'/result.caf',0o600)
if mode=='truncated':
 with open(directory+'/result.caf','r+b') as f: f.truncate(12)
if mode=='nonfinite':
 p=directory+'/result.caf'; data=bytearray(open(p,'rb').read()); offset=8
 while offset+12<=len(data):
  kind=data[offset:offset+4]; size=struct.unpack('>q',data[offset+4:offset+12])[0]
  if kind==b'data': data[offset+16:offset+20]=b'\xff\xff\xff\xff'; break
  offset+=12+size
 open(p,'wb').write(data)
json.dump(dict(version=1,session=str(uuid.uuid4()) if mode=='stale' else session,frames=r['frames']),open(directory+'/result.json','w'));os.chmod(directory+'/result.json',0o600)
if mode=='failed': sys.exit(23)
if mode=='early':
 os.close(1);os.close(2);time.sleep(.25)
open(os.path.dirname(directory)+'/'+session+'.done','w').write('done')
"""#
        try source.write(to:script,atomically:false,encoding:.utf8)
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:script.path)
        return(root,script)
    }
    private func descriptor(_ mode:String)->PluginDescriptor {.init(name:mode,type:0x61756678,subtype:0x64656c79,manufacturer:0x6170706c)}
    private func pcm()->PCM {var p=PCM(frames:128);p.left[0]=0.25;p.right[1] = -0.125;return p}
    private func contents(_ root:URL)throws->[URL] {try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)}
    private func assertReapedAndClean(_ root:URL,file:StaticString=#filePath,line:UInt=#line)throws {
        let files=try contents(root)
        XCTAssertFalse(files.contains{$0.lastPathComponent.hasPrefix("circlr-au-effect-")},file:file,line:line)
        for marker in files where marker.pathExtension=="pid" {
            let pid=try XCTUnwrap(Int32(String(contentsOf:marker,encoding:.utf8)),file:file,line:line)
            XCTAssertEqual(Darwin.kill(pid,0),-1,file:file,line:line);XCTAssertEqual(errno,ESRCH,file:file,line:line)
        }
    }
    private func waitForPID(_ root:URL)async throws {
        let deadline=ProcessInfo.processInfo.systemUptime+5
        while try !contents(root).contains(where:{$0.pathExtension=="pid"}) {
            guard ProcessInfo.processInfo.systemUptime<deadline else{throw NSError(domain:"fixture-start",code:1)}
            try await Task.sleep(for:.milliseconds(10))
        }
    }
    func testSuccessWaitsForExitAndPreservesPCM()async throws {
        let(root,script)=try fixture();let input=pcm()
        let output=try await AUEffectWorkerProcess(executable:script,timeout:5,temporaryRoot:root).process(input:input,plugin:descriptor("early"))
        XCTAssertEqual(output.left,input.left);XCTAssertEqual(output.right,input.right)
        XCTAssertTrue(try contents(root).contains{$0.pathExtension=="done"});try assertReapedAndClean(root)
    }
    func testCrashExitFailureAndInvalidArtifactsRejectAndClean()async throws {
        for mode in ["crash","failed","missing","truncated","nonfinite","stale"] {
            let(root,script)=try fixture()
            do {_ = try await AUEffectWorkerProcess(executable:script,timeout:5,temporaryRoot:root).process(input:pcm(),plugin:descriptor(mode));XCTFail("accepted \(mode)")}
            catch {XCTAssertFalse(error is CancellationError)}
            try assertReapedAndClean(root)
        }
    }
    func testTimeoutKillsUncooperativeChildBeforeReturning()async throws {
        let(root,script)=try fixture()
        do {_ = try await AUEffectWorkerProcess(executable:script,timeout:1,temporaryRoot:root).process(input:pcm(),plugin:descriptor("hang"));XCTFail("timeout missing")}
        catch AUEffectWorkerProcessError.timedOut {} catch {XCTFail("\(error)")}
        XCTAssertTrue(try contents(root).contains{$0.pathExtension=="pid"});try assertReapedAndClean(root)
    }
    func testCancellationReapsOnlyOwnedInvocationAndNextCallSucceeds()async throws {
        let(root,script)=try fixture();let host=AUEffectWorkerProcess(executable:script,timeout:5,temporaryRoot:root)
        let input=pcm(),plugin=descriptor("hang")
        let task=Task {try await host.process(input:input,plugin:plugin)}
        try await waitForPID(root);task.cancel()
        do {_ = try await task.value;XCTFail("cancellation missing")} catch is CancellationError {} catch {XCTFail("\(error)")}
        try assertReapedAndClean(root)
        let output=try await host.process(input:input,plugin:descriptor("early"))
        XCTAssertEqual(output.left,input.left);try assertReapedAndClean(root)
    }
    func testCancelledChildCleanupDoesNotTerminateOverlappingInvocation()async throws {
        let(root,script)=try fixture();let host=AUEffectWorkerProcess(executable:script,timeout:5,temporaryRoot:root)
        let input=pcm(),hanging=descriptor("hang"),successful=descriptor("early")
        let first=Task {try await host.process(input:input,plugin:hanging)}
        try await waitForPID(root)
        first.cancel()
        // Start B before awaiting A: A may still be in its TERM-to-KILL grace period.
        let second=Task {try await host.process(input:input,plugin:successful)}
        do {_ = try await first.value;XCTFail("cancellation missing")} catch is CancellationError {} catch {XCTFail("\(error)")}
        let output=try await second.value
        XCTAssertEqual(output.left,input.left);XCTAssertEqual(output.right,input.right)
        XCTAssertEqual(try contents(root).filter{$0.pathExtension=="pid"}.count,2)
        try assertReapedAndClean(root)
    }
    func testPrelaunchCancellationNeverSpawnsAndCleansFiles()async throws {
        let(root,script)=try fixture();let entered=DispatchSemaphore(value:0),resume=DispatchSemaphore(value:0)
        let host=AUEffectWorkerProcess(executable:script,timeout:5,temporaryRoot:root,beforeLaunch:{entered.signal();resume.wait()})
        let input=pcm(),plugin=descriptor("early")
        let task=Task {try await host.process(input:input,plugin:plugin)}
        let deadline=ProcessInfo.processInfo.systemUptime+3
        while entered.wait(timeout:.now()) != .success {
            if ProcessInfo.processInfo.systemUptime>=deadline {resume.signal();XCTFail("launch gate missing");return}
            try await Task.sleep(for:.milliseconds(10))
        }
        task.cancel();resume.signal()
        do {_ = try await task.value;XCTFail("cancellation missing")} catch is CancellationError {} catch {XCTFail("\(error)")}
        XCTAssertFalse(try contents(root).contains{$0.pathExtension=="pid"});try assertReapedAndClean(root)
    }
    func testEmptyInputAndBoundedDefaultDeadline()async throws {
        let result=try await AUEffectWorkerProcess(executable:nil).process(input:PCM(frames:0),plugin:descriptor("success"))
        XCTAssertEqual(result.count,0)
        XCTAssertEqual(AUEffectWorkerProcess.deadlineSeconds(for:0),30)
        XCTAssertEqual(AUEffectWorkerProcess.deadlineSeconds(for:100),415)
        XCTAssertEqual(AUEffectWorkerProcess.deadlineSeconds(for:10000),1800)
    }
    func testInvalidInputAndUnavailableExecutableDoNotLeaveFiles()async throws {
        let(root,script)=try fixture()
        var invalid=pcm();invalid.left[0] = .nan
        for (input,executable) in [(invalid,script),(pcm(),root.appendingPathComponent("missing"))] {
            do {_ = try await AUEffectWorkerProcess(executable:executable,timeout:5,temporaryRoot:root).process(input:input,plugin:descriptor("success"));XCTFail("invalid request accepted")} catch {}
            try assertReapedAndClean(root)
        }
        XCTAssertFalse(try contents(root).contains{$0.pathExtension=="pid"})
    }
}
