import Foundation
import Darwin

/// The host never calls CoreAudio. Each query owns and reaps exactly one helper.
/// Five seconds bounds the query deadline, not total completion: cancellation/timeout
/// additionally waits for the owned child to be reaped. After SIGKILL, Foundation's
/// waitUntilExit relies on platform process termination and has no separate deadline.
public final class OutputDeviceCatalogProcess:Sendable {
    private let executable:URL?
    private let timeout:Double
    public init(executable:URL?=Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("circlr-output-device-catalog"),timeout:Double=5){self.executable=executable;self.timeout=timeout}
    public func query()async throws->OutputDeviceCatalog {
        try Task.checkCancellation()
        let operation=Operation()
        let result:OutputDeviceCatalog=try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {continuation in
                DispatchQueue(label:"circlr.output-catalog."+UUID().uuidString).async {
                    do {continuation.resume(returning:try operation.run(executable:self.executable,timeout:self.timeout))}
                    catch {continuation.resume(throwing:error)}
                }
            }
        } onCancel:{operation.cancel()}
        try Task.checkCancellation();return result
    }
    private final class Operation:@unchecked Sendable {
        private let lock=NSLock();private var cancelled=false
        func cancel(){lock.lock();cancelled=true;lock.unlock()}
        func check(_ deadline:Double)throws {
            lock.lock();let stopped=cancelled;lock.unlock()
            if stopped{throw CancellationError()}
            if ProcessInfo.processInfo.systemUptime>=deadline{throw OutputDeviceCatalogError.timedOut}
        }
        func run(executable:URL?,timeout:Double)throws->OutputDeviceCatalog {
            guard timeout.isFinite,timeout>0 else{throw OutputDeviceCatalogError.timedOut}
            let deadline=ProcessInfo.processInfo.systemUptime+min(5,timeout)
            try check(deadline)
            guard let executable,FileManager.default.isExecutableFile(atPath:executable.path) else{throw OutputDeviceCatalogError.unavailable}
            let child=Process(),input=Pipe(),output=Pipe();var launched=false,reaped=false
            defer {
                try? input.fileHandleForWriting.close()
                if launched && !reaped {
                    if child.isRunning {
                        _ = kill(child.processIdentifier,SIGTERM)
                        let grace=ProcessInfo.processInfo.systemUptime+0.2
                        while child.isRunning && ProcessInfo.processInfo.systemUptime<grace{Thread.sleep(forTimeInterval:0.01)}
                        if child.isRunning{_ = kill(child.processIdentifier,SIGKILL)}
                    }
                    child.waitUntilExit()
                }
                try? input.fileHandleForReading.close();try? output.fileHandleForReading.close();try? output.fileHandleForWriting.close()
            }
            child.executableURL=executable;child.arguments=["--list"]
            child.standardInput=input;child.standardOutput=output;child.standardError=FileHandle.nullDevice
            let fd=output.fileHandleForReading.fileDescriptor
            guard fcntl(fd,F_SETFL,O_NONBLOCK)>=0 else{throw OutputDeviceCatalogError.invalidResponse}
            try check(deadline);try child.run();launched=true
            try? input.fileHandleForReading.close();try? output.fileHandleForWriting.close()
            var data=Data(),eof=false,buffer=[UInt8](repeating:0,count:4096)
            while true {
                try check(deadline)
                let count=buffer.withUnsafeMutableBytes{Darwin.read(fd,$0.baseAddress,$0.count)}
                if count>0 {
                    guard data.count+count<=OutputDeviceCatalog.maximumBytes else{throw OutputDeviceCatalogError.invalidResponse}
                    data.append(contentsOf:buffer.prefix(count))
                } else if count==0 {eof=true}
                else if errno != EAGAIN && errno != EINTR{throw OutputDeviceCatalogError.invalidResponse}
                if !child.isRunning && eof{break}
                if count<=0{Thread.sleep(forTimeInterval:0.005)}
            }
            child.waitUntilExit();reaped=true;try check(deadline)
            guard child.terminationReason == .exit,child.terminationStatus==0 else{throw OutputDeviceCatalogError.failed(child.terminationStatus)}
            let result=try OutputDeviceCatalog.decode(data);try check(deadline);return result
        }
    }
}
