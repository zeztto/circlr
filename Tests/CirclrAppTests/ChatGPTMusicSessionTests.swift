import XCTest
import CirclrCore
@testable import CirclrCodex
@testable import CirclrApp

@MainActor final class ChatGPTMusicSessionTests: XCTestCase {
    func finalOutput(_ text: String = "처리 결과를 확인했습니다.") -> [CodexJSONValue] {
        [.object(["type": .string("message"), "role": .string("assistant"),
                  "content": .array([.object(["type": .string("output_text"), "text": .string(text)])])])]
    }
    func spin(_ predicate: @escaping () -> Bool) async {
        for _ in 0..<2000 { if predicate() { return }; await Task.yield() }
        XCTFail("Async state timeout")
    }
    func makeStore() throws -> (AppStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(storageRootOverride: root)
        XCTAssertTrue(store.offerRecovery(startBridgeWhenReady: false))
        var project = Project(); _ = project.addTrack(name: "Synth"); _ = project.addSection(name: "Verse", at: Point(), bars: 2)
        project.enableAlbum(); store.project = try SectionGraphMigration.migrate(project)
        let use = try XCTUnwrap(store.project.active.uses.first)
        store.selection = [use.id]; store.selectedTrackID = store.project.tracks.first?.id
        store.hierarchySelection = .section(arrangementID: store.project.activeArrangementID, useID: use.id)
        return (store, root)
    }
    func clean(_ store: AppStore, _ root: URL) {
        store.chatGPTMusicSessionStorage?.stop(); store.resetSession(); store.pauseAgentBridgeForTermination()
        try? FileManager.default.removeItem(at: root)
    }
    func account() throws -> ChatGPTAccountDependencies {
        let fixture = ChatGPTAccountTests.Fixture()
        let credential = try ChatGPTAccountTests.credential(host: "test-host")
        fixture.saved = .init(hostID: "test-host", identity: credential.identity, credential: credential)
        return fixture.deps
    }
    func args(_ store: AppStore, revision: Int? = nil) -> CodexJSONValue {
        .object(["projectID": .string(store.project.id), "expectedRevision": .integer(revision ?? store.project.musicRevision),
            "arrangementID": .string(store.project.activeArrangementID), "useID": .string(store.selectedUse!.id),
            "laneID": .string(store.currentLane!.id), "append": .bool(false),
            "notes": .array([.object(["beat": .integer(0), "duration": .number(0.5), "pitch": .integer(64), "velocity": .integer(90)])])])
    }
    func testActualEditAndUndoThroughCompletedToolLoop() async throws {
        let (store, root) = try makeStore(); defer { clean(store, root) }
        var calls = 0
        let session = ChatGPTMusicSession(store: store, dependencies: .init(account: try account(), models: { _ in [.init(slug: "test", displayName: "Test")] }, respond: { request, _, event in
            calls += 1
            XCTAssertLessThan(try request.encoded().count, 196608)
            if calls == 1 { return .init(responseID: "a", output: [], functionCalls: [.init(callID: "c", name: "set_notes", arguments: self.args(store))]) }
            try await event(.textDelta("멜로디를 만들었습니다."))
            return .init(responseID: "b", output: [], functionCalls: [])
        }))
        store.chatGPTMusicSessionStorage = session
        session.connect(); await spin { !session.models.isEmpty }
        session.draft = "멜로디 만들기"; session.submit(); await spin { !session.isRunning }
        XCTAssertNil(session.errorMessage); XCTAssertEqual(store.currentLane?.notes.count, 1)
        XCTAssertEqual(store.currentLane?.notes.first?.pitch, 64); XCTAssertEqual(calls, 2)
        XCTAssertNil(store.trustedAgentIngress, "In-process account must not expose socket")
        store.undo(); XCTAssertEqual(store.currentLane?.notes.count, 0)
    }
    func testStopRejectsProviderThatIgnoresCancellation() async throws {
        let (store, root) = try makeStore(); defer { clean(store, root) }
        var pending: CheckedContinuation<SIWCResponsesResult, Error>?
        let session = ChatGPTMusicSession(store: store, dependencies: .init(account: try account(), models: { _ in [.init(slug: "test", displayName: "Test")] }, respond: { _, _, _ in
            try await withCheckedThrowingContinuation { pending = $0 }
        }))
        store.chatGPTMusicSessionStorage = session; session.connect(); await spin { !session.models.isEmpty }
        session.draft = "멜로디"; session.submit(); await spin { pending != nil }
        let arguments = args(store); session.stop()
        pending?.resume(returning: .init(responseID: "late", output: [], functionCalls: [.init(callID: "late", name: "set_notes", arguments: arguments)]))
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(store.currentLane?.notes.count, 0); XCTAssertFalse(session.isRunning)
        XCTAssertEqual(session.draft, "멜로디")
    }
    func testUnknownAuthorityAndInvalidNoteAreRejected() throws {
        let (store, root) = try makeStore(); defer { clean(store, root) }
        var raw = args(store).object!; raw["path"] = .string("/tmp/forbidden")
        XCTAssertThrowsError(try ChatGPTMusicTools.request(.init(callID: "bad", name: "set_notes", arguments: .object(raw))))
        raw.removeValue(forKey: "path"); raw["notes"] = .array([.object(["beat": .integer(0), "duration": .integer(1), "pitch": .integer(128), "velocity": .integer(90)])])
        XCTAssertThrowsError(try ChatGPTMusicTools.request(.init(callID: "bad", name: "set_notes", arguments: .object(raw))))
    }
    func testStaleWriteNeverRefreshesRevisionAndProviderFailureKeepsDraft() async throws {
        let (store, root) = try makeStore(); defer { clean(store, root) }
        let observed = store.project.musicRevision
        let stale = args(store, revision: observed)
        var calls = 0
        let session = ChatGPTMusicSession(store: store, dependencies: .init(account: try account(), models: { _ in [.init(slug: "test", displayName: "Test")] }, respond: { request, _, _ in
            calls += 1
            if calls == 1 {
                store.mutate("사용자 편집") { $0.musicRevision += 1 }
                return .init(responseID: "a", output: [], functionCalls: [.init(callID: "stale", name: "set_notes", arguments: stale)])
            }
            XCTAssertTrue(try String(decoding: request.encoded(), as: UTF8.self).contains("error"))
            throw SIWCResponsesError.network
        }))
        store.chatGPTMusicSessionStorage = session; session.connect(); await spin { !session.models.isEmpty }
        session.draft = "다시 시도할 요청"; session.submit(); await spin { !session.isRunning }
        XCTAssertEqual(store.currentLane?.notes.count, 0); XCTAssertNotNil(session.errorMessage)
        XCTAssertEqual(session.draft, "다시 시도할 요청")
    }
    func testDocumentReplacementRejectsLateCallbacksAndClearsConversation() async throws {
        let (store, root) = try makeStore(); defer { clean(store, root) }
        var pending: CheckedContinuation<SIWCResponsesResult, Error>?
        let session = ChatGPTMusicSession(store: store, dependencies: .init(account: try account(), models: { _ in [.init(slug: "test", displayName: "Test")] }, respond: { _, _, _ in
            try await withCheckedThrowingContinuation { pending = $0 }
        }))
        store.chatGPTMusicSessionStorage = session; session.connect(); await spin { !session.models.isEmpty }
        session.draft = "멜로디"; session.submit(); await spin { pending != nil }
        let arguments = args(store); store.project = Project()
        pending?.resume(returning: .init(responseID: "late", output: [], functionCalls: [.init(callID: "late", name: "set_notes", arguments: arguments)]))
        for _ in 0..<30 { await Task.yield() }
        XCTAssertTrue(session.messages.isEmpty); XCTAssertFalse(session.isRunning); XCTAssertNil(store.trustedRun.active)
    }

