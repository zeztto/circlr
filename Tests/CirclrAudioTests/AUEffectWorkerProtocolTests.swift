import XCTest
import AudioToolbox
import CirclrCore
@testable import CirclrAudio

/// File-only worker boundary tests. No helper launch, AU instantiation, or device access.
final class AUEffectWorkerProtocolTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }
    private func descriptor(type: UInt32 = kAudioUnitType_Effect, state: Data? = nil) -> PluginDescriptor {
        PluginDescriptor(name: "Offline contract", type: type, subtype: 0, manufacturer: 0, state: state)
    }
    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func caf(frames: Int = 4, rate: Double = 48_000, channels: UInt32 = 2,
                     floating: Bool = true, sample: Float = 0) -> Data {
        var bytes = Data()
        func big<T: FixedWidthInteger>(_ value: T) {
            var v = value.bigEndian
            withUnsafeBytes(of: &v) { bytes.append(contentsOf: $0) }
        }
        bytes.append(Data("caff".utf8)); big(UInt16(1)); big(UInt16(0))
        bytes.append(Data("desc".utf8)); big(UInt64(32)); big(rate.bitPattern)
        bytes.append(Data("lpcm".utf8)); big(UInt32(floating ? 3 : 2))
        big(channels * 4); big(UInt32(1)); big(channels); big(UInt32(32))
        bytes.append(Data("data".utf8)); big(UInt64(4 + frames * Int(channels) * 4)); big(UInt32(0))
        for _ in 0..<(frames * Int(channels)) {
            var v = sample.bitPattern.littleEndian
            withUnsafeBytes(of: &v) { bytes.append(contentsOf: $0) }
        }
        return bytes
    }

    func testEffectRequestsRoundTripAndRejectDifferentSession() throws {
        for type in [kAudioUnitType_Effect, kAudioUnitType_MusicEffect] {
            let dir = try directory(), session = UUID()
            let state = try PropertyListSerialization.data(fromPropertyList: ["gain": 0.25], format: .binary, options: 0)
            let request = AUEffectWorkerRequest(session: session, descriptor: descriptor(type: type, state: state), frames: 8)
            try AUEffectWorkerFiles.writeRequest(request, to: dir)
            XCTAssertEqual(try AUEffectWorkerFiles.readRequest(in: dir, session: session), request)
            XCTAssertThrowsError(try AUEffectWorkerFiles.readRequest(in: dir, session: UUID()))
            let original = try Data(contentsOf: dir.appendingPathComponent("request.json"))
            XCTAssertThrowsError(try AUEffectWorkerFiles.writeRequest(request, to: dir))
            XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("request.json")), original)
        }
    }

    func testRequestRejectsUnsupportedDescriptorStateVersionAndFrameBounds() throws {
        let session = UUID()
        for frames in [0, -1, AUEffectWorkerFiles.maximumFrames + 1] {
            XCTAssertThrowsError(try AUEffectWorkerFiles.validate(.init(session: session, descriptor: descriptor(), frames: frames)))
        }
        for type in [kAudioUnitType_MusicDevice, kAudioUnitType_Output, UInt32(0)] {
            XCTAssertThrowsError(try AUEffectWorkerFiles.validate(.init(session: session, descriptor: descriptor(type: type), frames: 1)))
        }
        let array = try PropertyListSerialization.data(fromPropertyList: ["not", "dictionary"], format: .binary, options: 0)
        for state in [Data(), Data("invalid plist".utf8), array, Data(repeating: 0, count: AUEffectWorkerFiles.maximumStateBytes + 1)] {
            XCTAssertThrowsError(try AUEffectWorkerFiles.validate(.init(session: session, descriptor: descriptor(state: state), frames: 1)))
        }
        var named = descriptor(); named.name = String(repeating: "가", count: 342)
        XCTAssertThrowsError(try AUEffectWorkerFiles.validate(.init(session: session, descriptor: named, frames: 1)))
        var version = AUEffectWorkerRequest(session: session, descriptor: descriptor(), frames: 1); version.version = 2
        XCTAssertThrowsError(try AUEffectWorkerFiles.validate(version))
        // Descriptor-only checks preserve long-render compatibility without allocating PCM.
        XCTAssertEqual(AUEffectWorkerFiles.maximumFrames, 268_435_456)
        XCTAssertNoThrow(try AUEffectWorkerFiles.validate(.init(session: session, descriptor: descriptor(), frames: 48_000 * 60 * 11)))
        XCTAssertNoThrow(try AUEffectWorkerFiles.validate(.init(session: session, descriptor: descriptor(), frames: AUEffectWorkerFiles.maximumFrames)))
    }

    func testRequestRejectsOversizedAndMalformedFiles() throws {
        for bytes in [Data(repeating: 32, count: AUEffectWorkerFiles.maximumRequestBytes + 1), Data("{".utf8), Data("[]".utf8)] {
            let dir = try directory()
            try write(bytes, to: dir.appendingPathComponent("request.json"))
            XCTAssertThrowsError(try AUEffectWorkerFiles.readRequest(in: dir, session: UUID()))
        }
    }

    func testPCMInputRoundTripPreservesBothChannels() throws {
        let dir = try directory()
        var pcm = PCM(frames: 4101)
        pcm.left[0] = 0.25; pcm.right[4096] = -0.5; pcm.left[4100] = 0.125
        try AUEffectWorkerFiles.writeInput(pcm, to: dir)
        let decoded = try AUEffectWorkerFiles.readPCM(at: dir.appendingPathComponent("input.caf"), frames: pcm.count)
        XCTAssertEqual(decoded.left, pcm.left); XCTAssertEqual(decoded.right, pcm.right)
        XCTAssertThrowsError(try AUEffectWorkerFiles.readPCM(at: dir.appendingPathComponent("input.caf"), frames: pcm.count - 1))
    }

    func testInputRejectsMismatchedEmptyAndNonfinitePCM() throws {
        var mismatch = PCM(frames: 2); mismatch.right.removeLast()
        var nan = PCM(frames: 2); nan.left[1] = .nan
        var infinity = PCM(frames: 2); infinity.right[0] = .infinity
        for pcm in [PCM(frames: 0), mismatch, nan, infinity] {
            let dir = try directory()
            XCTAssertThrowsError(try AUEffectWorkerFiles.writeInput(pcm, to: dir))
            XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("result.json").path))
        }
    }

    func testCAFRejectsRateChannelsIntegerEncodingAndNonfiniteSamples() throws {
        for bytes in [caf(rate: 44_100), caf(channels: 1), caf(floating: false), caf(sample: .nan), caf(sample: -.infinity)] {
            let url = try directory().appendingPathComponent("input.caf")
            try write(bytes, to: url)
            XCTAssertThrowsError(try AUEffectWorkerFiles.readPCM(at: url, frames: 4))
        }
        let valid = try directory().appendingPathComponent("valid.caf")
        try write(caf(sample: 0.25), to: valid)
        XCTAssertEqual(try AUEffectWorkerFiles.readPCM(at: valid, frames: 4).left, [Float](repeating: 0.25, count: 4))
    }

    func testCAFRejectsTruncationWrongMagicAndSizeBounds() throws {
        for bytes in [Data(caf().prefix(3)), Data(caf().dropLast(1)), Data("RIFF".utf8) + caf().dropFirst(4), caf() + Data(repeating: 0, count: 65537)] {
            let url = try directory().appendingPathComponent("input.caf")
            try write(bytes, to: url)
            XCTAssertThrowsError(try AUEffectWorkerFiles.readPCM(at: url, frames: 4))
        }
        let missing = try directory().appendingPathComponent("missing.caf")
        for frames in [0, -1, AUEffectWorkerFiles.maximumFrames + 1] {
            XCTAssertThrowsError(try AUEffectWorkerFiles.readPCM(at: missing, frames: frames))
        }
    }

    func testResultValidatesIdentityVersionFrameCountAndJSONTypes() throws {
        let session = UUID()
        let patches: [[String: Any]] = [["session": UUID().uuidString], ["version": 2], ["frames": 5], ["frames": "4"], ["version": "1"]]
        for patch in patches {
            let dir = try directory()
            try write(caf(), to: dir.appendingPathComponent("result.caf"))
            var object: [String: Any] = ["version": 1, "session": session.uuidString, "frames": 4]
            object.merge(patch) { _, new in new }
            try write(JSONSerialization.data(withJSONObject: object), to: dir.appendingPathComponent("result.json"))
            XCTAssertThrowsError(try AUEffectWorkerFiles.readResult(in: dir, session: session, frames: 4))
        }
        let dir = try directory()
        try write(Data(repeating: 32, count: 1025), to: dir.appendingPathComponent("result.json"))
        XCTAssertThrowsError(try AUEffectWorkerFiles.readResult(in: dir, session: session, frames: 4))
    }

    func testPublishedResultIsCompleteAndCannotOverwriteExistingResult() throws {
        let dir = try directory(), session = UUID()
        var pcm = PCM(frames: 8); pcm.left[3] = 0.75
        try AUEffectWorkerFiles.publishResult(pcm, session: session, in: dir)
        XCTAssertEqual(try AUEffectWorkerFiles.readResult(in: dir, session: session, frames: 8).left, pcm.left)
        let original = try Data(contentsOf: dir.appendingPathComponent("result.caf"))
        XCTAssertThrowsError(try AUEffectWorkerFiles.publishResult(PCM(frames: 8), session: session, in: dir))
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("result.caf")), original)
    }

    func testSymlinkHardlinkAndPublicPermissionsAreRejected() throws {
        let dir = try directory(), real = dir.appendingPathComponent("real.caf"), alias = dir.appendingPathComponent("input.caf")
        try write(caf(), to: real)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
        XCTAssertThrowsError(try AUEffectWorkerFiles.readPCM(at: alias, frames: 4))
        try FileManager.default.removeItem(at: alias)
        try FileManager.default.linkItem(at: real, to: alias)
        XCTAssertThrowsError(try AUEffectWorkerFiles.readPCM(at: alias, frames: 4))
        try FileManager.default.removeItem(at: alias)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: real.path)
        XCTAssertThrowsError(try AUEffectWorkerFiles.readPCM(at: real, frames: 4))
        let linkDir = try directory().appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: linkDir, withDestinationURL: dir)
        XCTAssertThrowsError(try AUEffectWorkerFiles.validateDirectory(linkDir))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        XCTAssertThrowsError(try AUEffectWorkerFiles.validateDirectory(dir))
    }
}
