# 공통 숫자 입력의 확정·취소

2026-09-09, 기준 `8fce062`, 목표 build 29. 전체 개발 목표는 진행 중이며 E 출고 gate를 유지한다.

## 계획 gate

Owner: development-lead → UI/UX → Swift utility → read-only review → QA. 사용자 요청에 따라 읽기 전용 UX 서브 에이전트를 다시 요청했으나 실제 도구가 `agent thread limit reached`로 거절했다. 추가 슬롯을 우회하지 않고 순차 역할 전환, 독립 테스트/release 명령의 병렬 실행을 사용한다. 기존 private `codex/daw-integration`에서 source/docs/tests만 commit/push한다.

## 작업 계약

- `ValueField`, `CompactNumber`, `CountControl`의 타이핑 중간 값을 모델에 쓰지 않는다. Return 또는 포커스 이동으로 한 번 확정하고 Esc로 취소한다. 단순히 들어갔다 나오는 조작은 표시 자릿수로 원래 정밀도를 덮어쓰지 않는다.
- 유한 숫자·범위·정수 조건을 검증하며 잘못된 입력을 자동 clamp하지 않는다. 포커스 테두리와 오류 표시/도움말로 상태를 구분한다. 새로운 패널은 만들지 않는다.
- 프로젝트·음악 revision·편집 대상·세션 수명이 달라진 dirty 입력을 거절한다. captured Binding의 오래된 getter만으로 현재 대상을 판단하지 않고 AppStore의 live identity를 검사한다. 개별 NSHostingView root에도 같은 환경을 주입한다.
- Tab으로 다음 필드가 먼저 focus된 뒤 이전 필드가 확정될 수 있다. 아직 쓰지 않은 다음 필드는 새 baseline을 받아들이고, 이미 쓰던 필드는 이전 baseline을 보존해 충돌을 검출한다.
- CountControl의 버튼은 즉시 한 단계 변경한다. 템포/스윙/전환/패턴의 기존 숫자 입력에 실제 범위를 지정한다. 별도 설정 전체 적용의 원자성이나 기존 효과 slider/DSP 정책은 이번 계약에 포함하지 않는다.

## 파일·검증

Core: 새 `Sources/CirclrCore/NumberEditSession.swift`, `Tests/CirclrCoreTests/NumberEditSessionTests.swift`에서 정밀도·범위·정수·stale·Tab 인과 관계를 검증한다.

App: 새 `Sources/CirclrApp/CommittedNumberField.swift`, `Theme.swift`, `EditorView.swift`, `RootView.swift`, `InlineCircleEditor.swift`, `CircleWorkspace.swift`, `InspectorView.swift`, `MusicControls.swift`, `AudioWorkspace.swift`, `AutomationEditor.swift`, `UnifiedSectionView.swift`의 공통 필드/환경/범위만 변경한다. `Resources/Info.plist` build 29와 README/CHANGELOG/roadmap을 갱신한다.

QA: `./scripts/swift-local.sh test --scratch-path .build/integration-quality --skip testArrangementRenderExportAndPlayback`, `python3 -m unittest mcp/test_server.py qa/test_agent_kit.py`, `./scripts/swift-local.sh build -c release --scratch-path .build/integration-release`. 별도 authored fixture/build 29 앱으로 신스·오디오·노트·출력·정수의 타이핑/Tab/Return/Esc/invalid/한 Undo, 외부 수정과 대상 변경, 최소 창/콘솔·저장/재열기를 확인한다. 결과 범위를 QA 문서에 구분한다. 실제 마이크·사용자 앱·원본 음악은 보존한다.

## 실행 결과와 설계 보완

SwiftUI FocusState 후보에서 빠른 Tab 후 첫 글자가 지워지고, 후속 후보에서는 정상 입력을 stale로 판단하는 결함을 실제 재현했다. 최종 공통 필드는 AppKit `textShouldEndEditing`에서 이전 값을 먼저 확정하고, 동일 문자열을 다시 넣어 Tab 선택 범위를 지우지 않는다. 숫자 getter는 현재 모델을 읽는다. 입력 전에는 같은 대상의 최신 revision을 받아들이고, dirty draft는 처음 입력한 revision/값을 유지해 충돌을 거절한다. automation point/parameter도 대상에 포함한다.

Swift 265개·Python 26개·release가 통과했다. 최종 패키지에서 MIDI 세 필드, 신스와 오디오의 빠른 Tab, 정수 검증, 출력·반복·템포, 외부 변경·대상 전환, 정밀도 보존과 개별 Undo·저장 재열기를 확인했다. 최종 음악 데이터는 원본과 같고 revision 74로 복원했다. 최종 앱의 file-backed Mach-O 37개 section과 키트 25개 hash가 일치한다. [후보별 결함과 남은 검증](../qa/number-editing-review.md).
