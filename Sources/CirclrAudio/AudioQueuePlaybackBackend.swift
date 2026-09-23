import Foundation
import AVFAudio
import AudioToolbox
import CoreAudio

enum AudioQueuePlaybackError: Error, LocalizedError {
    case invalidFile
    case invalidState
    case changedDevice
    case underrun
    case systemCall(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidFile: return "재생 오디오 파일의 형식이 올바르지 않습니다"
        case .invalidState: return "오디오 출력 상태가 올바르지 않습니다"
        case .changedDevice: return "출력 장치가 변경되어 재생을 정지했습니다. 장치 선택을 확인하세요."
        case .underrun: return "오디오 출력을 제때 공급하지 못해 재생을 정지했습니다"
        case .systemCall(let operation, let status): return "오디오 출력 \(operation)에 실패했습니다 (OSStatus \(status))"
        }
    }
}

private protocol AudioQueuePCMSource: AnyObject {
    var submittedFrames: Int64 { get }
    var finished: Bool { get }
    var maximumClockSeconds: Double? { get }
    func fill(_ destination: UnsafeMutableBufferPointer<Float>) throws -> Int
}

/// A queue that retains its device UID can still stop advancing. Detect that
/// independently of device identity so the transport cannot remain playing forever.
struct AudioQueueProgressWatchdog {
    private var lastSeconds: Double = 0
    private var lastAdvanceAt: Double

    init(startedAt: Double) { lastAdvanceAt = startedAt }

    mutating func observe(_ seconds: Double, at time: Double) throws {
        guard seconds.isFinite, seconds >= 0, time.isFinite else { throw AudioQueuePlaybackError.underrun }
        if seconds > lastSeconds + 1 / 48_000 {
            lastSeconds = seconds
            lastAdvanceAt = time
        } else if time - lastAdvanceAt > 2 {
            throw AudioQueuePlaybackError.underrun
        }
    }
}

/// Reads one small, interleaved PCM chunk at a time. The source file stays open;
/// a long arrangement never needs to be loaded into memory for playback.
final class AudioQueuePCMChunkReader: AudioQueuePCMSource {
    static let framesPerBuffer = 4_096
    let file: AVAudioFile
    private let scratch: AVAudioPCMBuffer
    var submittedFrames: Int64 { file.framePosition }
    var finished: Bool { file.framePosition >= file.length }
    var maximumClockSeconds: Double? { Double(file.length) / 48_000 }

    init(file: AVAudioFile) throws {
        guard file.length > 0,
              file.processingFormat.sampleRate == 48_000,
              file.processingFormat.channelCount == 2,
              file.processingFormat.commonFormat == .pcmFormatFloat32,
              !file.processingFormat.isInterleaved,
              let scratch = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                             frameCapacity: AVAudioFrameCount(Self.framesPerBuffer)) else {
            throw AudioQueuePlaybackError.invalidFile
        }
        self.file = file
        self.scratch = scratch
        file.framePosition = 0
    }

    /// `destination` has space for interleaved stereo samples. Returns frames, not samples.
    func fill(_ destination: UnsafeMutableBufferPointer<Float>) throws -> Int {
        guard destination.count >= 2, destination.count % 2 == 0 else { throw AudioQueuePlaybackError.invalidFile }
        let remaining = file.length - file.framePosition
        if remaining <= 0 { return 0 }
        let frames = min(Int(remaining), Self.framesPerBuffer, destination.count / 2)
        try file.read(into: scratch, frameCount: AVAudioFrameCount(frames))
        guard Int(scratch.frameLength) == frames, let channels = scratch.floatChannelData else {
            throw AudioQueuePlaybackError.invalidFile
        }
        for frame in 0..<frames {
            let left = channels[0][frame], right = channels[1][frame]
            guard left.isFinite, right.isFinite else { throw AudioQueuePlaybackError.invalidFile }
            destination[frame * 2] = left
            destination[frame * 2 + 1] = right
        }
        return frames
    }

}

/// Renders exact cycle/tail samples into contiguous AudioQueue buffers. All calls
/// are serialized by the backend; a replacement takes effect at the next
/// boundary that has not already been submitted to AudioQueue.
final class AudioQueueLoopChunkReader: AudioQueuePCMSource {
    private var planner: PlaybackLoopSchedule
    private var sources: [UUID: OutputWorkerLoopScheduler.Audio]
    private(set) var finished = false
    var submittedFrames: Int64 { planner.elapsedFrame }
    var maximumClockSeconds: Double? { nil }

