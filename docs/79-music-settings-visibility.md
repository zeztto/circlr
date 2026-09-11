# 음악 설정의 직접 조작과 우선 배치 — build 65

session-bootstrap-v1: development-lead, baseline=5705a38, branch=codex/daw-integration. 직전 build64는 구현·검증·private push로 progress다. 실제 1 slot 제한에 따라 delegation none, UX → native utility → read-only review → QA를 순차 수행한다.

## 계약과 소유

작은 창에서 길이·반복·리듬이 가려지고 각 출처 전환에 메뉴가 필요한 문제를 해결한다. Sources/CirclrApp/MusicContextEditor.swift의 출처를 기본값·앨범·개별 직접 버튼으로 바꾸고 선택 상태·보관된 개별 값의 도움말을 제공한다. 표시되는 숫자/선택은 계속 실제 유효값이며 개별 전환은 이전 값을 복원한다. 같은 출처는 no-op, 직접 숫자는 Return/Tab 확정·Esc 취소·항목별 Undo와 stale 대상 보호를 유지한다. 리듬을 박 분할·강세보다 먼저 배치한다.

Sources/CirclrApp/InlineCircleEditor.swift의 섹션 연결 진입을 한 줄로 줄이고 길이/반복을 음악 설정보다 먼저, 같은 행에 배치한다. 음악 서클 시작/길이/반복도 같은 행에 모은다. 공유 원본·이번 사용 편집과 1 기반 시작 박, 기존 action 동작을 보존한다. 별도 창/패널·접힘 단계나 문서 schema를 추가하지 않는다. Info.plist는 0.20.0 build65. README/CHANGELOG/docs25/31/79 및 이 범위 QA 도구/보고서를 갱신한다.

키보드 native 검사에서 SwiftUI 버튼 건너뛰기와 일반 NSButton의 Tab 전달을 확인했다. MusicContextEditor 내부 native 출처 버튼과 Sources/CirclrApp/PortKeyboardControls.swift의 navigation 없는 버튼 Tab 처리를 보완한다. 기존 연결 키보드 루프는 유지한다.

## 검증과 반영

기존 MusicContextEditingTests가 전환·개별 보관·다른 주소·원본/override·실패 원자성을 검사한다. UI 배치에 구현 복제 테스트를 추가하지 않는다. `./scripts/swift-local.sh test --scratch-path .build/navigation-reveal-quality --skip testArrangementRenderExportAndPlayback`, `python3 -m unittest mcp.test_server qa.test_agent_kit`, `./scripts/swift-local.sh build -c release --scratch-path .build/integration-release`를 실행한다. 새 authored QA 사본에서 최소 폭1024/콘솔 열림과 닫힘의 픽셀·AX, 섹션/앨범/음악 서클, 직접 출처 전환·숫자 입력·Undo/Redo·연결 왕복·저장 재열기를 확인한다. 원본 fixture, root/ports checkout, 사용자 앱은 보존하고 물리 재생/녹음은 시작하지 않는다. 검증된 source/docs/QA helpers만 승인된 private 브랜치에 commit/push한다.

## 결과

Swift463개·Python28개, 최종 release와 native23상태/21화면 검증을 통과했다. 출처 버튼의 Tab 접근/전달 결함을 수정했고 마디·반복·MIDI 타이밍·앨범·곡 반복의 직접 편집과 전체 음악 복원을 확인했다. [QA 보고서](../qa/music-settings-review.md).

## 후속

작업 화면 복귀 상태의 영속화, 실제 장치 입력/출력, 전 파라미터 automation과 아티스트 세계 관리 등 전체 목표는 계속 진행 중이다. build65는 전체 DAW 완성 선언이 아니다.
