import Foundation

/// The app-server wire omits JSON-RPC's `jsonrpc` member. This codec is deliberately
/// separate from circlr's MCP codec and has no knowledge of account credentials.
public enum CodexJSONValue: Codable, Equatable {
    case object([String: CodexJSONValue])
    case array([CodexJSONValue])
    case string(String)
    case integer(Int)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int.self) { self = .integer(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: CodexJSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([CodexJSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public subscript(_ key: String) -> CodexJSONValue? {
        guard case .object(let value) = self else { return nil }
        return value[key]
    }

    public var string: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var object: [String: CodexJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }
}

public enum CodexRPCID: Hashable, Equatable {
    case integer(Int)
    case string(String)

    var json: CodexJSONValue {
        switch self {
        case .integer(let value): return .integer(value)
        case .string(let value): return .string(value)
        }
    }

    init?(_ json: CodexJSONValue) {
        switch json {
        case .integer(let value): self = .integer(value)
        case .string(let value) where !value.isEmpty: self = .string(value)
        default: return nil
        }
    }
}

/// Client and server IDs occupy different Swift types even if their wire values match.
public struct CodexClientRequestID: Hashable, Equatable {
    public let value: CodexRPCID
    public init(_ value: Int) { self.value = .integer(value) }
    init(_ value: CodexRPCID) { self.value = value }
}

public struct CodexServerRequestID: Hashable, Equatable {
    public let value: CodexRPCID
    init(_ value: CodexRPCID) { self.value = value }
}

public struct CodexRPCError: Equatable {
    public let code: Int
    public let message: String

    init?(json: CodexJSONValue) {
        guard case .integer(let code)? = json["code"],
              let message = json["message"]?.string, !message.isEmpty else { return nil }
        self.code = code
        self.message = message
    }
}

public enum CodexWireMessage: Equatable {
    case response(id: CodexClientRequestID, result: CodexJSONValue?, error: CodexRPCError?)
    case serverRequest(id: CodexServerRequestID, method: String, params: CodexJSONValue)
    case notification(method: String, params: CodexJSONValue)
}

public enum CodexProtocolError: Error, Equatable {
    case malformedJSON
    case malformedEnvelope
    case unsupportedJSONRPCHeader
    case lineTooLong
    case tooManyMessages
    case outboundQueueFull
    case invalidState
    case unexpectedResponse
    case requiredField(String)
    case tooManyPendingServerRequests
    case tooManyPendingClientRequests
    case tooManyDeferredTurns
    case tooManyDeferredItems
    case accumulatedTextTooLong
    case staleGeneration
}

public enum CodexWire {
    public static func decode(_ line: Data) throws -> CodexWireMessage {
        let value: CodexJSONValue
        do { value = try JSONDecoder().decode(CodexJSONValue.self, from: line) }
        catch { throw CodexProtocolError.malformedJSON }
        guard let object = value.object else { throw CodexProtocolError.malformedEnvelope }
        if object["jsonrpc"] != nil { throw CodexProtocolError.unsupportedJSONRPCHeader }

        if let methodValue = object["method"] {
            guard let method = methodValue.string, !method.isEmpty,
                  case .object = object["params"] ?? .object([:]) else {
                throw CodexProtocolError.malformedEnvelope
            }
            let params = object["params"] ?? .object([:])
            if let idValue = object["id"] {
                guard let id = CodexRPCID(idValue),
                      object["result"] == nil, object["error"] == nil else {
                    throw CodexProtocolError.malformedEnvelope
                }
                return .serverRequest(id: CodexServerRequestID(id), method: method, params: params)
            }
            guard object["result"] == nil, object["error"] == nil else {
                throw CodexProtocolError.malformedEnvelope
            }
            return .notification(method: method, params: params)
        }

        guard let idValue = object["id"], let id = CodexRPCID(idValue) else {
            throw CodexProtocolError.malformedEnvelope
        }
        let hasResult = object["result"] != nil
        let hasError = object["error"] != nil
        guard hasResult != hasError else { throw CodexProtocolError.malformedEnvelope }
        if let errorValue = object["error"] {
            guard let error = CodexRPCError(json: errorValue) else {
                throw CodexProtocolError.malformedEnvelope
            }
            return .response(id: CodexClientRequestID(id), result: nil, error: error)
        }
        return .response(id: CodexClientRequestID(id), result: object["result"], error: nil)
    }

    public static func request(id: CodexClientRequestID, method: String, params: CodexJSONValue) throws -> Data {
        try encode(.object(["id": id.value.json, "method": .string(method), "params": params]))
    }

    public static func notification(method: String, params: CodexJSONValue = .object([:])) throws -> Data {
        try encode(.object(["method": .string(method), "params": params]))
    }

    public static func serverReply(id: CodexServerRequestID, result: CodexJSONValue) throws -> Data {
        try encode(.object(["id": id.value.json, "result": result]))
    }

    public static func serverErrorReply(id: CodexServerRequestID,
                                        code: Int, message: String) throws -> Data {
        try encode(.object(["id": id.value.json, "error": .object([
            "code": .integer(code), "message": .string(message)
        ])]))
    }

    private static func encode(_ value: CodexJSONValue) throws -> Data {
        var data = try JSONEncoder().encode(value)
        data.append(0x0A)
        return data
    }
}
