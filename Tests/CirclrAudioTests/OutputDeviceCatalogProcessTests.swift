import XCTest
import Darwin
@testable import CirclrAudio

@MainActor final class OutputDeviceCatalogProcessTests:XCTestCase {
    private var roots:[URL]=[]
    override func tearDown(){for root in roots{try? FileManager.default.removeItem(at:root)}}
    private func fixture(_ mode:String)throws->(URL,URL) {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("catalog-test-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false);roots.append(root)
        let script=root.appendingPathComponent("worker")
        let source = #"""
#!/usr/bin/python3
import os,sys,time,signal,json
mode='MODE';root=os.path.dirname(sys.argv[0]);assert sys.argv[1:]==['--list']
if mode=='hang':signal.signal(signal.SIGTERM,signal.SIG_IGN)
open(root+'/pid','w').write(str(os.getpid()))
if mode=='hang':
 while True:time.sleep(.01)
if mode=='crash':os.kill(os.getpid(),signal.SIGKILL)
if mode=='oversize':sys.stdout.write('x'*100000);sys.stdout.flush();time.sleep(5)
if mode=='malformed':print('bad');sys.exit(0)
print(json.dumps(dict(version=1,devices=[dict(uid='mock',name='가상 검증 장치')],defaultUID='mock')),flush=True)
if mode=='early':os.close(1);time.sleep(.15)
if mode=='failed':sys.exit(23)
open(root+'/done','w').write('done')
"""#.replacingOccurrences(of:"MODE",with:mode)
        try source.write(to:script,atomically:false,encoding:.utf8)
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:script.path)
        return(root,script)
    }
    private func reaped(_ root:URL)throws {
        let pid=try XCTUnwrap(Int32(String(contentsOf:root.appendingPathComponent("pid"),encoding:.utf8)))
        XCTAssertEqual(kill(pid,0),-1);XCTAssertEqual(errno,ESRCH)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:root.path).contains{$0.hasPrefix("circlr-")})
    }
    func testSuccessWaitsForExit()async throws {
        let(root,script)=try fixture("early")
        let result=try await OutputDeviceCatalogProcess(executable:script).query()
        XCTAssertEqual(result.defaultUID,"mock");XCTAssertEqual(result.devices.count,1)
        XCTAssertTrue(FileManager.default.fileExists(atPath:root.appendingPathComponent("done").path));try reaped(root)
    }
    func testMalformedOversizeCrashAndNonzeroRejectAndReap()async throws {
        for mode in ["malformed","oversize","crash","failed"] {
            let(root,script)=try fixture(mode)
            do {_ = try await OutputDeviceCatalogProcess(executable:script).query();XCTFail("accepted \(mode)")}catch{}
            try reaped(root)
        }
    }
    func testTimeoutReapsUncooperativeChild()async throws {
        let(root,script)=try fixture("hang")
        let started=ProcessInfo.processInfo.systemUptime
        do {_ = try await OutputDeviceCatalogProcess(executable:script,timeout:0.5).query();XCTFail("timeout missing")}
        catch OutputDeviceCatalogError.timedOut {} catch{XCTFail("\(error)")}
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime-started,4)
        try reaped(root)
    }
    func testCancellationReapsBeforeCompletion()async throws {
        let(root,script)=try fixture("hang")
        let task=Task {try await OutputDeviceCatalogProcess(executable:script).query()}
        let deadline=ProcessInfo.processInfo.systemUptime+3
        while !FileManager.default.fileExists(atPath:root.appendingPathComponent("pid").path) {
            if ProcessInfo.processInfo.systemUptime>deadline{task.cancel();_ = try? await task.value;XCTFail("child did not start");return}
            try await Task.sleep(for:.milliseconds(10))
        }
        let cancelledAt=ProcessInfo.processInfo.systemUptime
        task.cancel()
        do {_ = try await task.value;XCTFail("cancel missing")}catch is CancellationError {}catch{XCTFail("\(error)")}
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime-cancelledAt,3)
        try reaped(root)
    }
    func testPrecancelNeverLaunches()async throws {
        let(root,script)=try fixture("early")
        let task=Task {withUnsafeCurrentTask{$0?.cancel()};return try await OutputDeviceCatalogProcess(executable:script).query()}
        do {_ = try await task.value;XCTFail("cancel missing")}catch is CancellationError {}catch{XCTFail("\(error)")}
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("pid").path))
    }
}
