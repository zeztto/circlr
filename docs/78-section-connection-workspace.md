# 섹션 순서와 전환의 직접 편집 — build 64

session-bootstrap-v1: development-lead, baseline=a37bd01, branch=codex/daw-integration. 직전 build63은 구현/native/private push로 progress다. 실제 1 slot과 직전 dispatch 거절에 따라 delegation none, UX → Core/native utility → 읽기 전용 review → QA 순차로 진행한다.

## UX 계약

섹션 설정의 `다음 섹션 연결` 메뉴와 개별 케이블 행을 기존 PortConnectionsEditor로 통합한다. 설정 첫 항목에서 `섹션 순서·전환`을 열어 OUT 재생 경로를 바로 검색한다. 기존 L/연결 버튼·IN/OUT·8방향·그룹 노출 포트·재연결/해제는 유지한다. 별도 overlay나 고정 패널을 만들지 않는다.

대상은 실제 scene의 호환 포트를 사용한다. 직접 섹션은 편곡 uses 순서의 #번호·이름, 포트·곡/악장/편곡 경로로 구별한다. 한글 NFD/전각과 공백 AND 검색, 정확한 #번호를 지원한다. 그룹 노출은 기존 논리 binding을 존중한다. 필터가 대상을 숨기면 선택을 지우며 자동으로 첫 대상을 연결하지 않는다. 목록의 전체 label/help와 ↑↓/Return/Tab을 유지한다.

기존 연결 행에 섹션의 실제 재생 분기 상태와 `이 경로 재생`·`전환 편집`을 배치한다. 연결이 하나이고 종료 섹션이 아니면 자동 재생 경로이며, 여러 분기는 chosenEdges를 따른다. 재생 분기 선택은 해당 편곡의 chosenEdges/출발 use.isEnd만 바꾸고 현재 편집 위치·다른 편곡·전환 효과를 유지한다. 현재 경로 재선택은 no-op이며 한 Undo로 복원된다. 삭제되거나 주소가 다른 케이블은 거절한다. 전환 버튼은 연결 화면을 닫고 그 케이블의 기존 TransitionWorkspace를 연다. 같은 캔버스의 연결 작업 버튼으로 돌아온다.

## 소유와 검사

Core utility: 새 ConnectionTargetSearch.swift/SectionFlowSelection.swift 및 관련 테스트. Native utility: PortConnectionsEditor.swift, PortTargetList.swift, InlineCircleEditor.swift, AlbumWorkspace.swift(기존 선택 명령에 검증 공통화), TransitionWorkspace.swift(전환 앞/뒤의 번호·이름), Info.plist build64. 기존 schema/DSP/MCP는 보존한다. 문서 README/CHANGELOG/docs25/31/78와 qa/section-connection-review.md 및 owned QA helper가 해당 slice다.

Core fixture는 동명/다른 편곡 번호·Unicode/#정확 검색, 실제 Compiler의 단일/다중/종료 분기, 누락/다른 주소 거절과 전체 모델 보존을 검사한다. `./scripts/swift-local.sh test --scratch-path .build/navigation-reveal-quality --skip testArrangementRenderExportAndPlayback`, `python3 -m unittest mcp.test_server qa.test_agent_kit`, release `--scratch-path .build/integration-release`를 실행한다. authored fixture 사본의 다수 동명 섹션/분기에서 설정/L 진입, 검색·무결과·선택 해제, 연결/Undo, 재생 분기/Undo, 전환 왕복·재연결/해제·저장 재열기와 작은 창 픽셀/AX를 확인한다. 음악·port layout 변경은 각각 명시적으로 대조하고 원본 fixture/root/ports/사용자 앱은 보존한다. 물리 재생/마이크는 시작하지 않는다. 읽기 전용 review 후 승인된 private 브랜치에 source/docs/tests/QA helper만 commit/push한다.

## 결과와 후속 범위

Swift463개·Python28개, 최종 release와 native27상태/22화면이 통과했다. 실제 화면에서 반복 경로/Tab 순서를 보완하고 전환 앞·뒤의 동명 구분도 추가했다. 연결/분기/전환/재연결/해제/Undo, 일반 오디오·MIDI 포트와 최종 저장 복원은 [QA 보고서](../qa/section-connection-review.md)에 있다.

다음은 음악 설정의 가시성과 작업 복귀다. `MusicContextEditor.swift`의 출처·유효값·개별 설정 복원·직접 입력을 보존하며 작은 창에서 반복/길이/리듬까지 읽을 수 있도록 우선순위를 다시 배치한다. `InlineEditorHeader.swift`와 `AppStore.resetSession`/저장 hierarchyView를 함께 조사해 연결↔전환↔설정 왕복과 재열기 시 어떤 작업 상태를 복원할지 구분한다. 음악 문서·Undo에 임시 검색어/포트 선택이 섞이지 않아야 한다. 실제 입력·출력 acceptance는 별도 출고 조건으로 유지한다.
