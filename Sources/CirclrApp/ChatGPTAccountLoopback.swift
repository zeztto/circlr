import Foundation
import Network

/// Owns only this sign-in's loopback socket. No browser response contains credentials.
@MainActor
protocol ChatGPTAccountCallbackListening: AnyObject {
    var validateCallback: ((URL) -> Bool)? { get set }
    func start() async throws -> URL
    func callback() async throws -> URL
    func cancel()
}

enum ChatGPTAccountCallbackError: Error, Equatable {
    case cancelled, timedOut, unavailable, invalidRequest
}

@MainActor
final class ChatGPTAccountLoopbackListener: ChatGPTAccountCallbackListening {
    var validateCallback: ((URL) -> Bool)?
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var requestTimers: [UUID: Task<Void, Never>] = [:]
    private var ready: CheckedContinuation<URL, Error>?
    private var pending: CheckedContinuation<URL, Error>?
    private var result: Result<URL, Error>?
    private var redirect: URL?
    private var deadline: Task<Void, Never>?
    private var accepted = 0
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 180) { self.timeout = timeout }

    func start() async throws -> URL {
        guard listener == nil, result == nil else { throw ChatGPTAccountCallbackError.unavailable }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let socket = try NWListener(using: parameters)
        listener = socket
        socket.stateUpdateHandler = { [weak self, weak socket] state in
            Task { @MainActor in
                guard let self, let socket, self.listener === socket else { return }
                switch state {
                case .ready:
                    guard let port = socket.port,
                          let url = URL(string: "http://127.0.0.1:\(port.rawValue)/auth/callback") else {
                        self.finish(.failure(ChatGPTAccountCallbackError.unavailable)); return
                    }
                    self.redirect = url
                    self.ready?.resume(returning: url); self.ready = nil
                case .failed: self.finish(.failure(ChatGPTAccountCallbackError.unavailable))
                default: break
                }
            }
        }
        socket.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        deadline = Task { [weak self, timeout] in
            do { try await Task.sleep(nanoseconds: UInt64(max(0.01, timeout) * 1_000_000_000)) }
            catch { return }
            self?.finish(.failure(ChatGPTAccountCallbackError.timedOut))
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                ready = continuation
                socket.start(queue: .main)
            }
        } onCancel: { Task { @MainActor [weak self] in self?.cancel() } }
    }

    func callback() async throws -> URL {
        if let result { return try result.get() }
        guard listener != nil, pending == nil else { throw ChatGPTAccountCallbackError.unavailable }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { pending = $0 }
        } onCancel: { Task { @MainActor [weak self] in self?.cancel() } }
    }

    func cancel() { finish(.failure(ChatGPTAccountCallbackError.cancelled)) }

    private func accept(_ connection: NWConnection) {
        guard result == nil, accepted < 8 else { connection.cancel(); return }
        accepted += 1
        let id = UUID()
        connections[id] = connection
        connection.start(queue: .main)
        requestTimers[id] = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            self?.close(id)
        }
        receive(id, data: Data())
    }

    private func receive(_ id: UUID, data: Data) {
        guard let connection = connections[id] else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8193 - data.count) { [weak self] bytes, _, complete, error in
            Task { @MainActor in
                guard let self, self.connections[id] != nil else { return }
                var buffer = data
                if let bytes { buffer.append(bytes) }
                guard buffer.count <= 8192 else { self.reply(id, success: false); return }
                if buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
                    guard let redirect = self.redirect,
                          let url = Self.parseRequest(buffer, redirect: redirect),
                          self.validateCallback?(url) ?? true else {
                        self.reply(id, success: false); return
                    }
                    self.reply(id, success: true)
                    // Stop accepting immediately; keep only this response until its write completes.
                    self.finish(.success(url), preserving: id)
                } else if complete || error != nil { self.close(id) }
                else { self.receive(id, data: buffer) }
            }
        }
    }

    static func parseRequest(_ data: Data, redirect: URL) -> URL? {
        guard data.count <= 8192, let text = String(data: data, encoding: .utf8),
              let line = text.components(separatedBy: "\r\n").first else { return nil }
        let fields = line.split(separator: " ", omittingEmptySubsequences: false)
        guard fields.count == 3, fields[0] == "GET", fields[2] == "HTTP/1.1",
              fields[1].hasPrefix("/auth/callback?"), !fields[1].contains("#"),
              let base = URLComponents(url: redirect, resolvingAgainstBaseURL: false),
              let url = URL(string: "http://127.0.0.1:\(base.port ?? 0)\(fields[1])"),
              url.path == "/auth/callback", url.user == nil, url.password == nil else { return nil }
        let parts = text.components(separatedBy: "\r\n\r\n")
        guard parts.count == 2, parts[1].isEmpty else { return nil }
        let headers = parts[0].components(separatedBy: "\r\n").dropFirst()
        guard !headers.contains(where: { $0.lowercased().hasPrefix("content-length:") || $0.lowercased().hasPrefix("transfer-encoding:") }) else { return nil }
        let hosts = text.components(separatedBy: "\r\n").dropFirst().filter { $0.lowercased().hasPrefix("host:") }
        guard hosts.count == 1,
              hosts[0].dropFirst(5).trimmingCharacters(in: .whitespaces) == "127.0.0.1:\(base.port ?? 0)" else { return nil }
        return url
    }

    private func reply(_ id: UUID, success: Bool) {
        guard let connection = connections[id] else { return }
        let body = success ? "로그인 응답을 받았습니다. 써클러에서 결과를 확인하세요." : "유효하지 않은 로그인 요청입니다. 써클러로 돌아가세요."
        let response = "HTTP/1.1 \(success ? "200 OK" : "400 Bad Request")\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'none'\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in self?.close(id) }
        })
    }

    private func close(_ id: UUID) {
        requestTimers.removeValue(forKey: id)?.cancel()
        connections.removeValue(forKey: id)?.cancel()
    }

    private func finish(_ outcome: Result<URL, Error>, preserving: UUID? = nil) {
        guard result == nil else { return }
        result = outcome
        deadline?.cancel(); deadline = nil
        listener?.cancel(); listener = nil
        for id in Array(connections.keys) where id != preserving { close(id) }
        if let ready { ready.resume(with: outcome); self.ready = nil }
        pending?.resume(with: outcome); pending = nil
    }
}