    func testDuplicateCallIDAcrossRoundsDoesNotApplySecondWrite() async throws {
        let (store, root) = try makeStore(); defer { clean(store, root) }
        var calls = 0
        let session = ChatGPTMusicSession(store: store, dependencies: .init(account: try account(), models: { _ in [.init(slug: "test", displayName: "Test")] }, respond: { _, _, _ in
            calls += 1
            var raw = self.args(store).object!; raw["append"] = .bool(true)
            return .init(responseID: "r", output: [], functionCalls: [.init(callID: "same", name: "set_notes", arguments: .object(raw))])
        }))
        store.chatGPTMusicSessionStorage = session; session.connect(); await spin { !session.models.isEmpty }
        session.draft = "멜로디"; session.submit(); await spin { !session.isRunning }
        XCTAssertEqual(calls, 2); XCTAssertEqual(store.currentLane?.notes.count, 1)
        XCTAssertNotNil(session.errorMessage); store.undo(); XCTAssertEqual(store.currentLane?.notes.count, 0)
    }
    func testToolRoundLimitAndAccountLogoutClearHistory() async throws {
        let (store, root) = try makeStore(); defer { clean(store, root) }
        var calls = 0
        let session = ChatGPTMusicSession(store: store, dependencies: .init(account: try account(), models: { _ in [.init(slug: "test", displayName: "Test")] }, respond: { _, _, _ in
            calls += 1
            return .init(responseID: "r", output: [], functionCalls: [.init(callID: "call-\(calls)", name: "read_selection", arguments: .object([:]))])
        }))
        store.chatGPTMusicSessionStorage = session; session.connect(); await spin { !session.models.isEmpty }
        session.draft = "반복"; session.submit(); await spin { !session.isRunning }
        XCTAssertEqual(calls, 6); XCTAssertNotNil(session.errorMessage); XCTAssertEqual(session.draft, "반복")
        session.logout(); XCTAssertTrue(session.messages.isEmpty)
        await spin { !session.isSignedIn }; XCTAssertTrue(session.models.isEmpty)
    }

