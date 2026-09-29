import Foundation

/// Byte framing precedes UTF-8 decoding, so arbitrary network chunk boundaries are safe.
public struct SIWCResponsesStreamParser {
    private var line = Data()
    private var eventData = Data()
    private var pendingCR = false
    private var totalBytes = 0
    private var result: SIWCResponsesResult?
    private var failed = false
    private let allowedFunctions: Set<String>
    public let maximumEventBytes: Int
    public let maximumStreamBytes: Int
    public init(allowedFunctions: Set<String> = [], maximumEventBytes: Int = 2 * 1024 * 1024,
                maximumStreamBytes: Int = 16 * 1024 * 1024) {
        self.allowedFunctions = allowedFunctions
        self.maximumEventBytes = max(1, maximumEventBytes)
        self.maximumStreamBytes = max(1, maximumStreamBytes)
    }
    public mutating func append(_ bytes: Data) throws -> [SIWCResponsesEvent] {
        guard !failed else { throw SIWCResponsesError.invalidResponse }
        do {
            guard bytes.count <= maximumStreamBytes - totalBytes else { throw SIWCResponsesError.limitExceeded }
            totalBytes += bytes.count
            var events: [SIWCResponsesEvent] = []
            for byte in bytes {
                if pendingCR { pendingCR = false; if byte == 10 { continue } }
                if byte == 10 || byte == 13 {
                    events += try finishLine()
                    pendingCR = byte == 13
                } else {
                    guard line.count < maximumEventBytes else { throw SIWCResponsesError.limitExceeded }
                    line.append(byte)
                }
            }
            return events
        } catch { failed = true; throw error }
    }
    public func finish() throws -> SIWCResponsesResult {
        guard !failed, line.isEmpty, eventData.isEmpty, let result else { throw SIWCResponsesError.interruptedStream }
        return result
    }
    private mutating func finishLine() throws -> [SIWCResponsesEvent] {
        defer { line.removeAll(keepingCapacity: true) }
        if line.isEmpty {
            guard !eventData.isEmpty else { return [] }
            defer { eventData.removeAll(keepingCapacity: true) }
            if eventData.last == 10 { eventData.removeLast() }
            guard let string = String(data: eventData, encoding: .utf8) else { throw SIWCResponsesError.invalidUTF8 }
            if string == "[DONE]" { return [] }
            guard let json = try? JSONDecoder().decode(CodexJSONValue.self, from: eventData),
                  let type = json["type"]?.string else { throw SIWCResponsesError.invalidResponse }
            guard result == nil else { throw SIWCResponsesError.invalidResponse }
            switch type {
            case "response.output_text.delta":
                guard let delta = json["delta"]?.string else { throw SIWCResponsesError.invalidResponse }
                return [.textDelta(delta)]
            case "response.failed", "error":
                // Only a bounded machine code crosses the trust boundary; never server messages/headers.
                let code = json["response"]?["error"]?["code"]?.string ?? json["code"]?.string ?? "unknown_error"
                let safe = code.count <= 128 && code.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") })
                throw SIWCResponsesError.failed(safe ? code : "unknown_error")
            case "response.incomplete": throw SIWCResponsesError.incomplete
            case "response.completed":
                result = try completed(json["response"])
            default: break // Nonterminal progress/argument fragments never dispatch tools.
            }
            return []
        }
        guard String(data: line, encoding: .utf8) != nil else { throw SIWCResponsesError.invalidUTF8 }
        let prefix = Array("data:".utf8)
        guard line.starts(with: prefix) else { return [] }
        var value = line.dropFirst(prefix.count)
        if value.first == 32 { value = value.dropFirst() }
        guard eventData.count + value.count + 1 <= maximumEventBytes else { throw SIWCResponsesError.limitExceeded }
        eventData.append(contentsOf: value); eventData.append(10)
        return []
    }
    private func completed(_ response: CodexJSONValue?) throws -> SIWCResponsesResult {
        guard let response, response["status"]?.string == "completed",
              let id = response["id"]?.string, !id.isEmpty, id.utf8.count <= 256,
              case .array(let output)? = response["output"], output.count <= 4096 else { throw SIWCResponsesError.invalidResponse }
        var calls: [SIWCResponsesFunctionCall] = []
        var seen = Set<String>()
        for item in output {
            guard let type = item["type"]?.string else { throw SIWCResponsesError.invalidResponse }
            guard ["message", "reasoning", "function_call"].contains(type) else { throw SIWCResponsesError.invalidResponse }
            guard type == "function_call" else { continue }
            guard item["status"]?.string == nil || item["status"]?.string == "completed",
                  let callID = item["call_id"]?.string, !callID.isEmpty, callID.utf8.count <= 256,
                  seen.insert(callID).inserted,
                  let name = item["name"]?.string, allowedFunctions.contains(name),
                  item["namespace"]?.string == "circlr",
                  let arguments = item["arguments"]?.string, arguments.utf8.count <= 256 * 1024,
                  let value = try? JSONDecoder().decode(CodexJSONValue.self, from: Data(arguments.utf8)),
                  value.object != nil, calls.count < 128 else { throw SIWCResponsesError.invalidResponse }
            calls.append(SIWCResponsesFunctionCall(callID: callID, name: name, arguments: value))
        }
        return SIWCResponsesResult(responseID: id, output: output, functionCalls: calls)
    }
}
