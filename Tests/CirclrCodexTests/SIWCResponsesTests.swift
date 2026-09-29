import XCTest
@testable import CirclrCodex

final class SIWCResponsesTests: XCTestCase {
    private let user: CodexJSONValue = .object(["role": .string("user"), "content": .string("안녕")])
    private func event(_ object: CodexJSONValue, newline: String = "\n") throws -> Data {
        Data(("data: " + String(decoding: try JSONEncoder().encode(object), as: UTF8.self) + newline + newline).utf8)
    }
    private func completed(_ output: [CodexJSONValue] = []) -> CodexJSONValue {
        .object(["type": .string("response.completed"), "response": .object([
            "id": .string("resp_1"), "status": .string("completed"), "output": .array(output)])])
    }
    private func call(id: String = "call_1", args: String = "{}", name: String = "edit") -> CodexJSONValue {
        .object(["type": .string("function_call"), "namespace": .string("circlr"), "name": .string(name),
                 "call_id": .string(id), "arguments": .string(args), "status": .string("completed")])
    }
    func testRequestIsStatelessStreamingAndNamespaced() throws {
        let body = try SIWCResponsesRequest(model: "account-model", instructions: "Compose", input: [user], functions: [
            .init(name: "edit", description: "Edit", parameters: .object(["type": .string("object"), "additionalProperties": .bool(false), "properties": .object([:]), "required": .array([])]))]).encoded()
        let json = try JSONDecoder().decode(CodexJSONValue.self, from: body)
        XCTAssertEqual(json["store"], .bool(false)); XCTAssertEqual(json["stream"], .bool(true))
        XCTAssertEqual(json["input"], .array([user])); XCTAssertNil(json["previous_response_id"])
        guard case .array(let tools)? = json["tools"] else { return XCTFail() }
        XCTAssertEqual(tools.first?["type"], .string("namespace"))
        XCTAssertThrowsError(try SIWCResponsesRequest(model: "m", instructions: "", input: [.object(["role": .string("system")])]).encoded())
    }
    func testSingleByteChunkedKoreanAndCRLF() throws {
        let delta = try event(.object(["type": .string("response.output_text.delta"), "delta": .string("노래🎵")]), newline: "\r\n")
        let bytes = delta + (try event(completed(), newline: "\r\n"))
        var parser = SIWCResponsesStreamParser()
        var output: [SIWCResponsesEvent] = []
        for byte in bytes { output += try parser.append(Data([byte])) }
        XCTAssertEqual(output, [.textDelta("노래🎵")]); XCTAssertEqual(try parser.finish().responseID, "resp_1")
    }
    func testArgumentsNotDispatchedUntilCompleted() throws {
        var parser = SIWCResponsesStreamParser(allowedFunctions: ["edit"])
        XCTAssertEqual(try parser.append(event(.object(["type": .string("response.function_call_arguments.done"), "arguments": .string("{}")]))), [])
        XCTAssertThrowsError(try parser.finish())
        _ = try parser.append(event(completed([call()])))
        XCTAssertEqual(try parser.finish().functionCalls.first?.arguments, .object([:]))
    }
    func testInvalidFunctionCompletionsFailClosed() throws {
        for output in [[call(), call()], [call(args: "{" )], [call(args: "[]")], [call(name: "shell")]] {
            var parser = SIWCResponsesStreamParser(allowedFunctions: ["edit"])
            XCTAssertThrowsError(try parser.append(event(completed(output))))
            XCTAssertThrowsError(try parser.finish())
        }
    }
    func testFailedIncompleteEOFLimitsAndInvalidUTF8() throws {
        for type in ["response.failed", "response.incomplete", "error"] {
            var parser = SIWCResponsesStreamParser()
            XCTAssertThrowsError(try parser.append(event(.object(["type": .string(type)]))))
            XCTAssertThrowsError(try parser.finish())
        }
        var parser = SIWCResponsesStreamParser(maximumEventBytes: 8)
        XCTAssertThrowsError(try parser.append(Data("data: 123456789".utf8)))
        var invalid = SIWCResponsesStreamParser()
        XCTAssertThrowsError(try invalid.append(Data([100, 97, 116, 97, 58, 32, 255, 10, 10])))
        var cut = SIWCResponsesStreamParser()
        _ = try cut.append(Data("data: {".utf8)); XCTAssertThrowsError(try cut.finish())
    }
    func testModelsUsesSIWCCatalogAndPreservesOrder() async throws {
        let transport = Fake { request, receive in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/models")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            try await receive(200, "application/json", Data(#"{"models":[{"slug":"b","display_name":"B","visibility":"list"},{"slug":"hidden","visibility":"hide"},{"slug":"a","display_name":"A","visibility":"list"}]}"#.utf8))
        }
        let models = try await SIWCResponsesClient(transport: transport).models(accessToken: "test-token")
        XCTAssertEqual(models.map(\.slug), ["b", "a"])
    }
    func testHTTPAndNetworkFailuresDoNotLeakPayload() async throws {
        for status in [401, 429, 503] {
            let client = SIWCResponsesClient(transport: Fake { _, receive in try await receive(status, nil, Data("SECRET".utf8)) })
            do { _ = try await client.models(accessToken: "test-token"); XCTFail() }
            catch { XCTAssertEqual(error as? SIWCResponsesError, .http(status)) }
        }
        let client = SIWCResponsesClient(transport: Fake { _, _ in throw NSError(domain: "SECRET", code: 1) })
        do { _ = try await client.models(accessToken: "test-token"); XCTFail() }
        catch { XCTAssertEqual(error as? SIWCResponsesError, .network) }
    }
    func testTransportSuccessAndEOFRequireCompleted() async throws {
        let bytes = try event(completed([call()]))
        let request = SIWCResponsesRequest(model: "m", instructions: "", input: [user], functions: [.init(name: "edit", description: "", parameters: .object([:]))])
        let client = SIWCResponsesClient(transport: Fake { _, receive in try await receive(200, "text/event-stream", bytes) })
        let result = try await client.respond(request: request, accessToken: "test-token")
        XCTAssertEqual(result.functionCalls.count, 1)
        let eof = SIWCResponsesClient(transport: Fake { _, receive in try await receive(200, "text/event-stream", Data()) })
        do { _ = try await eof.respond(request: request, accessToken: "test-token"); XCTFail() }
        catch { XCTAssertEqual(error as? SIWCResponsesError, .interruptedStream) }
    }
    func testCancellationRejectsLateTransportBytes() async throws {
        let gate = Gate()
        let data = try event(.object(["type": .string("response.output_text.delta"), "delta": .string("late")])) + event(completed())
        let client = SIWCResponsesClient(transport: Fake { _, receive in
            await gate.wait()
            try await receive(200, "text/event-stream", data)
        })
        let request = SIWCResponsesRequest(model: "m", instructions: "", input: [user])
        let task = Task { try await client.respond(request: request, accessToken: "test-token", onEvent: { _ in XCTFail("late callback") }) }
        await gate.started()
        task.cancel(); await gate.release()
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testURLSessionCancelsUnderlyingTaskOnConsumerFailure() async throws {
        let stopped = expectation(description: "URLProtocol stopped")
        HangingProtocol.onStop = { stopped.fulfill() }
        defer { HangingProtocol.onStop = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HangingProtocol.self]
        let transport = SIWCResponsesURLSessionTransport(configuration: config)
        do {
            try await transport.perform(URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)) { _, _, _ in
                throw SIWCResponsesError.limitExceeded
            }
            XCTFail()
        } catch { XCTAssertEqual(error as? SIWCResponsesError, .limitExceeded) }
        await fulfillment(of: [stopped], timeout: 3)
    }
    func testURLSessionCancelsUnderlyingTaskOnTaskCancellation() async throws {
        let stopped = expectation(description: "URLProtocol stopped")
        let received = expectation(description: "HTTP headers received")
        HangingProtocol.onStop = { stopped.fulfill() }
        defer { HangingProtocol.onStop = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HangingProtocol.self]
        let transport = SIWCResponsesURLSessionTransport(configuration: config)
        let task = Task {
            try await transport.perform(URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)) { _, _, data in
                if data.isEmpty { received.fulfill() }
            }
        }
        await fulfillment(of: [received], timeout: 3)
        task.cancel()
        do { try await task.value; XCTFail() } catch { }
        await fulfillment(of: [stopped], timeout: 3)
    }
    private final class HangingProtocol: URLProtocol {
        private static let lock = NSLock()
        private static var callback: (() -> Void)?
        static var onStop: (() -> Void)? {
            get { lock.lock(); defer { lock.unlock() }; return callback }
            set { lock.lock(); defer { lock.unlock() }; callback = newValue }
        }
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(": heartbeat\n\n".utf8))
        }
        override func stopLoading() { Self.onStop?() }
    }
    private struct Fake: SIWCResponsesTransport {
        let body: (URLRequest, @escaping (Int, String?, Data) async throws -> Void) async throws -> Void
        func perform(_ request: URLRequest, receive: @escaping (Int, String?, Data) async throws -> Void) async throws { try await body(request, receive) }
    }
    private actor Gate {
        var continuation: CheckedContinuation<Void, Never>?
        func wait() async { await withCheckedContinuation { continuation = $0 } }
        func started() async { while continuation == nil { await Task.yield() } }
        func release() { continuation?.resume(); continuation = nil }
    }
}
