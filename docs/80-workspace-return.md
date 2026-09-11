# 연결 작업과 전환 편집 복귀 — build 66

session-bootstrap-v1: development-lead, baseline=473ba15, branch=codex/daw-integration. 이전 구현/native/private push는 progress다. 실제 1 slot에 맞춰 delegation none, UX → Core/native utility → read-only review → QA 순차 진행한다.

## 계약

동일 프로젝트 세션에서 서클별 연결 검색어·선택 포트·대상·8방향·목록 범위·재연결 작업을 기억한다. 명시적으로 포트나 케이블을 여는 요청은 기억보다 우선하고, 일반 연결 진입은 복원한다. 개별/공유 원본 범위는 구분한다. 유효하지 않은 포트/대상은 지우고 삭제·변경된 재연결은 새 연결로 몰래 전환하지 않는다. 임시 작업은 음악·Undo/Redo·저장 schema에 넣지 않으며 세션 변경 때 지운다.

섹션의 최근 유효한 전환을 상단 `전환`에서 다시 열고 `편집`과 `연결`로 바로 이동한다. 최근 전환은 해당 출발 섹션/편곡/현재 edge가 유효할 때만 보여준다. 새 이름 draft를 먼저 해결하고 상단 작업 버튼은 Tab/Shift-Tab/Return을 지원한다. 창/고정 패널/추가 메뉴를 만들지 않는다.

## 소유와 검증

Core utility: Sources/CirclrCore/ConnectionWorkspaceState.swift, Tests/CirclrCoreTests/ConnectionWorkspaceStateTests.swift. Native utility: PortConnectionsEditor.swift, AppStore.swift, AlbumWorkspace.swift, InlineEditorHeader.swift, InlineCircleEditor.swift(상단·본문 공통 Tab 순서), MusicContextEditor.swift에서 공용 StudioModeButton.swift 추출, Resources/Info.plist build66. 문서 README/CHANGELOG/docs25/31/80, owned QA helper/보고서를 갱신한다.

Core에서 유효 복원·필터/포트/대상 삭제·재연결 주소 변경을 검사한다. `./scripts/swift-local.sh test --scratch-path .build/navigation-reveal-quality --skip testArrangementRenderExportAndPlayback`, `python3 -m unittest mcp.test_server qa.test_agent_kit`, `./scripts/swift-local.sh build -c release --scratch-path .build/integration-release` 실행. authored 분기·오디오/MIDI fixture의 같은 캔버스 왕복/Tab/선택 복원/명시적 재연결/삭제 후 재진입/Undo/새 세션 초기화, 작은 창 픽셀·AX와 저장 음악을 대조한다. 원본 fixture/root/ports/사용자 앱과 계정 상태를 보존하며 물리 오디오 입출력은 시작하지 않는다. 검증한 소스·문서·테스트·도구만 기존 승인된 private 브랜치에 commit/push한다.

재실행 후 임시 검색 전체 복원과 전 작업 페이지의 영속화는 후속 계약이다. 전체 개발 목표는 유지한다.

## 결과

build66에서 구현·검증했다. Swift469개·Python28개 통과. 직접 작성한 native 사본27상태와 상태 복원34화면·최종 키보드7화면을 전체 음악 문서와 대조했다. 연결→설정→연결, 전환→편집→전환, 서클·원본 범위 전환, 명시적 OUT 우선, 삭제된 재연결 해제, 실제 재연결/Undo, 이름 확정과 세션 초기화를 확인했다. 상단/본문 Tab 순환 누락을 최종 후보에서 보완했다. [QA와 후보별 근거](../qa/workspace-return-review.md).

후속은 연결 스크롤 위치와 재실행 후 작업 페이지 복원 계약이다. 음악 revision/Undo와 보기 저장을 분리하고, 오래된 서클·포트·전환이 사라진 문서를 다시 열 때 유효한 상위 화면으로 돌아가야 한다. 기존 전역 단축키와 캔버스의 키보드 진입도 계속 점검한다. 물리 입출력·장치 lifecycle 검증은 별도 출고 조건으로 유지한다.
