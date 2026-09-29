import Foundation

public enum SIWCResponsesError: Error, Equatable {
    case invalidRequest, invalidCredential, invalidResponse, invalidUTF8
    case limitExceeded, interruptedStream, incomplete, failed(String), http(Int), network
    case provider(code: SIWCResponsesProviderCode, status: Int)
    case requestRejected(code: String?, parameter: String?, status: Int)
}

/// Only documented codes cross the transport boundary; diagnostic text never does.
public enum SIWCResponsesProviderCode: String, Equatable {
    case userNotEligible = "subscription_sharing_user_not_eligible"
    case usageLimitExceeded = "subscription_sharing_usage_limit_exceeded"
    case usageUnavailable = "subscription_sharing_usage_unavailable"
    case unsupportedCapability = "subscription_sharing_unsupported_capability"
    case routeNotSupported = "subscription_sharing_route_not_supported"
    case invalidUser = "subscription_sharing_invalid_user"
    case scopeNotAuthorized = "chatpass_v2_scope_not_authorized"
    case invalidAuthorizationContext = "chatpass_v2_invalid_authorization_context"
    case userUnavailable = "subscription_sharing_user_unavailable"
}

/// A non-success status is terminal even when the body is truncated or the transport fails.
private struct SIWCHTTPFailure {
    private var status: Int?
    private var body = Data()
    private static let maximumBytes = 16 * 1024

    mutating func receive(status incoming: Int, chunk: Data) throws -> Bool {
        if status == nil {
            guard !(200..<300).contains(incoming) else { return false }
            status = incoming
        }
        guard incoming == status else { throw error! }
        guard chunk.count <= Self.maximumBytes - body.count else {
            // A truncated prefix must never be interpreted as a complete provider error.
            body.removeAll(keepingCapacity: false)
            throw error!
        }
        body.append(chunk)
        return true
    }

    var error: SIWCResponsesError? {
        guard let status else { return nil }
        if let object = try? JSONDecoder().decode(CodexJSONValue.self, from: body),
           let fields = object["error"]?.object {
            if let raw = fields["code"]?.string, let code = SIWCResponsesProviderCode(rawValue: raw) {
                return .provider(code: code, status: status)
            }
            let code = Self.identifier(fields["code"]?.string, parameter: false)
            let parameter = Self.identifier(fields["param"]?.string, parameter: true)
            if code != nil || parameter != nil {
                return .requestRejected(code: code, parameter: parameter, status: status)
            }
        }
        return .http(status)
    }

    /// Admit only bounded machine identifiers, never free-form diagnostic text.
    private static func identifier(_ value: String?, parameter: Bool) -> String? {
        guard let value, !value.isEmpty, value.utf8.count <= 96,
              let first = value.utf8.first, (97...122).contains(first) else { return nil }
        let valid = value.utf8.allSatisfy { byte in
            (97...122).contains(byte) || (48...57).contains(byte) || byte == 95 ||
                (parameter && (byte == 46 || byte == 91 || byte == 93))
        }
        return valid ? value : nil
    }
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
        guard let http = response as? HTTPURLResponse else { throw SIWCResponsesError.failed("transport_non_http_response") }
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
        var failure = SIWCHTTPFailure()
        do {
            try Task.checkCancellation()
            try await transport.perform(request) { status, _, chunk in
                try Task.checkCancellation()
                if try failure.receive(status: status, chunk: chunk) { return }
                guard data.count + chunk.count <= 2 * 1024 * 1024 else { throw SIWCResponsesError.limitExceeded }
                data.append(chunk)
            }
            try Task.checkCancellation()
            if let error = failure.error { throw error }
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
        } catch { throw sanitized(error, failure: failure.error) }
    }
    public func respond(request input: SIWCResponsesRequest, accessToken: String,
                        onEvent: @escaping (SIWCResponsesEvent) async throws -> Void = { _ in }) async throws -> SIWCResponsesResult {
        var request = try request(path: "responses", token: accessToken)
        request.httpMethod = "POST"; request.httpBody = try input.encoded()
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        var parser = SIWCResponsesStreamParser(allowedFunctions: Set(input.functions.map(\.name)))
        var failure = SIWCHTTPFailure()
        do {
            try Task.checkCancellation()
            try await transport.perform(request) { status, contentType, chunk in
                try Task.checkCancellation()
                if try failure.receive(status: status, chunk: chunk) { return }
                let mediaType = contentType?.split(separator: ";", maxSplits: 1).first?
                    .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                // Some direct-route responses omit Content-Type. The bounded SSE parser
                // still requires a valid terminal event before accepting any result.
                guard contentType == nil || mediaType == "text/event-stream" else {
                    let category: String
                    switch mediaType {
                    case nil, "": category = "missing"
                    case "application/json": category = "json"
                    case "text/html": category = "html"
                    default: category = "other"
                    }
                    throw SIWCResponsesError.failed("response_content_type_" + category)
                }
                for event in try parser.append(chunk) {
                    try Task.checkCancellation()
                    try await onEvent(event)
                }
            }
            try Task.checkCancellation()
            if let error = failure.error { throw error }
            return try parser.finish()
        } catch { throw sanitized(error, failure: failure.error) }
    }
    private func sanitized(_ error: Error, failure: SIWCResponsesError?) -> Error {
        if error is CancellationError || Task.isCancelled { return CancellationError() }
        if let failure { return failure }
        return (error as? SIWCResponsesError) ?? SIWCResponsesError.network
    }
}