    func populateNotes(_ store: AppStore, count: Int) throws {
        var lane = try XCTUnwrap(store.currentLane)
        lane.notes = (0..<count).map { Note(beat: Double($0) / 64, length: 0.125, pitch: 60, velocity: 90) }
        var project = store.project
        try ProjectEditing.setLane(lane, for: store.selectedUse!.id, original: false, in: &project)
        store.project = project
    }

    func testReadIncludesPreviouslyTruncatedNotesAndAllowsCompleteReplacement() async throws {
        let (store, root) = try makeStore(); defer { clean(store, root) }
        try populateNotes(store, count: 65)
        let original = try XCTUnwrap(store.currentLane).notes
        var calls = 0
        let session = ChatGPTMusicSession(store: store, dependencies: .init(account: try account(), models: { _ in [.init(slug: "test", displayName: "Test")] }, respond: { request, _, _ in
            calls += 1
            if calls == 1 {
                let wire = String(decoding: try request.encoded(), as: UTF8.self)
                XCTAssertTrue(wire.contains(original[64].id), "The model must observe the formerly hidden 65th note")
                return .init(responseID: "edit", output: [], functionCalls: [.init(callID: "replace", name: "set_notes", arguments: self.args(store))])
            }
            return .init(responseID: "done", output: self.finalOutput(), functionCalls: [])
        }))
        store.chatGPTMusicSessionStorage = session; session.connect(); await spin { !session.models.isEmpty }
        session.draft = "전체 멜로디 교체"; session.submit(); await spin { !session.isRunning }
        XCTAssertNil(session.errorMessage); XCTAssertEqual(store.currentLane?.notes.count, 1)
        store.undo(); XCTAssertEqual(store.currentLane?.notes, original)
    }

