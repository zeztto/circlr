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
    func testDocumentedProviderCodesAreClassifiedForBothEndpoints() async throws {
        let cases: [(SIWCResponsesProviderCode, Int)] = [
            (.userNotEligible, 403), (.usageLimitExceeded, 429), (.usageUnavailable, 503),
            (.unsupportedCapability, 400), (.routeNotSupported, 403), (.invalidUser, 401),
            (.scopeNotAuthorized, 403), (.invalidAuthorizationContext, 403), (.userUnavailable, 503)
        ]
        for (code, status) in cases {
            let body = try JSONEncoder().encode(CodexJSONValue.object(["error": .object([
                "code": .string(code.rawValue), "message": .string("SECRET"), "param": .string("SECRET")])]))
            let client = SIWCResponsesClient(transport: Fake { _, receive in
                try await receive(status, "application/json", Data())
                for byte in body { try await receive(status, "application/json", Data([byte])) }
            })
            for streaming in [false, true] {
                do {
                    if streaming {
                        _ = try await client.respond(request: .init(model: "m", instructions: "", input: [user]), accessToken: "test-token", onEvent: { _ in XCTFail("HTTP errors cannot emit text") })
                    } else { _ = try await client.models(accessToken: "test-token") }
                    XCTFail()
                } catch {
                    XCTAssertEqual(error as? SIWCResponsesError, .provider(code: code, status: status))
                    XCTAssertFalse(String(describing: error).contains("SECRET"))
                }
            }
        }
    }
    func testUnknownMalformedAndOversizedErrorBodiesRemainHTTPFailures() async throws {
        let bodies = [Data(), Data(#"{"detail":"SECRET"}"#.utf8),
            Data(#"{"error":{"code":"SECRET","message":"SECRET"}}"#.utf8),
            Data(#"{"error":{"code":"subscription_sharing_invalid_user"}"#.utf8),
            Data([255]), Data(repeating: 65, count: 16 * 1024 + 1)]
        for body in bodies {
            let client = SIWCResponsesClient(transport: Fake { _, receive in
                try await receive(403, "application/json", Data())
                try await receive(403, "application/json", body)
            })
            do { _ = try await client.respond(request: .init(model: "m", instructions: "", input: [user]), accessToken: "test-token"); XCTFail() }
            catch { XCTAssertEqual(error as? SIWCResponsesError, .http(403)) }
        }
    }
    func testHTTPRejectionKeepsOnlyBoundedMachineIdentifiers() async throws {
        let cases: [(String, String, String?, String?)] = [
            ("unsupported_parameter", "tools[0].namespace", "unsupported_parameter", "tools[0].namespace"),
            ("invalid_request", "model", "invalid_request", "model"),
            ("bad code SECRET", "input[0].content", nil, "input[0].content"),
            ("invalid_request", "Bearer SECRET", "invalid_request", nil),
            (String(repeating: "a", count: 97), "model", nil, "model"),
            ("invalid_request", String(repeating: "a", count: 97), "invalid_request", nil),
            ("token.secret", "model", nil, "model"),
            ("오류", "model", nil, "model")
        ]
        for (rawCode, rawParameter, code, parameter) in cases {
            let body = try JSONEncoder().encode(CodexJSONValue.object(["error": .object([
                "code": .string(rawCode), "param": .string(rawParameter),
                "message": .string("SECRET"), "detail": .string("SECRET")])]))
            let client = SIWCResponsesClient(transport: Fake { _, receive in
                try await receive(400, "application/json", body)
            })
            for streaming in [false, true] {
                do {
                    if streaming {
                        _ = try await client.respond(request: .init(model: "m", instructions: "", input: [user]), accessToken: "test-token")
                    } else { _ = try await client.models(accessToken: "test-token") }
                    XCTFail()
                } catch {
                    XCTAssertEqual(error as? SIWCResponsesError, .requestRejected(code: code, parameter: parameter, status: 400))
                    XCTAssertFalse(String(describing: error).contains("SECRET"))
                }
            }
        }
    }
    func testInvalidMachineIdentifiersDoNotReplaceHTTPFallback() async throws {
        for value in ["", "SECRET", "Bearer token", "a\nsecret", "api-key", "eyJhbGci.abc.signature", String(repeating: "a", count: 97)] {
            let body = try JSONEncoder().encode(CodexJSONValue.object(["error": .object([
                "code": .string(value), "param": .string(value)])]))
            let client = SIWCResponsesClient(transport: Fake { _, receive in
                try await receive(400, nil, body)
            })
            do { _ = try await client.models(accessToken: "test-token"); XCTFail() }
            catch { XCTAssertEqual(error as? SIWCResponsesError, .http(400)) }
        }
    }
    func testErrorBodyCapStopsTransportBeforeFurtherChunks() async throws {
        let client = SIWCResponsesClient(transport: Fake { _, receive in
            try await receive(503, nil, Data(repeating: 65, count: 16 * 1024))
            try await receive(503, nil, Data([65]))
            XCTFail("Oversized error body must terminate the transport")
        })
        do { _ = try await client.models(accessToken: "test-token"); XCTFail() }
        catch { XCTAssertEqual(error as? SIWCResponsesError, .http(503)) }
    }
    func testErrorStatusSurvivesIncompleteTransportAndCannotBecomeSuccess() async throws {
        for status in [401, 403, 429, 503] {
            let client = SIWCResponsesClient(transport: Fake { _, receive in
                try await receive(status, nil, Data(#"{"detail":"SECRET"#.utf8))
                throw NSError(domain: "SECRET", code: 1)
            })
            do { _ = try await client.models(accessToken: "test-token"); XCTFail() }
            catch { XCTAssertEqual(error as? SIWCResponsesError, .http(status)) }
        }
        let client = SIWCResponsesClient(transport: Fake { _, receive in
            try await receive(403, nil, Data())
            try await receive(200, "application/json", Data(#"{"models":[]}"#.utf8))
        })
        do { _ = try await client.models(accessToken: "test-token"); XCTFail() }
        catch { XCTAssertEqual(error as? SIWCResponsesError, .http(403)) }
    }
    func testCancellationTakesPrecedenceOverReceivedHTTPError() async throws {
        let client = SIWCResponsesClient(transport: Fake { _, receive in
            try await receive(401, nil, Data())
            throw CancellationError()
        })
        do { _ = try await client.models(accessToken: "test-token"); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testContentTypeFailureReportsOnlyFixedCategory() async throws {
        for (header, category) in [("", "missing"), ("application/json; charset=utf-8", "json"), ("text/html", "html"), ("SECRET", "other")] as [(String?, String)] {
            let client = SIWCResponsesClient(transport: Fake { _, receive in
                try await receive(200, header, Data())
            })
            do { _ = try await client.respond(request: .init(model: "m", instructions: "", input: [user]), accessToken: "test-token"); XCTFail() }
            catch { XCTAssertEqual(error as? SIWCResponsesError, .failed("response_content_type_" + category)) }
        }
    }
    func testMissingContentTypeAcceptsOnlyCompletedValidatedSSE() async throws {
        let bytes = try event(completed([call()]))
        let client = SIWCResponsesClient(transport: Fake { _, receive in
            try await receive(200, nil, Data())
            for byte in bytes { try await receive(200, nil, Data([byte])) }
        })
        let request = SIWCResponsesRequest(model: "m", instructions: "", input: [user], functions: [.init(name: "edit", description: "", parameters: .object([:]))])
        let result = try await client.respond(request: request, accessToken: "test-token")
        XCTAssertEqual(result.responseID, "resp_1")
        XCTAssertEqual(result.functionCalls.count, 1)
        XCTAssertEqual(result.functionCalls.first?.name, "edit")
    }
    func testMissingContentTypeRejectsHTMLMalformedAndIncompleteSSE() async throws {
        let bodies = [
            Data("<html>SECRET</html>".utf8),
            Data("data: SECRET\n\n".utf8),
            try event(.object(["type": .string("response.function_call_arguments.done"), "arguments": .string("{}")])) ,
            try event(completed([call(name: "SECRET")]))
        ]
        for body in bodies {
            let client = SIWCResponsesClient(transport: Fake { _, receive in
                try await receive(200, nil, Data())
                try await receive(200, nil, body)
            })
            do {
                _ = try await client.respond(request: .init(model: "m", instructions: "", input: [user]), accessToken: "test-token", onEvent: { _ in XCTFail("Invalid body cannot emit text") })
                XCTFail("Invalid or incomplete stream must never return tool calls")
            } catch {
                XCTAssertTrue(error is SIWCResponsesError)
                XCTAssertFalse(String(describing: error).contains("SECRET"))
            }
        }
    }
    func testStreamFailureStageCodesNeverContainPayload() throws {
        let cases: [(CodexJSONValue, String)] = [
            (.object(["SECRET": .string("SECRET")]), "stream_event_type"),
            (.object(["type": .string("response.output_text.delta"), "delta": .bool(false)]), "stream_text_delta_shape"),
            (.object(["type": .string("response.completed")]), "completed_response_shape"),
            (.object(["type": .string("response.completed"), "response": .object(["status": .string("SECRET")])]), "completed_status"),
            (completed([.object(["type": .string("SECRET")])]), "completed_item_type_unsupported"),
            (completed([.object(["type": .string("function_call"), "call_id": .string("c"), "name": .string("edit"), "arguments": .string("{}")])]), "function_namespace_missing"),
            (completed([.object(["type": .string("function_call"), "call_id": .string("c"), "name": .string("edit"), "namespace": .string("SECRET"), "arguments": .string("{}")])]), "function_namespace_mismatch"),
            (completed([call(name: "SECRET")]), "function_name_not_allowed"),
            (completed([call(args: "SECRET")]), "function_arguments_json_object")
        ]
        for (input, stage) in cases {
            var parser = SIWCResponsesStreamParser(allowedFunctions: ["edit"])
            XCTAssertThrowsError(try parser.append(event(input))) { error in
                XCTAssertEqual(error as? SIWCResponsesError, .failed(stage))
                XCTAssertFalse(String(describing: error).contains("SECRET"))
            }
            XCTAssertThrowsError(try parser.finish())
        }
        var parser = SIWCResponsesStreamParser()
        XCTAssertThrowsError(try parser.append(Data("data: SECRET\n\n".utf8))) { error in
            XCTAssertEqual(error as? SIWCResponsesError, .failed("stream_event_json"))
        }
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
