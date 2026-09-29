import Foundation

public enum SIWCResponsesError: Error, Equatable {
    case invalidRequest, invalidCredential, invalidResponse, invalidUTF8
    case limitExceeded, interruptedStream, incomplete, failed(String), http(Int), network
}

public struct SIWCResponsesModel: Equatable {
    public let slug: String
    public let displayName: String
}

public struct SIWCResponsesFunctionTool {
    public let name: String
    public let description: String
    public let parameters: CodexJSONValue
    public init(name: String, description: String, parameters: CodexJSONValue) {
        self.name = name; self.description = description; self.parameters = parameters
    }
}

/// All conversation state is explicitly supplied by the caller. No server-side history is used.
public struct SIWCResponsesRequest {
    public let model: String
    public let instructions: String
    public let input: [CodexJSONValue]
    public let functions: [SIWCResponsesFunctionTool]
    public init(model: String, instructions: String, input: [CodexJSONValue], functions: [SIWCResponsesFunctionTool] = []) {
        self.model = model; self.instructions = instructions; self.input = input; self.functions = functions
    }
    public func encoded() throws -> Data {
        guard !model.isEmpty, model.utf8.count <= 256, !input.isEmpty, input.count <= 4096,
              functions.count <= 128, Set(functions.map(\.name)).count == functions.count else { throw SIWCResponsesError.invalidRequest }
        for item in input {
            guard item.object != nil else { throw SIWCResponsesError.invalidRequest }
            let type = item["type"]?.string ?? "message"
            guard ["message", "reasoning", "function_call", "function_call_output"].contains(type) else { throw SIWCResponsesError.invalidRequest }
            if type == "message" {
                guard let role = item["role"]?.string, ["user", "assistant", "developer"].contains(role) else { throw SIWCResponsesError.invalidRequest }
            }
        }
        var object: [String: CodexJSONValue] = ["model": .string(model), "instructions": .string(instructions),
            "input": .array(input), "store": .bool(false), "stream": .bool(true),
            "include": .array([.string("reasoning.encrypted_content")])]
        if !functions.isEmpty {
            let tools = try functions.map { function -> CodexJSONValue in
                guard !function.name.isEmpty, function.name.utf8.count <= 64,
                      function.name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }),
                      function.parameters.object != nil else { throw SIWCResponsesError.invalidRequest }
                return .object(["type": .string("function"), "name": .string(function.name),
                    "description": .string(function.description), "parameters": function.parameters, "strict": .bool(true)])
            }
            object["tools"] = .array([.object(["type": .string("namespace"), "name": .string("circlr"),
                "description": .string("Work on the current circlr project through permission-checked commands."), "tools": .array(tools)])])
        }
        let data = try JSONEncoder().encode(CodexJSONValue.object(object))
        guard data.count <= 4 * 1024 * 1024 else { throw SIWCResponsesError.limitExceeded }
        return data
    }
}

public struct SIWCResponsesFunctionCall: Equatable {
    public let callID: String
    public let name: String
    public let arguments: CodexJSONValue
}
public struct SIWCResponsesResult: Equatable {
    public let responseID: String
    /// Append these exact items, then function_call_output items, to the next request's input.
    public let output: [CodexJSONValue]
    public let functionCalls: [SIWCResponsesFunctionCall]
}
public enum SIWCResponsesEvent: Equatable {
    case textDelta(String)
}

/// Transport must stop its underlying request when its consumer task is cancelled.
public protocol SIWCResponsesTransport {
    func perform(_ request: URLRequest, receive: @escaping (Int, String?, Data) async throws -> Void) async throws
}

public final class SIWCResponsesURLSessionTransport: SIWCResponsesTransport, @unchecked Sendable {
    private let session: URLSession
    public convenience init() { self.init(configuration: .ephemeral) }
    internal init(configuration config: URLSessionConfiguration) {
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 600
        session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }
    public func perform(_ request: URLRequest, receive: @escaping (Int, String?, Data) async throws -> Void) async throws {
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse else { throw SIWCResponsesError.invalidResponse }
        try await receive(http.statusCode, http.value(forHTTPHeaderField: "Content-Type"), Data())
        var buffer = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            buffer.append(byte)
            if byte == 10 || buffer.count >= 4096 {
                try await receive(http.statusCode, http.value(forHTTPHeaderField: "Content-Type"), buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty { try await receive(http.statusCode, http.value(forHTTPHeaderField: "Content-Type"), buffer) }
    }
    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
}

public final class SIWCResponsesClient {
    private let transport: SIWCResponsesTransport
    public init(transport: SIWCResponsesTransport = SIWCResponsesURLSessionTransport()) { self.transport = transport }
    private func request(path: String, token: String) throws -> URLRequest {
        guard !token.isEmpty, token.utf8.count <= 32_768,
              token.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }) else { throw SIWCResponsesError.invalidCredential }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/" + path)!)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        return request
    }
    public func models(accessToken: String) async throws -> [SIWCResponsesModel] {
        let request = try request(path: "models", token: accessToken)
        var data = Data()
        do {
            try Task.checkCancellation()
            try await transport.perform(request) { status, _, chunk in
                try Task.checkCancellation()
                guard (200..<300).contains(status) else { throw SIWCResponsesError.http(status) }
                guard data.count + chunk.count <= 2 * 1024 * 1024 else { throw SIWCResponsesError.limitExceeded }
                data.append(chunk)
            }
            try Task.checkCancellation()
            guard let json = try? JSONDecoder().decode(CodexJSONValue.self, from: data),
                  case .array(let entries)? = json["models"] else { throw SIWCResponsesError.invalidResponse }
            var seen = Set<String>()
            return try entries.compactMap { item in
                guard item["visibility"]?.string == "list" else { return nil }
                guard let slug = item["slug"]?.string, !slug.isEmpty, slug.utf8.count <= 256,
                      let name = item["display_name"]?.string, !name.isEmpty,
                      seen.insert(slug).inserted else { throw SIWCResponsesError.invalidResponse }
                return SIWCResponsesModel(slug: slug, displayName: name)
            }
        } catch { throw sanitized(error) }
    }
    public func respond(request input: SIWCResponsesRequest, accessToken: String,
                        onEvent: @escaping (SIWCResponsesEvent) async throws -> Void = { _ in }) async throws -> SIWCResponsesResult {
        var request = try request(path: "responses", token: accessToken)
        request.httpMethod = "POST"; request.httpBody = try input.encoded()
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        var parser = SIWCResponsesStreamParser(allowedFunctions: Set(input.functions.map(\.name)))
        do {
            try Task.checkCancellation()
            try await transport.perform(request) { status, contentType, chunk in
                try Task.checkCancellation()
                guard (200..<300).contains(status) else { throw SIWCResponsesError.http(status) }
                guard contentType?.lowercased().hasPrefix("text/event-stream") == true else { throw SIWCResponsesError.invalidResponse }
                for event in try parser.append(chunk) {
                    try Task.checkCancellation()
                    try await onEvent(event)
                }
            }
            try Task.checkCancellation()
            return try parser.finish()
        } catch { throw sanitized(error) }
    }
    private func sanitized(_ error: Error) -> Error {
        if error is CancellationError || Task.isCancelled { return CancellationError() }
        return (error as? SIWCResponsesError) ?? SIWCResponsesError.network
    }
}