    func testIncompleteReadRejectsReplacementButAllowsAppend() async throws {
        let (store, root) = try makeStore(); defer { clean(store, root) }
        try populateNotes(store, count: 257)
        let original = try XCTUnwrap(store.currentLane).notes
        var calls = 0
        let session = ChatGPTMusicSession(store: store, dependencies: .init(account: try account(), models: { _ in [.init(slug: "test", displayName: "Test")] }, respond: { request, _, _ in
            calls += 1
            if calls == 1 {
                return .init(responseID: "replace", output: [], functionCalls: [.init(callID: "replace", name: "set_notes", arguments: self.args(store))])
            }
            if calls == 2 {
                XCTAssertEqual(store.currentLane?.notes, original)
                XCTAssertTrue(String(decoding: try request.encoded(), as: UTF8.self).contains("error"))
                var raw = self.args(store).object!; raw["append"] = .bool(true)
                return .init(responseID: "append", output: [], functionCalls: [.init(callID: "append", name: "set_notes", arguments: .object(raw))])
            }
            return .init(responseID: "done", output: self.finalOutput(), functionCalls: [])
        }))
        store.chatGPTMusicSessionStorage = session; session.connect(); await spin { !session.models.isEmpty }
        session.draft = "노트 추가"; session.submit(); await spin { !session.isRunning }
        XCTAssertNil(session.errorMessage); XCTAssertEqual(store.currentLane?.notes.count, 258)
        XCTAssertEqual(Array(try XCTUnwrap(store.currentLane).notes.prefix(257)), original)
    }

    func testFinalResponseWaitsForOwnedJobWithoutModelPolling() async throws {
        let (store, root) = try makeStore(); defer { clean(store, root) }
        var suppliedFinal = false
        let session = ChatGPTMusicSession(store: store, dependencies: .init(account: try account(), models: { _ in [.init(slug: "test", displayName: "Test")] }, respond: { _, _, _ in
            let lease = try XCTUnwrap(store.trustedRun.active)
            store.agentJob = AgentJob(id: "pending", kind: "bounce", state: "running", message: "")
            store.trustedAgentJob = TrustedAgentJob(id: "pending", lease: lease)
            suppliedFinal = true
            return .init(responseID: "done", output: self.finalOutput(), functionCalls: [])
        }))
        store.chatGPTMusicSessionStorage = session; session.connect(); await spin { !session.models.isEmpty }
        session.draft = "바운스"; session.submit(); await spin { suppliedFinal }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(session.isRunning); XCTAssertFalse(store.trustedRun.turnCompleted)
        store.agentJob?.state = "completed"
        try await Task.sleep(for: .milliseconds(300))
        await spin { !session.isRunning }
        XCTAssertNil(session.errorMessage); XCTAssertTrue(store.trustedRun.turnCompleted)
    }

    func testFailedOwnedJobCannotBecomeSuccessfulFinalResponse() async throws {
        let (store, root) = try makeStore(); defer { clean(store, root) }
        let session = ChatGPTMusicSession(store: store, dependencies: .init(account: try account(), models: { _ in [.init(slug: "test", displayName: "Test")] }, respond: { _, _, _ in
            let lease = try XCTUnwrap(store.trustedRun.active)
            store.agentJob = AgentJob(id: "failed", kind: "save", state: "failed", message: "")
            store.trustedAgentJob = TrustedAgentJob(id: "failed", lease: lease)
            return .init(responseID: "done", output: self.finalOutput(), functionCalls: [])
        }))
        store.chatGPTMusicSessionStorage = session; session.connect(); await spin { !session.models.isEmpty }
        session.draft = "저장"; session.submit(); await spin { !session.isRunning }
        XCTAssertNotNil(session.errorMessage); XCTAssertEqual(session.status, "작업 중단")
        XCTAssertEqual(session.draft, "저장"); XCTAssertNil(store.trustedRun.active)
    }

    func testStopWhileFinalResponseWaitsForOwnedJob() async throws {
        let (store, root) = try makeStore(); defer { clean(store, root) }
        var suppliedFinal = false
        let session = ChatGPTMusicSession(store: store, dependencies: .init(account: try account(), models: { _ in [.init(slug: "test", displayName: "Test")] }, respond: { _, _, _ in
            let lease = try XCTUnwrap(store.trustedRun.active)
            store.agentJob = AgentJob(id: "pending", kind: "bounce", state: "running", message: "")
            store.trustedAgentJob = TrustedAgentJob(id: "pending", lease: lease)
            suppliedFinal = true
            return .init(responseID: "done", output: self.finalOutput(), functionCalls: [])
        }))
        store.chatGPTMusicSessionStorage = session; session.connect(); await spin { !session.models.isEmpty }
        session.draft = "바운스"; session.submit(); await spin { suppliedFinal }
        session.stop()
        for _ in 0..<30 { await Task.yield() }
        XCTAssertFalse(session.isRunning); XCTAssertEqual(session.status, "AI 작업 중단")
        XCTAssertEqual(store.agentJob?.state, "cancelled"); XCTAssertNil(store.trustedRun.active)
        XCTAssertEqual(session.draft, "바운스")
    }

