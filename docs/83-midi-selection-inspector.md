# MIDI 선택의 직접 수치 편집 — build 69

planning-gate-v1: development-lead. 기준8d83f7e, `codex/daw-integration`, 실제1 slot/delegation none. 이전 build68은 검증·push 완료의 progress다. UI/UX → Core/native utility → code/security review → QA 순차 소유. 기존 user/root/ports 앱과 문서는 유지하고 검증 사본만 실행한다. 물리 출력·audition·녹음은 시작하지 않는다.

ux-brief-v1: 송라이터/편곡자가 여러 노트를 선택했을 때 수치 입력이 사라지고, 단일 선택의 하단 작업도 작은 창에서 가려진다. 목적은 MIDI 편집 화면 안에서 선택 범위를 읽고 음정·시작·길이·세기를 직접 입력하는 것이다. 빈 선택은 선택 방법, 단일 선택은 실제 값, 다중 선택은 선택 범위와 상대 변화량을 표시한다. 다른 서클/원본/페이지 전환 중 입력은 기존 identity 계약을 따른다.

ux-handoff-v1: native utility. 선택 메뉴 아래2열 입력을 배치해 네 항목과 복제/삭제/퀀타이즈를 가까이 둔다. 다중 선택의 입력값0은 현재 상태, 양수/음수는 전체 선택에 더할 차이다. 음정·시작 간격, 길이 차이와 세기 차이를 보존한다. 모든 선택이 유효한 경우만 한 트랜잭션으로 적용하며 임의 부분 clamp하지 않는다. 범위 오류는 해당 입력에 표시하고 음악은 바꾸지 않는다. Return/Tab 적용과 Esc 취소를 유지한다. 전체 UI는 한국어이며 새 패널/창을 만들지 않는다.

## 구현 경계

- `Sources/CirclrApp/MIDINoteInspector.swift`: 공통 단일/다중 입력, 선택 요약, 명시적 Tab 순서와 stale guard.
- `Sources/CirclrCore/MIDIEditing.swift`: `lengthDelta`, `velocityDelta`의 유효성·원자성·no-op. 기존 MIDI/오디오/노트 ID 보존.
- `Sources/CirclrCore/AgentProtocol.swift`, `mcp/server.py`, `mcp/test_server.py`: `edit_notes`의 `length_delta`(beatOffset), `velocity_delta`(velocityOffset). 기존 velocity 절댓값 계약 유지.
- `Tests/CirclrCoreTests/MIDIBatchInspectorTests.swift`: 상대 차이, 경계/비유한 값, 미선택/오디오 보존, transaction 거절, no-op, agent schema.
- `Resources/Info.plist`, `Resources/Codex/skills/circlr-studio/references/circlr-operations.md`, `Resources/Codex/skills/circlr-studio/scripts/mcp_server.py`, `Resources/Codex/manifest.json`: build69 및 일치하는 kit. kit는 `scripts/build-agent-kit.py`로 생성.
- README/CHANGELOG/docs25/31/83 및 전용 QA 도구/보고서.

## 검증

새 scratch에서 `./scripts/swift-local.sh test --scratch-path .build/midi-inspector-quality --skip testArrangementRenderExportAndPlayback`, `python3 -m unittest mcp.test_server qa.test_agent_kit`, release/native. 실제1024×768에서 단일/다중 선택의 네 필드와 작업 접근, Return/Tab/Esc, 여러 노트의 각 상대 편집과 Undo, 범위 오류 무변경, 기존 단일 값 편집, MCP 편집·stale 거절·문서 재열기/음악 보존을 검사한다. 코드 입력과 모델 변화가 같은지 전체 manifest로 비교하고 signed app/kit hashes를 확인한다. 이 UI 범위의 통과를 실제 오디오 입출력이나 전체 DAW 완료로 확대하지 않는다.

## 실행 결과

Swift491개·Python29개, native14상태/25화면과 전체 음악·앱/키트 서명 비교를 통과했다. 최초 후보에서 가려진 복제/삭제는 상단으로 이동했고 최종 후보에서 다시 검사했다. 두 후보의 근거, 단일 선택 시도의 한계와 후속 AX 경로는 [QA](../qa/midi-inspector-review.md)에 구분했다. 검증 앱은 종료했고 전체 목표는 계속 진행한다.
