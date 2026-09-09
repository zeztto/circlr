import Foundation
import AVFAudio
import AudioToolbox
import Darwin
import CirclrCore

struct AUEffectWorkerRequest: Codable, Equatable {
    var version = 1
    let session: UUID
    let descriptor: PluginDescriptor
    let frames: Int
    init(session: UUID, descriptor: PluginDescriptor, frames: Int) {
        self.session = session; self.descriptor = descriptor; self.frames = frames
    }
}
struct AUEffectWorkerResult: Codable, Equatable {
    var version = 1
    let session: UUID
    let frames: Int
    init(session: UUID, frames: Int) { self.session = session; self.frames = frames }
}

enum AUEffectWorkerFiles {
    // Match the renderer's absolute 2 GiB preparation ceiling: stereo Float32 is 8 bytes/frame.
    // Existing render preflight still accounts for all simultaneous buffers.
    static let maximumFrames = 268_435_456
    static let maximumStateBytes = 8 * 1024 * 1024
    static let maximumRequestBytes = 12 * 1024 * 1024
    private static let maximumCAFOverhead = 64 * 1024

    static func validateDirectory(_ url: URL) throws {
        try validateOwned(url, directory: true, maximumBytes: nil)
    }
    private static func invalid() -> CirclrError { CirclrError("Audio Unit 작업 파일이 올바르지 않습니다") }
    private static func validateOwned(_ url: URL, directory: Bool, maximumBytes: Int?) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_uid == geteuid(), info.st_mode & 0o077 == 0,
              info.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG),
              directory || info.st_nlink == 1 else { throw invalid() }
        if let maximumBytes { guard info.st_size >= 0, info.st_size <= maximumBytes else { throw invalid() } }
    }
    static func validate(_ request: AUEffectWorkerRequest) throws {
        guard request.version == 1, (1...maximumFrames).contains(request.frames),
              request.descriptor.name.utf8.count <= 1024,
              [kAudioUnitType_Effect, kAudioUnitType_MusicEffect].contains(request.descriptor.type),
              (request.descriptor.state?.count ?? 0) <= maximumStateBytes else { throw invalid() }
        if let state = request.descriptor.state {
            guard (try? PropertyListSerialization.propertyList(from: state, format: nil)) is [String: Any] else { throw invalid() }
        }
    }
    private static func writeExclusive(_ data: Data, to url: URL) throws {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw invalid() }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do { try handle.write(contentsOf: data); try handle.close() }
        catch { try? handle.close(); throw error }
    }
    private static func data(at url: URL, maximumBytes: Int) throws -> Data {
        try validateOwned(url, directory: false, maximumBytes: maximumBytes)
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw invalid() }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw invalid() }
        return data
    }
    static func writeRequest(_ request: AUEffectWorkerRequest, to directory: URL) throws {
        try validateDirectory(directory); try validate(request)
        let bytes = try JSONEncoder().encode(request)
        guard bytes.count <= maximumRequestBytes else { throw invalid() }
        try writeExclusive(bytes, to: directory.appendingPathComponent("request.json"))
    }
    static func readRequest(in directory: URL, session: UUID) throws -> AUEffectWorkerRequest {
        try validateDirectory(directory)
        let request = try JSONDecoder().decode(AUEffectWorkerRequest.self, from: data(at: directory.appendingPathComponent("request.json"), maximumBytes: maximumRequestBytes))
        try validate(request)
        guard request.session == session else { throw invalid() }
        return request
    }
    static func writeInput(_ pcm: PCM, to directory: URL, checkCancellation: () throws -> Void = { try Task.checkCancellation() }) throws {
        try validateDirectory(directory)
        try writePCM(pcm, to: directory.appendingPathComponent("input.caf"), checkCancellation: checkCancellation)
    }
    private static func writePCM(_ pcm: PCM, to url: URL, checkCancellation: () throws -> Void = { try Task.checkCancellation() }) throws {
        guard (1...maximumFrames).contains(pcm.count), pcm.left.count == pcm.right.count,
              let format = AVAudioFormat(standardFormatWithSampleRate: PCM.rate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096),
              let channels = buffer.floatChannelData else { throw invalid() }
        try writeExclusive(Data(), to: url)
        var settings = format.settings
        settings[AVLinearPCMIsNonInterleaved] = false
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        var cursor = 0
        while cursor < pcm.count {
            try checkCancellation()
            let count = min(4096, pcm.count - cursor)
            for i in 0..<count {
                let l = pcm.left[cursor+i], r = pcm.right[cursor+i]
                guard l.isFinite, r.isFinite else { throw invalid() }
                channels[0][i] = l; channels[1][i] = r
            }
            buffer.frameLength = AVAudioFrameCount(count)
            try file.write(from: buffer); cursor += count
        }
    }
    static func readPCM(at url: URL, frames: Int, checkCancellation: () throws -> Void = { try Task.checkCancellation() }) throws -> PCM {
        guard (1...maximumFrames).contains(frames) else { throw invalid() }
        try validateOwned(url, directory: false, maximumBytes: frames * 8 + maximumCAFOverhead)
        let header = try FileHandle(forReadingFrom: url)
        defer { try? header.close() }
        guard try header.read(upToCount: 4) == Data("caff".utf8) else { throw invalid() }
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let f = file.fileFormat.streamDescription.pointee
        guard file.length == frames, f.mFormatID == kAudioFormatLinearPCM,
              f.mSampleRate == PCM.rate, f.mChannelsPerFrame == 2, f.mBitsPerChannel == 32,
              f.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096),
              let channels = buffer.floatChannelData else { throw invalid() }
        var pcm = PCM(frames: frames), cursor = 0
        while cursor < frames {
            try checkCancellation()
            try file.read(into: buffer, frameCount: AVAudioFrameCount(min(4096, frames-cursor)))
            let count = Int(buffer.frameLength)
            guard count > 0, count <= frames-cursor else { throw invalid() }
            for i in 0..<count {
                let l = channels[0][i], r = channels[1][i]
                guard l.isFinite, r.isFinite else { throw invalid() }
                pcm.left[cursor+i] = l; pcm.right[cursor+i] = r
            }
            cursor += count
        }
        return pcm
    }
    // link publishes a complete inode without overwriting any existing result.
    private static func publish(_ temporary: URL, as final: URL) throws {
        guard link(temporary.path, final.path) == 0 else { throw invalid() }
        guard unlink(temporary.path) == 0 else { throw invalid() }
    }
    static func publishResult(_ pcm: PCM, session: UUID, in directory: URL) throws {
        try validateDirectory(directory)
        let audio = directory.appendingPathComponent("result.pending.caf")
        try writePCM(pcm, to: audio)
        _ = try readPCM(at: audio, frames: pcm.count)
        try publish(audio, as: directory.appendingPathComponent("result.caf"))
        let manifest = directory.appendingPathComponent("result.pending.json")
        try writeExclusive(JSONEncoder().encode(AUEffectWorkerResult(session: session, frames: pcm.count)), to: manifest)
        try publish(manifest, as: directory.appendingPathComponent("result.json"))
    }
    static func readResult(in directory: URL, session: UUID, frames: Int, checkCancellation: () throws -> Void = { try Task.checkCancellation() }) throws -> PCM {
        try validateDirectory(directory)
        let result = try JSONDecoder().decode(AUEffectWorkerResult.self, from: data(at: directory.appendingPathComponent("result.json"), maximumBytes: 1024))
        guard result.version == 1, result.session == session, result.frames == frames else { throw invalid() }
        return try readPCM(at: directory.appendingPathComponent("result.caf"), frames: frames, checkCancellation: checkCancellation)
    }
}