    init(audio: OutputWorkerLoopScheduler.Audio, fromFrame: Int) throws {
        try Self.validate(audio)
        let id = UUID()
        planner = try PlaybackLoopSchedule(source: .init(id: id, frames: audio.frames,
                                                         tailFrames: audio.tailFrames), fromFrame: fromFrame)
        sources = [id: audio]
    }

    @discardableResult func request(id: UUID, audio: OutputWorkerLoopScheduler.Audio?) throws -> PlaybackLoopSchedule.Boundary {
        guard !finished else { throw AudioQueuePlaybackError.invalidState }
        if let audio { try Self.validate(audio) }
        let source = audio.map { PlaybackLoopSchedule.Source(id: id, frames: $0.frames, tailFrames: $0.tailFrames) }
        let boundary = try planner.request(.init(id: id, replacement: source))
        if let audio { sources[id] = audio }
        return boundary
    }

    func fill(_ destination: UnsafeMutableBufferPointer<Float>) throws -> Int {
        guard destination.count >= 2, destination.count % 2 == 0 else { throw AudioQueuePlaybackError.invalidFile }
        if finished { return 0 }
        var written = 0
        let capacity = min(destination.count / 2, AudioQueuePCMChunkReader.framesPerBuffer)
        while written < capacity && !finished {
            let step = try planner.next(maxFrames: capacity - written)
            if let boundary = step.boundary, let replacement = boundary.change.replacement {
                sources = sources.filter { $0.key == replacement.id }
            }
            if let chunk = step.chunk {
                guard let audio = sources[chunk.source.id],
                      let channels = (chunk.tail ? audio.tail : audio.cycle)?.floatChannelData else {
                    throw AudioQueuePlaybackError.invalidFile
                }
                for offset in 0..<chunk.count {
                    let sourceFrame = chunk.sourceFrame + offset
                    let left = channels[0][sourceFrame], right = channels[1][sourceFrame]
                    guard left.isFinite, right.isFinite else { throw AudioQueuePlaybackError.invalidFile }
                    destination[(written + offset) * 2] = left
                    destination[(written + offset) * 2 + 1] = right
                }
                written += chunk.count
            } else if !step.ended {
                throw AudioQueuePlaybackError.invalidState
            }
            finished = step.ended
        }
        return written
    }

    private static func validate(_ audio: OutputWorkerLoopScheduler.Audio) throws {
        let format = audio.cycle.format
        guard audio.frames > 0,
              format.sampleRate == 48_000, format.channelCount == 2,
              format.commonFormat == .pcmFormatFloat32, !format.isInterleaved,
              audio.cycle.floatChannelData != nil,
              audio.tail == nil || (audio.tail!.format.sampleRate == 48_000 &&
                                    audio.tail!.format.channelCount == 2 &&
                                    audio.tail!.format.commonFormat == .pcmFormatFloat32 &&
                                    !audio.tail!.format.isInterleaved &&
                                    audio.tail!.floatChannelData != nil) else {
            throw AudioQueuePlaybackError.invalidFile
        }
    }
}

/// Finite-song output path independent of AVAudioEngine and the system default.
/// All AudioQueue/file work is serialized on `workQueue`; CoreAudio callbacks only
/// enqueue a refill request. An owning worker must call stop before releasing it.
final class AudioQueuePlaybackBackend: @unchecked Sendable {
    private final class CallbackContext {
        // Assigned once during initialization. Swift's zeroing weak reference
        // handles owner deallocation; stop never writes it from another thread.
        weak var owner: AudioQueuePlaybackBackend?
    }

    private let workQueue = DispatchQueue(label: "circlr.audioqueue-playback")
    private let workQueueKey = DispatchSpecificKey<UInt8>()
    private let source: any AudioQueuePCMSource
    private let selection: OutputDeviceSelection
    private let deviceID: AudioDeviceID
    let outputDevice: OutputDeviceDescriptor
    private let onFinished: @Sendable (Int64) -> Void
    private let onBoundary: (@Sendable (PlaybackLoopSchedule.Boundary) -> Void)?
    private let onFailure: @Sendable (Error) -> Void
    private let context = CallbackContext()
    private var contextRetained = false
    private var audioQueue: AudioQueueRef?
    private var timeline: AudioQueueTimelineRef?
    private var buffers: [AudioQueueBufferRef] = []
    private var inFlight: [AudioQueueBufferRef: Int] = [:]
    private var prepared = false
    private var started = false
    private var stopped = false
    private var playedFrames: Int64 = 0
    private var clockSeconds = 0.0
    private var clockSeen = false
    private var progressWatchdog: AudioQueueProgressWatchdog?
    private var completedPlayback = false

