import Foundation
import Darwin

/// A single offline effect job. This entry point belongs only in the helper process.
public enum AUEffectWorkerService {
    public static func run(arguments: [String]) -> Never {
        guard arguments.count == 4, arguments[0] == "--session", let session = UUID(uuidString: arguments[1]),
              arguments[2] == "--directory" else { exit(64) }
        signal(SIGPIPE, SIG_IGN)
        let directory = URL(fileURLWithPath: arguments[3], isDirectory: true).standardizedFileURL
        do { try AUEffectWorkerFiles.validateDirectory(directory) } catch { exit(65) }
        // Parent death/cancellation remains effective while a plugin blocks the main thread.
        DispatchQueue(label: "circlr.au-effect-parent").async {
            var bytes = [UInt8](repeating: 0, count: 64)
            while true {
                let count = bytes.withUnsafeMutableBytes { Darwin.read(STDIN_FILENO, $0.baseAddress, $0.count) }
                if count < 0 && errno == EINTR { continue }
                // This one-shot protocol accepts no commands. EOF or unexpected input ends it.
                exit(count == 0 ? 0 : 66)
            }
        }
        Task { @MainActor in
            do {
                let request = try AUEffectWorkerFiles.readRequest(in: directory, session: session)
                let input = try AUEffectWorkerFiles.readPCM(at: directory.appendingPathComponent("input.caf"), frames: request.frames)
                let unit = try await AudioUnitHost.instantiate(request.descriptor)
                let output = try AudioUnitHost.process(input, unit: unit)
                guard output.count == request.frames else { exit(70) }
                try AUEffectWorkerFiles.publishResult(output, session: session, in: directory)
                exit(0)
            } catch {
                try? FileHandle.standardError.write(contentsOf: Data("Audio Unit offline effect failed\n".utf8))
                exit(70)
            }
        }
        RunLoop.main.run()
        exit(70)
    }
}
