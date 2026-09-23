// Standalone App-target smoke test:
// xcrun swiftc Sources/CirclrApp/AgentSocket.swift Tests/AgentSocketSafetySmoke.swift -o /tmp/circlr-agent-socket-safety && /tmp/circlr-agent-socket-safety
import Foundation
import Darwin

@main struct AgentSocketSafetySmoke {
    private struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
    }
    private static func identity(_ path: String) throws -> Identity {
        var info = stat()
        guard Darwin.lstat(path, &info) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        return Identity(device: info.st_dev, inode: info.st_ino)
    }
    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw NSError(domain: "AgentSocketSafetySmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    private static func requireRejected(_ message: String, _ action: () throws -> Void) throws {
        var rejected = false
        do { try action() } catch { rejected = true }
        try require(rejected, message)
    }
    private static func bindWithoutListen(at path: String) throws -> Int32 {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8) + [0]
        try require(bytes.count <= MemoryLayout.size(ofValue: address.sun_path), "socket path too long")
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let failure = errno
            Darwin.close(descriptor)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(failure))
        }
        return descriptor
    }
    static func main() throws {
        let root = URL(fileURLWithPath: "/tmp/circlr-as-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let activeDirectory = root.appendingPathComponent("active", isDirectory: true)
        var active: AgentSocket? = try AgentSocket(directory: activeDirectory) { _, _ in }
        let activePath = active!.path
        let activeIdentity = try identity(activePath)
        try requireRejected("active listener was accepted") {
            _ = try AgentSocket(directory: activeDirectory) { _, _ in }
        }
        try require(try identity(activePath) == activeIdentity, "active listener path was removed")

        let unlistenedDirectory = root.appendingPathComponent("unlistened", isDirectory: true)
        try FileManager.default.createDirectory(at: unlistenedDirectory, withIntermediateDirectories: true)
        let unlistenedPath = unlistenedDirectory.appendingPathComponent("agent.sock").path
        let unlistenedDescriptor = try bindWithoutListen(at: unlistenedPath)
        let unlistenedIdentity = try identity(unlistenedPath)
        try requireRejected("bound but unlistened socket was accepted") {
            _ = try AgentSocket(directory: unlistenedDirectory) { _, _ in }
        }
        try require(try identity(unlistenedPath) == unlistenedIdentity, "live bind-only path was removed")
        Darwin.close(unlistenedDescriptor)
        try requireRejected("stale path was removed without explicit repair") {
            _ = try AgentSocket(directory: unlistenedDirectory) { _, _ in }
        }
        try require(try identity(unlistenedPath) == unlistenedIdentity, "stale path was automatically removed")

        // The public name may appear after an initial absence check. Publishing
        // the private socket must fail atomically without replacing that owner.
        let publishDirectory = root.appendingPathComponent("publish", isDirectory: true)
        try FileManager.default.createDirectory(at: publishDirectory, withIntermediateDirectories: true)
        let privatePath = publishDirectory.appendingPathComponent(".a12345678").path
        let publicPath = publishDirectory.appendingPathComponent("agent.sock").path
        let privateDescriptor = try bindWithoutListen(at: privatePath)
        let publicDescriptor = try bindWithoutListen(at: publicPath)
        let privateIdentity = try identity(privatePath)
        let publicIdentity = try identity(publicPath)
        try require(renamex_np(privatePath, publicPath, UInt32(RENAME_EXCL)) == -1 && errno == EEXIST,
                    "exclusive socket publication replaced a competing owner")
        try require(try identity(privatePath) == privateIdentity, "failed publication removed private socket")
        try require(try identity(publicPath) == publicIdentity, "failed publication replaced public socket")
        Darwin.close(privateDescriptor)
        Darwin.close(publicDescriptor)

        // A late deinit must not unlink a replacement socket owned by another instance.
        try require(Darwin.unlink(activePath) == 0, "could not simulate path replacement")
        let replacement = try AgentSocket(directory: activeDirectory) { _, _ in }
        let replacementIdentity = try identity(activePath)
        active = nil
        try require(try identity(activePath) == replacementIdentity, "old deinit removed replacement")
        withExtendedLifetime(replacement) {}
        let shutdownDirectory = root.appendingPathComponent("shutdown", isDirectory: true)
        var shutdown: AgentSocket? = try AgentSocket(directory: shutdownDirectory) { _, _ in }
        let shutdownPath = shutdown!.path
        try require(FileManager.default.fileExists(atPath: shutdownPath), "shutdown socket missing")
        let unpublished = try FileManager.default.contentsOfDirectory(atPath: shutdownDirectory.path)
            .filter { $0.hasPrefix(".a") }
        try require(unpublished.isEmpty, "private socket path remained after publication")
        shutdown = nil
        try require(!FileManager.default.fileExists(atPath: shutdownPath), "explicit shutdown left socket path")
        print("AgentSocket active, bind-only, stale, exclusive publish, and deinit safety PASS")
    }
}
