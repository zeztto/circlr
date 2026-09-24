import Foundation
import Darwin

// Private, app-owned stdio MCP bridge. The first stdin line is a one-use
// bootstrap, never an MCP message or a model-visible tool argument.
private enum Bridge {
    static let maxBootstrap = 4096
    static let maxFrame = 1_048_576
    static let methods: Set<String> = ["snapshot", "inspect", "apply", "bounce", "job"]
    static var input = Data()

    static func line(limit: Int) throws -> Data? {
        while true {
            if let end = input.firstIndex(of: 10) {
                let frame = Data(input[..<end])
                input.removeSubrange(...end)
                guard frame.count <= limit else { throw Failure.frame }
                return frame
            }
            guard input.count <= limit else { throw Failure.frame }
            var bytes = [UInt8](repeating: 0, count: 4096)
            let count = Darwin.read(STDIN_FILENO, &bytes, bytes.count)
            if count == 0 { return nil }
            guard count > 0 else { throw Failure.io }
            input.append(contentsOf: bytes.prefix(count))
        }
    }

    static func write(_ object: [String: Any]) throws {
        guard JSONSerialization.isValidJSONObject(object) else { throw Failure.frame }
        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard payload.count <= maxFrame else { throw Failure.frame }
        var packet = payload
        packet.append(10)
        try packet.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = Darwin.write(STDOUT_FILENO, raw.baseAddress! + offset, raw.count - offset)
                guard n > 0 else { throw Failure.io }
                offset += n
            }
        }
    }

    struct Bootstrap {
        let socket: String
        let capability: String
        init(_ data: Data) throws {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(object.keys) == ["version", "socket", "capability", "parentPID"],
                  object["version"] as? Int == 1,
                  object["parentPID"] as? Int32 == getppid(),
                  let socket = object["socket"] as? String,
                  let capability = object["capability"] as? String,
                  capability.count == 64,
                  capability.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  socket.utf8.count < 104,
                  URL(fileURLWithPath: socket).lastPathComponent.range(
                    of: #"^\.t[0-9a-f]{8}$"#, options: .regularExpression) != nil else {
                throw Failure.bootstrap
            }
            var info = stat()
            guard Darwin.lstat(socket, &info) == 0,
                  info.st_mode & mode_t(S_IFMT) == mode_t(S_IFSOCK),
                  info.st_uid == getuid() else { throw Failure.bootstrap }
            self.socket = socket
            self.capability = capability
        }
    }

    enum Failure: Error { case bootstrap, frame, io, socket, protocolViolation }

    static func socketReply(_ request: [String: Any], bootstrap: Bootstrap) throws -> [String: Any] {
        let packet = try JSONSerialization.data(withJSONObject: [
            "capability": bootstrap.capability, "request": request
        ], options: [.sortedKeys])
        guard packet.count < maxFrame else { throw Failure.frame }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.socket }
        defer { Darwin.close(fd) }
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let pathBytes = Array(bootstrap.socket.utf8) + [0]
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw Failure.socket }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: pathBytes) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw Failure.socket }
        var peerUID: uid_t = 0
        var peerGID: gid_t = 0
        guard getpeereid(fd, &peerUID, &peerGID) == 0, peerUID == getuid() else { throw Failure.socket }
        var peerPID: pid_t = 0
        var peerPIDSize = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &peerPID, &peerPIDSize) == 0,
              peerPIDSize == MemoryLayout<pid_t>.size,
              peerPID == getppid() else { throw Failure.socket }
        let outbound = packet + Data([10])
        try outbound.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset)
                guard n > 0 else { throw Failure.socket }
                offset += n
            }
        }
        var response = Data()
        var bytes = [UInt8](repeating: 0, count: 8192)
        while response.count <= maxFrame {
            let n = Darwin.read(fd, &bytes, bytes.count)
            guard n > 0 else { throw Failure.socket }
            response.append(contentsOf: bytes.prefix(n))
            if let end = response.firstIndex(of: 10) {
                guard end <= maxFrame,
                      let result = try JSONSerialization.jsonObject(with: response[..<end]) as? [String: Any],
                      Set(result.keys).isSubset(of: ["ok", "result", "error"]),
                      result["ok"] is Bool else { throw Failure.protocolViolation }
                return result
            }
        }
        throw Failure.frame
    }

    static func hasForbiddenKey(_ value: Any) -> Bool {
        if let fields = value as? [String: Any] {
            if fields.keys.contains(where: { ["path", "socket", "capability", "destination"].contains($0) }) {
                return true
            }
            return fields.values.contains(where: hasForbiddenKey)
        }
        if let values = value as? [Any] { return values.contains(where: hasForbiddenKey) }
        return false
    }

    static func tool(_ name: String) -> [String: Any] {
        ["name": "circlr_\(name)",
         "description": "App-scoped \(name) for the selected circlr turn. Pass an AgentRequest with an observed revision; paths and credentials are never tool arguments.",
         "inputSchema": ["type": "object", "properties": ["request": ["type": "object"]],
                         "required": ["request"], "additionalProperties": false]]
    }

    static func respond(_ call: [String: Any], bootstrap: Bootstrap) -> [String: Any]? {
        guard call["jsonrpc"] as? String == "2.0",
              let method = call["method"] as? String,
              method.utf8.count <= 128 else { return error(id: nil, code: -32600) }
        if method == "notifications/initialized" { return nil }
        let id = call["id"]
        let validID = (id as? String).map { $0.utf8.count <= 128 } ?? (id is Int)
        guard validID, !hasForbiddenKey(call) else {
            return error(id: nil, code: -32600)
        }
        switch method {
        case "initialize":
            return success(id: id, result: ["protocolVersion": "2025-06-18",
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "circlr-trusted-internal", "version": "1"]])
        case "tools/list":
            return success(id: id, result: ["tools": methods.sorted().map(tool)])
        case "tools/call":
            guard let params = call["params"] as? [String: Any],
                  Set(params.keys) == ["name", "arguments"],
                  let name = params["name"] as? String,
                  let requestedMethod = methods.first(where: { name == "circlr_\($0)" }),
                  let args = params["arguments"] as? [String: Any],
                  Set(args.keys) == ["request"],
                  let request = args["request"] as? [String: Any],
                  request["method"] as? String == requestedMethod,
                  request["id"] is String else {
                return error(id: id, code: -32602)
            }
            do {
                let reply = try socketReply(request, bootstrap: bootstrap)
                if reply["ok"] as? Bool == true, let result = reply["result"] as? [String: Any] {
                    guard let size = try? JSONSerialization.data(withJSONObject: result).count,
                          size <= maxFrame - 4096 else {
                        return success(id: id, result: ["content": [["type": "text",
                            "text": "trusted_run_result_too_large"]], "isError": true])
                    }
                    return success(id: id, result: ["structuredContent": result,
                        "content": [["type": "text", "text": "circlr \(requestedMethod) 완료"]],
                        "isError": false])
                }
                return success(id: id, result: ["content": [["type": "text",
                    "text": "trusted_run_rejected"]], "isError": true])
            } catch {
                return success(id: id, result: ["content": [["type": "text",
                    "text": "trusted_run_unavailable"]], "isError": true])
            }
        default: return error(id: id, code: -32601)
        }
    }

    static func success(id: Any?, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
    }
    static func error(id: Any?, code: Int) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(),
         "error": ["code": code, "message": "trusted_mcp_invalid_request"]]
    }

    static func run() throws {
        guard let first = try line(limit: maxBootstrap) else { throw Failure.bootstrap }
        let bootstrap = try Bootstrap(first)
        while let frame = try line(limit: maxFrame) {
            guard let call = try? JSONSerialization.jsonObject(with: frame) as? [String: Any] else {
                try write(error(id: nil, code: -32700))
                continue
            }
            if let response = respond(call, bootstrap: bootstrap) { try write(response) }
        }
    }
}

// Deliberately quiet: no credentials, paths, or project data go to stderr.
do { try Bridge.run() } catch { exit(1) }
