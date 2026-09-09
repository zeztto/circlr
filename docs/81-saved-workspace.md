# 저장한 작업 페이지로 복귀 — build 67

planning-gate-v1: development-lead, baseline=4d50a8c, branch=codex/daw-integration. build66은 progress. 실제 1 slot, delegation none. UX → Core/native utility → read-only review → QA 순차 소유로 진행한다.

## 작업 계약

같은 문서를 저장하고 다시 열면 선택 서클·배율뿐 아니라 편집/연결/전환/오토메이션/설정 페이지와 이번 사용/공유 원본 범위를 복원한다. 선택 서클의 연결 검색·포트·대상·8방향·재연결·목록 범위, 최근 전환과 볼륨/팬 선택을 보기 상태에 저장한다. 모든 서클의 임시 cache를 문서에 저장하지 않는다. 복원 자체는 음악 revision·Undo를 만들지 않는다.

현재 문서에 맞춰 다시 검증한다. 사라진 서클은 유효한 섹션·곡·앨범으로 올라가고 상위 화면에 맞게 초점을 잡는다. 포트/대상/케이블은 build66의 검증을 거쳐 복원하고 삭제된 재연결은 자동 새 연결로 바뀌지 않는다. 전환은 현재 섹션에서 출발하는 유효 edge에만 열리며, 지원하지 않는 오토메이션은 기본 편집으로 돌아간다. 재열기는 연결 적용·재생·녹음·플러그인 창·가져오기 작업을 시작하지 않는다.

기존 문서의 settingsOpen/midiStepMode를 유지하고 optional workspace를 추가한다. 알 수 없는 미래 페이지는 기본 편집으로 해석한다. 보기 상태는 CircleHistory에서도 현재 상태를 보존한다. 재연결은 선택과 의도를 복원할 뿐 사용자의 명시적 적용을 기다린다.

## 파일 책임과 검사

Core utility: `StudioWorkspace.swift`, `ConnectionWorkspaceState.swift`, `HierarchyScene.swift`, `CircleHistory.swift`, `Tests/CirclrCoreTests/SavedWorkspaceTests.swift`. Native utility: `SavedWorkspace.swift`, `AlbumCanvas.swift`, `AppStore.swift`, `InlineCircleEditor.swift`의 세션 identity, `PortConnectionsEditor.swift`의 편집 범위 표시, `Resources/Info.plist`. 동일 캔버스와 기존 헤더를 사용한다. 네트워크·인증 변경 없음. UI 편집·MCP는 현재 승인된 owned fixture에서만 검증하고 사용자 실행 앱은 보존한다.

검사: `./scripts/swift-local.sh test --scratch-path .build/navigation-reveal-quality --skip testArrangementRenderExportAndPlayback`, `python3 -m unittest mcp.test_server qa.test_agent_kit`, release build. Core JSON 왕복·legacy/future page·삭제/미선택 편곡·전환 주소·재연결 변경·보기/Undo 보존을 검사한다. Native에서 연결 draft→저장→재열기→적용/Undo, 전환·오토메이션 팬·설정 범위·MIDI 스텝 저장 복귀와 이전 문서 열기를 AX/화면/전체 문서로 대조한다. 최종 소스·실행 파일·서명·키트 hash와 원본 fixture 보존을 검사한다. README/CHANGELOG/개발 계획/QA 갱신 후 기존 승인된 private 브랜치에 source/docs/tests/helpers만 commit/push한다.

스크롤 위치, 파형/피아노롤의 세부 범위, 모든 플러그인·VoiceOver·물리 입출력은 별도 후속이다. 전체 목표는 유지한다.

## 결과와 다음 작업

build67 구현·검증 완료. 깨끗한 scratch에서 Swift477개·Python28개, 최종 native18상태·20화면과 전체 문서 비교를 통과했다. 같은 문서 재열기 후 검색 재저장 결함을 발견해 세션 identity로 수정했다. [후보별 근거와 제한](../qa/saved-workspace-review.md).

다음은 편집 페이지 안의 위치 보존이다. MIDI 스텝의 페이지/행, 피아노롤·파형·오토메이션의 보이는 구간과 스크롤을 음악 편집 이력과 분리하고, 대상과 길이가 달라지면 유효 구간으로 제한한다. 재열기에 더해 같은 페이지 왕복에서도 포커스와 보이는 위치를 유지해야 한다. 현재 작업 모드·선택 범위를 헤더에서 확인하는 흐름은 유지한다. 물리 입출력과 장치 lifecycle은 별도 출고 조건이다.
