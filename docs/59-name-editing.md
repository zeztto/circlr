# 이름 입력의 확정과 취소

## 실행 계약

`session-bootstrap-v1`: owner=development-lead; implementation=native Swift utility; baseline=eacdc8d; branch=codex/daw-integration; delegation=none (직전 실제 subagent 한도 거절, 변경 없는 재호출은 생략). 이전 build 44는 구현·검증·push를 완료한 progress다.

기존 live TextField는 한 글자마다 `mutate`를 호출한다. 주 캔버스의 이름, 기존 섹션/트랙/리듬/그룹 필드에 공통 draft를 적용한다. 기존 global 설정의 전체 적용 draft는 별도 수명 계약이므로 이번에는 바꾸지 않는다.

- 입력 중 프로젝트·revision·Undo 이력은 변하지 않는다. Return/Tab/다른 컨트롤 클릭은 유효한 이름을 한 번 적용한다. ⌘S/⇧⌘S는 이름을 먼저 확정하고 저장하며 유효하지 않으면 이름 오류를 표시한다. Esc는 원래 값으로 돌아가며 Return/Esc 후 캔버스 키보드 포커스를 회복한다.
- 한글/일본어 조합 중 임시 문자열을 확정하지 않는다. 선행/후행 공백을 정리하고, 빈 이름·여러 줄·256자를 초과하는 새 이름을 거절한다. 내부 공백·기호·emoji·Unicode는 보존한다. 기존 긴 이름을 변경 없이 떠나면 다시 쓰거나 잘라내지 않는다.
- baseline 이름과 프로젝트/session/대상/revision이 달라지면 덮어쓰지 않는다. 다른 대상이나 제거된 필드의 늦은 이벤트는 새 대상에 적용하지 않는다. 명시적 취소·오류는 상태와 접근성 도움말로 전달한다.
- 이름의 오류 표시는 헤더 높이를 늘리지 않는다. 불변인 앨범 사운드 컨테이너는 수정 가능한 필드로 표시하지 않는다. 새 창·고정 사이드 패널은 만들지 않는다.

Core: `Sources/CirclrCore/NameEditSession.swift`, `Tests/CirclrCoreTests/NameEditSessionTests.swift`. App: `CommittedNameField.swift`, `InlineEditorHeader.swift`, `InlineCircleEditor.swift`, `CircleWorkspace.swift`, `EditorView.swift`, `CommittedNumberField.swift`, `AppStore.swift`. 기존 `NumberEditingContext`의 live project/target/session guard를 공유하며 이름 registry를 전달한다. 앱의 UI 저장/프로젝트 교체는 활성 이름을 먼저 확정한다. MCP 저장은 기존 계약대로 committed 프로젝트만 저장하며 사용자의 미확정 초안을 임의로 적용하지 않는다. 단계별 UI/UX → Swift 구현 → 읽기 전용 리뷰 → QA 전환이며 문서/QA helper/버전은 후속 소유 slice다.

검증: `./scripts/swift-local.sh test --scratch-path .build/connection-workspace-quality --skip testArrangementRenderExportAndPlayback`; `python3 -m unittest mcp.test_server qa.test_agent_kit`; `./scripts/swift-local.sh build -c release --scratch-path .build/integration-release`. 이름 draft·Unicode·공백·취소·충돌·late event를 제어된 테스트로 검사한다. source-built QA 앱에서 ASCII 연속 입력/Unicode 붙여넣기 전후 revision, Return/Tab/Esc, 다른 대상/외부 수정, Undo·저장/재열기를 확인한다. 실제 IME 조합과 legacy 창 조합의 검증 범위를 별도 명시한다.

검증 사본은 authored 파일만 복제한다. 이번 이름 검사는 음악 출력·미리 듣기·마이크/MIDI 입력을 시작하지 않는다. 사용자 앱과 다른 작업 트리를 보존하며 통과한 source/docs/tests/helper만 승인된 private branch에 commit/push한다.

## 구현 결과

build 45에서 구현했다. 첫 native ⌘S 실패는 UI 저장/프로젝트 교체의 활성 이름 registry로 수정했다. 최종 setter 결과를 다시 읽어 변경 거절 시 초안을 보존하며 이전 registry 해제 순서도 보완했다. Swift 363개·Python 26개, native 21 snapshots·8 JPEG와 저장/재열기·원본 복원·최종 패키지 검사가 통과했다. [QA 근거와 남은 IME/legacy/녹음 범위](../qa/name-editing-review.md)를 따른다.
