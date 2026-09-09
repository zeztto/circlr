# 캔버스 보기와 편집 이력 분리

`session-bootstrap-v1`: owner=development-lead; baseline=0eafe25; branch=codex/daw-integration; delegation=none. 사용자 요청에 따라 독립 검토를 실제 dispatch했으나 `agent thread limit reached`로 거절됐다. UI/UX 계약 → native Swift/Core utility 구현 → read-only code/security 검토 → QA를 순차 수행한다.

## 계약

궤도/자유 배치, 앨범의 그리드 표시와 놓을 때 스냅은 문서에 저장하는 보기 선호다. 변경하면 dirty/recovery를 갱신하지만 Undo 추가, Redo 삭제, 음악/포트 revision 증가, 녹음 요청 취소를 하지 않는다. 메뉴와 명령 검색은 같은 setter를 쓴다. 같은 값을 다시 설정하면 변경하지 않는다.

음악 또는 실제 노드 배치의 snapshot을 Undo/Redo할 때 현재 `circleLayout`을 유지한다. 같은 ID의 앨범이 양쪽에 있을 때만 현재 `album.layout.grid/snap`을 유지한다. 앨범 생성/제거/교체의 구조를 보기 복원 때문에 바꾸지 않으며, nil 기본값도 유지한다. 실제 위치·정렬·그룹·간격과 포트 전용 Undo의 계약은 보존한다. 모든 `musical:false` 변경을 일괄 제외하지 않는다.

## 파일과 검증

Core: `Sources/CirclrCore/CircleHistory.swift`, `Tests/CirclrCoreTests/CircleHistoryTests.swift`. App: `Sources/CirclrApp/AppStore.swift`, `RootView.swift`, `CanvasCommands.swift`. `Resources/Info.plist` build 56, README/CHANGELOG/roadmap/DAW 계획, QA packager/capture/checker와 결과 문서를 갱신한다. Schema·MCP/API·auth·DSP·외부 연결 변경은 없다.

검사 명령: `./scripts/swift-local.sh test --scratch-path .build/automation-time-quality --skip testArrangementRenderExportAndPlayback`, `python3 -m unittest mcp.test_server qa.test_agent_kit`, `./scripts/swift-local.sh build -c release --scratch-path .build/integration-release`.

Native QA는 authored 두-use 사본을 쓴다. 보기만 변경한 뒤 Undo 부재, MIDI 숫자 편집→메뉴/명령으로 보기 변경→한 번 Undo→보기 변경 후 Redo 보존, 실제 노드 이동 Undo, 저장·재열기를 캡처한다. 음악 revision/다른 use/원본·자산 보존을 확인하고 작은 창·편집기 포커스와 표시도 확인한다. 출력·audition·마이크는 시작하지 않는다. 소스와 서명 앱의 executable sections, kit hashes/codesign, root/ports HEAD와 사용자 앱 보존을 확인한다. 검증 뒤 source/docs/tests/QA helper만 승인된 private branch에 commit/push한다.

## 결과와 사용법

build 56에서 계약을 구현했다. 보기 메뉴 또는 ⇧⌘P의 궤도/그리드/스냅 명령은 즉시 반영하고 ⌘S로 저장한다. 음악 편집 뒤 보기를 바꿔도 ⌘Z는 마지막 편집을 되돌린다. Undo 뒤 보기를 바꿔도 ⇧⌘Z로 음악을 다시 실행할 수 있다. 서클 이동·정렬·그룹·포트 편집은 여전히 Undo 대상이다.

Swift 413개·Python 26개, 실제 MIDI 편집/Undo/Redo, 키보드 서클 이동/Undo, 저장·재열기와 패키지 검사를 통과했다. 메뉴 screenshot 1장 unavailable 및 실제 출력/녹음·VoiceOver 범위를 포함한 근거는 [QA](../qa/view-history-review.md)에 기록했다. 다음 작업은 작업 이동 시 자동으로 펼쳐지는 그룹의 이력과 사용자 그룹 편집을 구별하는 계약이다.

후속 자동 그룹 펼침은 [build 57](71-navigation-group-reveal.md)에서 선택 경로의 scene 표시로 분리하고 실제 작업 이동·복귀·Undo·저장 복원을 검증했다.