    convenience init(file: AVAudioFile, selection: OutputDeviceSelection,
                     onFinished: @escaping @Sendable () -> Void,
                     onFailure: @escaping @Sendable (Error) -> Void) throws {
        try self.init(source: AudioQueuePCMChunkReader(file: file), selection: selection,
                      onFinished: { _ in onFinished() }, onBoundary: nil, onFailure: onFailure)
    }

    convenience init(loopAudio: OutputWorkerLoopScheduler.Audio, fromFrame: Int,
                     selection: OutputDeviceSelection,
                     onBoundary: @escaping @Sendable (PlaybackLoopSchedule.Boundary) -> Void,
                     onFinished: @escaping @Sendable (Int64) -> Void,
                     onFailure: @escaping @Sendable (Error) -> Void) throws {
        try self.init(source: AudioQueueLoopChunkReader(audio: loopAudio, fromFrame: fromFrame),
                      selection: selection, onFinished: onFinished, onBoundary: onBoundary,
                      onFailure: onFailure)
    }

    private init(source: any AudioQueuePCMSource, selection: OutputDeviceSelection,
                 onFinished: @escaping @Sendable (Int64) -> Void,
                 onBoundary: (@Sendable (PlaybackLoopSchedule.Boundary) -> Void)?,
                 onFailure: @escaping @Sendable (Error) -> Void) throws {
        try selection.validate()
        self.source = source
        self.selection = selection
        let (id, descriptor) = try Self.resolve(selection)
        self.deviceID = id
        self.outputDevice = descriptor
        self.onFinished = onFinished
        self.onBoundary = onBoundary
        self.onFailure = onFailure
        context.owner = self
        workQueue.setSpecific(key: workQueueKey, value: 1)

        var format = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
            mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        let opaqueContext = Unmanaged.passRetained(context).toOpaque()
        contextRetained = true
        let status = AudioQueueNewOutput(&format, { userData, _, buffer in
            guard let userData else { return }
            let context = Unmanaged<CallbackContext>.fromOpaque(userData).takeUnretainedValue()
            guard let owner = context.owner else { return }
            owner.workQueue.async { [weak owner] in owner?.bufferPlayed(buffer) }
        }, opaqueContext, nil, nil, 0, &audioQueue)
        guard status == noErr, let audioQueue else {
            if let audioQueue { _ = AudioQueueDispose(audioQueue, true) }
            self.audioQueue = nil
            releaseContext()
            throw AudioQueuePlaybackError.systemCall("생성", status)
        }
        do {
            // Binding happens before Start, even for systemDefault selection. The
            // selected queue never implicitly follows a later default-device change.
            let uid = descriptor.uid as CFString
            var uidPointer = Unmanaged.passUnretained(uid).toOpaque()
            try Self.check(withExtendedLifetime(uid) {
                AudioQueueSetProperty(audioQueue, kAudioQueueProperty_CurrentDevice,
                                      &uidPointer, UInt32(MemoryLayout<UnsafeMutableRawPointer>.size))
            }, "장치 선택")
            try verifyDevice(on: audioQueue)
            try Self.check(AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, 0), "음소거")
            let bytes = UInt32(AudioQueuePCMChunkReader.framesPerBuffer * 8)
            try Self.check(AudioQueueCreateTimeline(audioQueue, &timeline), "재생 시계 생성")
            // File playback gets about one second for disk stalls. In-memory
            // loops keep the existing eight-buffer (~0.68 s) change latency.
            let bufferCount = source is AudioQueueLoopChunkReader ? 8 : 12
            for _ in 0..<bufferCount {
                var buffer: AudioQueueBufferRef?
                try Self.check(AudioQueueAllocateBuffer(audioQueue, bytes, &buffer), "버퍼 할당")
                guard let buffer else { throw AudioQueuePlaybackError.invalidState }
                buffers.append(buffer)
            }
        } catch {
            if let timeline { _ = AudioQueueDisposeTimeline(audioQueue, timeline) }
            _ = AudioQueueDispose(audioQueue, true)
            self.audioQueue = nil
            releaseContext()
            throw error
        }
    }

    deinit { stop() }

    func startMuted() throws { try prepare(volume: 0); try startPrepared() }

    /// Preferred for real playback: the first audio frame is audible. Device
    /// identity is verified before the queue is started.
    func startAudible() throws { try prepareAudible(); try startPrepared() }

    func prepareAudible() throws { try prepare(volume: 1) }

    private func prepare(volume: Float) throws {
        try workQueue.sync {
            guard !prepared, !started, !stopped, let audioQueue else { throw AudioQueuePlaybackError.invalidState }
            do {
                try verifyDevice(on: audioQueue)
                for buffer in buffers { try enqueue(buffer, on: audioQueue) }
                guard !inFlight.isEmpty else { throw AudioQueuePlaybackError.invalidFile }
                try Self.check(AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, volume), "음량 적용")
                prepared = true
            } catch {
                stopOnWorkQueue()
                throw error
            }
        }
    }

    func startPrepared() throws {
        try workQueue.sync {
            guard prepared, !started, !stopped, let audioQueue else { throw AudioQueuePlaybackError.invalidState }
            do {
                try verifyDevice(on: audioQueue)
                try Self.check(AudioQueueStart(audioQueue, nil), "시작")
                started = true
                try verifyDevice(on: audioQueue)
                progressWatchdog = AudioQueueProgressWatchdog(startedAt: ProcessInfo.processInfo.systemUptime)
            } catch {
                stopOnWorkQueue()
                throw error
            }
        }
    }

    func makeAudible() throws {
        try workQueue.sync {
            guard started, !stopped, let audioQueue else { throw AudioQueuePlaybackError.invalidState }
            try verifyDevice(on: audioQueue)
            try Self.check(AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, 1), "음량 적용")
        }
    }

    func revalidate() throws -> OutputDeviceDescriptor {
        try workQueue.sync {
            guard !stopped, let audioQueue else { throw AudioQueuePlaybackError.invalidState }
            try verifyDevice(on: audioQueue)
            return outputDevice
        }
    }

    var hasCompletedPlayback: Bool { workQueue.sync { completedPlayback } }

    /// Acknowledges a reserved future sample boundary immediately. The change
    /// is rendered only when the producer reaches that not-yet-queued frame.
    func requestLoopChange(id: UUID, audio: OutputWorkerLoopScheduler.Audio?) throws {
        let boundary = try workQueue.sync {
            guard started, !stopped, let loop = source as? AudioQueueLoopChunkReader else {
                throw AudioQueuePlaybackError.invalidState
            }
            return try loop.request(id: id, audio: audio)
        }
        if let onBoundary { DispatchQueue.main.async { onBoundary(boundary) } }
    }

    func checkedSeconds() throws -> Double {
        try workQueue.sync {
            guard let audioQueue, started, !stopped else { return clockSeconds }
            var stamp = AudioTimeStamp()
            var discontinuity = DarwinBoolean(false)
            let status = AudioQueueGetCurrentTime(audioQueue, timeline, &stamp, &discontinuity)
            if clockSeen && discontinuity.boolValue {
                throw AudioQueuePlaybackError.underrun
            }
            try Self.check(status, "재생 시계 조회")
            clockSeen = true
            if stamp.mSampleTime.isFinite, stamp.mSampleTime >= 0 {
                clockSeconds = max(clockSeconds, min(source.maximumClockSeconds ?? .greatestFiniteMagnitude,
                                                      stamp.mSampleTime / 48_000))
            }
            try progressWatchdog?.observe(clockSeconds, at: ProcessInfo.processInfo.systemUptime)
            return clockSeconds
        }
    }

    func stop() {
        // A final weak callback may release the last reference on workQueue.
        // Calling sync from that deinit path would deadlock the helper.
        if DispatchQueue.getSpecific(key: workQueueKey) != nil { stopOnWorkQueue() }
        else { workQueue.sync { stopOnWorkQueue() } }
    }

    private func enqueue(_ buffer: AudioQueueBufferRef, on queue: AudioQueueRef) throws {
        let capacity = Int(buffer.pointee.mAudioDataBytesCapacity) / MemoryLayout<Float>.size
        let audioData = buffer.pointee.mAudioData
        let samples = UnsafeMutableBufferPointer(start: audioData.assumingMemoryBound(to: Float.self), count: capacity)
        let frames = try source.fill(samples)
        guard frames > 0 else { return }
        buffer.pointee.mAudioDataByteSize = UInt32(frames * 8)
        try Self.check(AudioQueueEnqueueBuffer(queue, buffer, 0, nil), "버퍼 추가")
        inFlight[buffer] = frames
    }

    private func bufferPlayed(_ buffer: AudioQueueBufferRef) {
        guard started, !stopped, let audioQueue, let frames = inFlight.removeValue(forKey: buffer) else { return }
        playedFrames += Int64(frames)
        clockSeconds = max(clockSeconds, min(source.maximumClockSeconds ?? .greatestFiniteMagnitude,
                                             Double(playedFrames) / 48_000))
        do {
            // The last queued buffer ended while the file still has content.
            // Treat a real queue starvation as failure, never as successful EOF.
            if inFlight.isEmpty && !source.finished {
                throw AudioQueuePlaybackError.underrun
            }
            try verifyDevice(on: audioQueue)
            try enqueue(buffer, on: audioQueue)
            if inFlight.isEmpty {
                let endFrame = source.submittedFrames
                completedPlayback = true
                stopOnWorkQueue()
                DispatchQueue.main.async { [onFinished] in onFinished(endFrame) }
            }
        } catch {
            stopOnWorkQueue()
            DispatchQueue.main.async { [onFailure] in onFailure(error) }
        }
    }

    private func stopOnWorkQueue() {
        guard !stopped else { return }
        stopped = true
        if let audioQueue {
            // Synchronous disposal waits for callbacks before releasing their context.
            _ = AudioQueueStop(audioQueue, true)
            if let timeline { _ = AudioQueueDisposeTimeline(audioQueue, timeline) }
            _ = AudioQueueDispose(audioQueue, true)
        }
        audioQueue = nil
        timeline = nil
        buffers.removeAll()
        inFlight.removeAll()
        releaseContext()
    }

    private func releaseContext() {
        guard contextRetained else { return }
        contextRetained = false
        Unmanaged<CallbackContext>.passUnretained(context).release()
    }

    private static func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw AudioQueuePlaybackError.systemCall(operation, status) }
    }

    private static func property(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                 scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> UInt32 {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                                 mElement: kAudioObjectPropertyElementMain)
        var result: UInt32 = 0, bytes = UInt32(MemoryLayout<UInt32>.size)
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &bytes, &result), "장치 조회")
        guard bytes == MemoryLayout<UInt32>.size else { throw AudioQueuePlaybackError.changedDevice }
        return result
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var result: Unmanaged<CFString>?
        var bytes = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &bytes, &result), "장치 정보 조회")
        guard bytes == MemoryLayout<Unmanaged<CFString>?>.size, let result else {
            throw AudioQueuePlaybackError.changedDevice
        }
        return result.takeRetainedValue() as String
    }

    private static func resolve(_ selection: OutputDeviceSelection) throws -> (AudioDeviceID, OutputDeviceDescriptor) {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let id: AudioDeviceID
        switch selection {
        case .systemDefault:
            id = try property(system, kAudioHardwarePropertyDefaultOutputDevice)
        case .deviceUID(let requestedUID):
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            let qualifier = requestedUID as CFString
            var pointer = Unmanaged.passUnretained(qualifier).toOpaque()
            var result = AudioDeviceID(kAudioObjectUnknown)
            var bytes = UInt32(MemoryLayout<AudioDeviceID>.size)
            let status = withExtendedLifetime(qualifier) {
                AudioObjectGetPropertyData(system, &address, UInt32(MemoryLayout<UnsafeMutableRawPointer>.size),
                                           &pointer, &bytes, &result)
            }
            try check(status, "장치 식별")
            guard bytes == MemoryLayout<AudioDeviceID>.size else { throw AudioQueuePlaybackError.changedDevice }
            id = result
        }
        guard id != kAudioObjectUnknown,
              try property(id, kAudioDevicePropertyDeviceIsAlive) != 0 else {
            throw AudioQueuePlaybackError.changedDevice
        }
        var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var bytes: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &bytes), "출력 조회")
        guard bytes >= MemoryLayout<AudioStreamID>.size else { throw AudioQueuePlaybackError.changedDevice }
        let descriptor = try OutputDeviceDescriptor(uid: string(id, kAudioDevicePropertyDeviceUID),
                                                    name: string(id, kAudioObjectPropertyName))
        if case .deviceUID(let requestedUID) = selection, descriptor.uid != requestedUID {
            throw AudioQueuePlaybackError.changedDevice
        }
        return (id, descriptor)
    }

    private func verifyDevice(on queue: AudioQueueRef) throws {
        let (currentID, current) = try Self.resolve(selection)
        guard currentID == deviceID, current.uid == outputDevice.uid else {
            throw AudioQueuePlaybackError.changedDevice
        }
        var actual: Unmanaged<CFString>?
        var bytes = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try Self.check(AudioQueueGetProperty(queue, kAudioQueueProperty_CurrentDevice, &actual, &bytes),
                       "장치 적용 확인")
        guard bytes == MemoryLayout<Unmanaged<CFString>?>.size,
              let actual, (actual.takeUnretainedValue() as String) == outputDevice.uid else {
            throw AudioQueuePlaybackError.changedDevice
        }
    }
}
