import Foundation
import Darwin

/// A single offline instrument job. This entry point belongs only in the helper process.
public enum AUInstrumentWorkerService {
    public static func run(arguments: [String]) -> Never {
        guard arguments.count == 4, arguments[0] == "--session", let session = UUID(uuidString: arguments[1]),
              arguments[2] == "--directory" else { exit(64) }
        signal(SIGPIPE, SIG_IGN)
        let directory = URL(fileURLWithPath: arguments[3], isDirectory: true).standardizedFileURL
        do { try AUEffectWorkerFiles.validateDirectory(directory) } catch { exit(65) }
        // Parent death/cancellation remains effective while a plugin blocks the main thread.
        DispatchQueue(label: "circlr.au-instrument-parent").async {
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
                let request = try AUInstrumentWorkerFiles.readRequest(in: directory, session: session)
                let prepared = try AUInstrumentWorkerFiles.validate(request)
                let output = try await AudioUnitHost.renderNotes(request.notes,instrument:request.instrument,
                    clock:prepared.clock,tail:request.tail,hostContext:request.hostContext)
                guard output.count == prepared.frames else { exit(70) }
                try AUEffectWorkerFiles.publishResult(output, session: session, in: directory)
                exit(0)
            } catch {
                try? FileHandle.standardError.write(contentsOf: Data("Audio Unit offline instrument failed\n".utf8))
                exit(70)
            }
        }
        RunLoop.main.run()
        exit(70)
    }
}