    func testUsageLimitPreservesAccountAndDraftWithRecoveryMessage() async throws {
        let (store, root) = try makeStore(); defer { clean(store, root) }
        let session = ChatGPTMusicSession(store: store, dependencies: .init(account: try account(), models: { _ in [.init(slug: "test", displayName: "Test")] }, respond: { _, _, _ in
            throw SIWCResponsesError.provider(code: .usageLimitExceeded, status: 429)
        }))
        store.chatGPTMusicSessionStorage = session; session.connect(); await spin { !session.models.isEmpty }
        session.draft = "유지할 요청"; session.submit(); await spin { !session.isRunning }
        XCTAssertEqual(session.draft, "유지할 요청"); XCTAssertTrue(session.isSignedIn)
        XCTAssertTrue(session.errorMessage?.contains("Usage") == true)
        XCTAssertFalse(session.errorMessage?.contains("429") == true)
    }

    func testIneligibleModelListingKeepsAccountAndExplainsEligibility() async throws {
        let (store, root) = try makeStore(); defer { clean(store, root) }
        let session = ChatGPTMusicSession(store: store, dependencies: .init(account: try account(), models: { _ in
            throw SIWCResponsesError.provider(code: .userNotEligible, status: 403)
        }, respond: { _, _, _ in XCTFail("No model must be called"); throw SIWCResponsesError.network }))
        store.chatGPTMusicSessionStorage = session; session.draft = "유지할 요청"; session.connect()
        await spin { session.errorMessage != nil && !session.isLoadingModels }
        XCTAssertTrue(session.isSignedIn); XCTAssertTrue(session.models.isEmpty)
        XCTAssertEqual(session.draft, "유지할 요청")
        XCTAssertTrue(session.errorMessage?.contains("워크스페이스") == true)
        XCTAssertFalse(session.isSigningIn)
    }

    func testTurnFailuresExposeBoundedDiagnosticsAndPreserveDraft() async throws {
        let cases: [(SIWCResponsesError, String)] = [
            (.http(400), "HTTP 400"),
            (.invalidResponse, "invalid_response"),
            (.incomplete, "incomplete_response"),
            (.invalidUTF8, "invalid_utf8"),
            (.interruptedStream, "interrupted_stream"),
            (.failed("server_error"), "response_failed/server_error"),
            (.failed("Bearer secret-token\nraw response"), "response_failed/unknown_error"),
            (.requestRejected(code: "invalid_request_error", parameter: "tools[0].parameters", status: 400), "field=tools[0].parameters"),
            (.requestRejected(code: "Bearer secret-token", parameter: "/private/secret-token", status: 400), "HTTP 400")
        ]
        for (failure, diagnostic) in cases {
            let (store, root) = try makeStore()
            let session = ChatGPTMusicSession(store: store, dependencies: .init(account: try account(), models: { _ in [.init(slug: "test", displayName: "Test")] }, respond: { _, _, _ in throw failure }))
            store.chatGPTMusicSessionStorage = session; session.connect(); await spin { !session.models.isEmpty }
            session.draft = "진단 후 다시 시도할 요청"; session.submit(); await spin { !session.isRunning }
            XCTAssertTrue(session.errorMessage?.contains(diagnostic) == true, "Missing diagnostic for \(failure)")
            XCTAssertFalse(session.errorMessage?.contains("secret-token") == true)
            XCTAssertFalse(session.errorMessage?.contains("raw response") == true)
            XCTAssertEqual(session.draft, "진단 후 다시 시도할 요청"); XCTAssertTrue(session.isSignedIn)
            XCTAssertEqual(store.currentLane?.notes.count, 0)
            clean(store, root)
        }
    }

