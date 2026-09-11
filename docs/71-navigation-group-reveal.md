# 접힌 그룹 안으로 작업 이동

`session-bootstrap-v1`: owner=development-lead; baseline=82171e1; branch=codex/daw-integration; delegation=none (직전 실제 dispatch가 thread limit으로 거절됨). UI/UX → native Swift/Core utility → read-only code/security review → QA 순서로 진행한다.

## 작업 계약

작업 이동·트랙 역할 버튼·MCP focus는 목적지의 접힌 상위 그룹을 화면에서만 펼친다. 문서의 collapsed 상태, graph layout override, 음악/포트 revision, dirty, Undo/Redo는 바꾸지 않는다. 다른 경로를 선택하거나 상위 그룹으로 돌아가면 저장된 접힘 상태를 다시 보여준다. 선택 경로 밖의 그룹과 공유된 다른 use는 펼치지 않는다. 명시적인 그룹 펼치기/접기는 기존 문서 편집과 Undo를 유지한다.

선택에 따라 만드는 scene에만 reveal을 적용한다. 경로 검증은 원자적이며 사라진 대상·비활성 편곡은 거절한다. scene cache는 선택 변경 시 갱신한다. Esc 복귀는 펼치기 전 scene의 크기가 아니라 현재 scene의 중심·크기로 맞춘다. 저장된 viewport의 선택이 접힌 그룹 안이면 재열기 시 그 경로를 화면에서 복원한다. 새 창·dock·schema·도구 인자는 추가하지 않는다.

## 파일·검증·반영

Core: `Sources/CirclrCore/StudioNavigation.swift`, `HierarchyScene.swift`, `Tests/CirclrCoreTests/StudioNavigationTests.swift` 및 새 경로 검증 테스트. App: `Sources/CirclrApp/StudioNavigationView.swift`, `AlbumWorkspace.swift`, `AppStore.swift`, `AlbumCanvas.swift`, `AgentWorkspace.swift`. build 57, README/CHANGELOG/roadmap/DAW 계획, QA helper와 결과 문서가 범위다. 음악/DSP·권한·외부 API 계약은 유지한다.

검사: `./scripts/swift-local.sh test --scratch-path .build/automation-time-quality --skip testArrangementRenderExportAndPlayback`, `python3 -m unittest mcp.test_server qa.test_agent_kit`, `./scripts/swift-local.sh build -c release --scratch-path .build/integration-release`.

Native: authored 두-use QA 사본에서 ⌘J/역할 버튼으로 접힌 그룹 내부 이동, 이동만 한 뒤 Undo 부재·dirty/revision 보존, 음악 편집→다른 경로→한 번 Undo→다시 이동 후 Redo, Esc/상위 복귀 시 그룹 재접힘, 명시적 그룹 펼침/Undo, 직접 MCP focus·사라진 대상 거절, 같은 선택 저장·앱 재실행 복원을 확인한다. 궤도/자유 배치와 작은 창에서 선택·편집기·라벨·포커스를 캡처한다. 출력/audition/마이크는 시작하지 않는다. 원본/자산·root/ports HEAD·사용자 앱을 보존하고 최종 소스·서명 앱·kit을 대조한다. 검증한 source/docs/tests/QA helper만 승인된 private branch에 commit/push한다.

## 결과와 사용법

build 57에서 구현했다. ⌘J에서 트랙을 찾아 Return을 누르거나 역할 버튼을 선택하면 그룹을 직접 펼치지 않고 편집할 수 있다. Esc는 상위 그룹으로 돌아가며 원래 접힘 상태를 보여준다. 그룹을 계속 펼쳐 두려면 그룹의 펼치기 명령을 사용한다. 이 명시적 편집은 Undo로 되돌릴 수 있다.

음악 편집 전후의 경로 이동은 Undo/Redo를 소비하지 않는다. 저장하면 현재 내부 선택/편집 화면은 viewport로 복원하고, 그룹의 접힘 설정은 유지한다. MCP focus도 같은 경로를 따른다.

Swift 419개·Python 26개, 보강한 경로 테스트 6개, 실제 궤도/자유 이동·음악/그룹 Undo·MCP 거절·저장 복원과 최종 앱 검증을 통과했다. 증분 링크 실패 뒤 깨끗한 검증에 사용한 경로는 `.build/navigation-reveal-quality`다. 메뉴 전환 중 연속 입력 및 실행 범위는 [QA](../qa/navigation-reveal-review.md)를 따른다.
