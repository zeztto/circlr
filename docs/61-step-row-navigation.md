# 드럼 스텝 행 탐색

`session-bootstrap-v1`: owner=development-lead; baseline=4d4f0ed; branch=codex/daw-integration; delegation=none (현재 실제 root 포함 슬롯 1개). 이전 build 46은 구현·검증·push 완료로 progress다.

한도 해제 안내를 받은 뒤 독립 검토용 서브 에이전트 생성을 다시 요청했으나 `agent thread limit reached`로 거절됐다. 추가 슬롯이 실제 제공될 때까지 순차 역할 전환으로 진행한다.

## UX·실행 계약

스텝 드럼 행은 관측된 노트·샘플 매핑·임시 추가 행의 합집합이다. 행 검색이 없고 추가한 행으로 이동하지 않으며, 이름 클릭은 무시한다. 최대 128행의 모든 셀이 매번 그려지고 접근성에 노출된다. 기존 한 다크 캔버스 안에서 아래 동작을 완성한다.

- 드럼 모드에서 현재 이름/샘플 이름/MIDI 번호로 행을 검색한다. 검색은 행 표시만 바꾸며 음악·노트 선택·Undo를 변경하지 않는다. Enter는 결과가 있으면 격자로, Esc는 검색 해제 후 격자로 돌아간다. 숨겨진 선택 행은 바로 다시 보여줄 수 있다.
- 드럼 모드에서 효과가 없는 음역 ± 버튼 대신 검색을 제공한다. 음정 스텝과 피아노 롤의 기존 음역 조작은 유지한다. 일치/전체 행 수와 검색 결과 없음 상태를 표시한다.
- 행 추가는 검색을 지우고 추가한 pitch로 스크롤/커서를 이동한다. 노트는 Return 또는 셀 클릭 때만 생성한다. 행 이름 클릭과 접근성의 행 선택은 현재 열을 선택하며 노트를 토글하지 않는다.
- 필터/행 추가·제거 때 커서는 가능한 한 같은 pitch에 남는다. Home/End는 첫/마지막 행, PageUp/PageDown은 보이는 행 수만큼 이동한다. 기존 방향키와 수치 입력·페이지/분할 계약을 유지한다.
- 실제 보이는 행만 그리기/AX에 노출한다. 오래된 행/셀 AX action이 필터 후 다른 pitch나 다른 프로젝트를 수정하지 않도록 target·pitch·page·grid identity를 확인한다.

## 소유 경계와 검증

UI/UX → native Swift utility → 읽기 전용 code/input review → QA → development-lead 순차 전환이다. Core: 새 `Sources/CirclrCore/StepRows.swift`, `Tests/CirclrCoreTests/StepRowsTests.swift`. App: `StepEditor.swift`, `MIDIGridWorkspace.swift`, 필요 시 새 `StepRowSearch.swift`. 문서·QA helper·Info build 47은 마지막 slice다. 신호 엔진·instrument mapping 의미·노트 재생·장치·MCP 인증은 바꾸지 않는다.

Core는 행 합집합·정렬/범위·Unicode/공백/번호 검색·빈 결과를 검사한다. `./scripts/swift-local.sh test --scratch-path .build/connection-workspace-quality --skip testArrangementRenderExportAndPlayback`, `python3 -m unittest mcp.test_server qa.test_agent_kit`, `./scripts/swift-local.sh build -c release --scratch-path .build/integration-release`를 실행한다.

Native authored 사본에 많은 pitch를 추가해 작은 창의 검색/행 이동·추가·선택·Return 토글/Undo·빈 결과·최저/최고/페이지 이동·필터 뒤 다른 사용 전환과 저장/재열기 복원을 검사한다. 출력/audition·마이크/MIDI 입력은 시작하지 않는다. VoiceOver 발화와 전체 대규모 성능 보장은 별도다. source/docs/tests/helper만 승인된 private branch에 commit/push하며 사용자 앱·원본 음악·다른 작업 트리·이전 QA 사본을 보존한다.

## 실행 결과

build 47에서 구현하고 Swift 369개·Python 26개, 실제 앱의 15개 snapshot·7개 JPEG와 패키지 검사를 통과했다. 최초 화면에서 발견한 필터/모드 변경 뒤 커서 스크롤 누락을 수정했고 최종 후보에서 재확인했다. 원본 음악·악기·자산·배치를 복원한 뒤 저장/재열기를 확인했다. 상세 증거와 미검증 범위는 [QA 보고서](../qa/step-row-navigation-review.md)에 기록한다. 전체 DAW/UI goal은 진행 중이다.