    func testCatalogFailureExposesHTTPAndRejectedFieldWithoutRawDetails() async throws {
        let (store, root) = try makeStore(); defer { clean(store, root) }
        let session = ChatGPTMusicSession(store: store, dependencies: .init(account: try account(), models: { _ in
            throw SIWCResponsesError.requestRejected(code: "invalid_request_error", parameter: "model", status: 400)
        }, respond: { _, _, _ in XCTFail("No model must be called"); throw SIWCResponsesError.network }))
        store.chatGPTMusicSessionStorage = session; session.draft = "유지할 요청"; session.connect()
        await spin { session.errorMessage != nil && !session.isLoadingModels }
        XCTAssertTrue(session.errorMessage?.contains("HTTP 400") == true)
        XCTAssertTrue(session.errorMessage?.contains("invalid_request_error") == true)
        XCTAssertTrue(session.errorMessage?.contains("field=model") == true)
        XCTAssertTrue(session.isSignedIn); XCTAssertEqual(session.draft, "유지할 요청")
    }

    func testEmptyCompletionDoesNotClaimSuccessOrClearDraft() async throws {
        let cases: [([CodexJSONValue], String)] = [
            ([], "completed_output_empty"),
            ([.object(["type": .string("reasoning"), "summary": .array([])])], "completed_reasoning_only"),
            (finalOutput("  "), "completed_message_no_usable_text")
        ]
        for (output, diagnostic) in cases {
            let (store, root) = try makeStore()
            let session = ChatGPTMusicSession(store: store, dependencies: .init(account: try account(), models: { _ in [.init(slug: "test", displayName: "Test")] }, respond: { _, _, _ in
                .init(responseID: "empty", output: output, functionCalls: [])
            }))
            store.chatGPTMusicSessionStorage = session; session.connect(); await spin { !session.models.isEmpty }
            session.draft = "멜로디 만들기"; session.submit(); await spin { !session.isRunning }
            XCTAssertTrue(session.errorMessage?.contains(diagnostic) == true)
            XCTAssertEqual(session.status, "작업 중단"); XCTAssertEqual(session.draft, "멜로디 만들기")
            XCTAssertEqual(store.project.musicRevision, 0); XCTAssertEqual(store.currentLane?.notes.count, 0)
            clean(store, root)
        }
    }

    func testCompletedMessageFallbackDisplaysTextWithoutClaimingMusicEdit() async throws {
        let (store, root) = try makeStore(); defer { clean(store, root) }
        let session = ChatGPTMusicSession(store: store, dependencies: .init(account: try account(), models: { _ in [.init(slug: "test", displayName: "Test")] }, respond: { _, _, _ in
            .init(responseID: "text", output: self.finalOutput("선택한 섹션은 2마디입니다."), functionCalls: [])
        }))
        store.chatGPTMusicSessionStorage = session; session.connect(); await spin { !session.models.isEmpty }
        session.draft = "섹션 설명"; session.submit(); await spin { !session.isRunning }
        XCTAssertNil(session.errorMessage); XCTAssertEqual(session.messages.last?.text, "선택한 섹션은 2마디입니다.")
        XCTAssertEqual(session.status, "응답 수신 · 음악 변경 없음"); XCTAssertEqual(store.project.musicRevision, 0)
    }

    func testCompletedMessageDoesNotDuplicateAlreadyStreamedText() async throws {
        let (store, root) = try makeStore(); defer { clean(store, root) }
        let session = ChatGPTMusicSession(store: store, dependencies: .init(account: try account(), models: { _ in [.init(slug: "test", displayName: "Test")] }, respond: { _, _, event in
            try await event(.textDelta("안내합니다."))
            return .init(responseID: "text", output: self.finalOutput("안내합니다."), functionCalls: [])
        }))
        store.chatGPTMusicSessionStorage = session; session.connect(); await spin { !session.models.isEmpty }
        session.draft = "설명"; session.submit(); await spin { !session.isRunning }
        XCTAssertNil(session.errorMessage); XCTAssertEqual(session.messages.last?.text, "안내합니다.")
    }

}
