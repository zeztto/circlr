# 편곡안 직접 검색 — build 63

session-bootstrap-v1: development-lead, baseline=38f2212, branch=codex/daw-integration. 직전 build62 구현/native/private push는 progress다. 제공된 1 slot과 직전 실제 thread limit을 근거로 UX → Core/native UI → 읽기 전용 review → QA 순차 역할 전환을 사용한다.

## UX와 음악 계약

현재 InlineCircleEditor의 곡·악장 설정 안 StudioChoice는 이름만 나열한다. 이를 단일 캔버스 overlay 검색으로 바꾸고, 곡·악장 서클 상단의 편곡안 버튼과 ⌥⌘J·명령 검색으로 직접 연다. 섹션/MIDI/음색 안에서는 그 작업을 소유한 곡·악장에 대해 단축키를 쓸 수 있다. 편곡을 직접 소유하지 않는 상위 곡/앨범에서는 임의 하위 대상을 고르지 않는다.

850×560 기존 검색 규격을 따른다. 소유 곡·악장 이름과 `앨범 재생에 사용할 편곡안`을 명시하고, 선언된 arrangementIDs 순서의 #번호·이름·섹션 수를 표시한다. 이름은 최대 두 줄/전체 help·AX, Unicode/전각/#정확한 순번 검색을 지원한다. 현재 편곡 찾기는 검색을 초기화하고 실제 selectedArrangementID를 강조한다. ↑↓/Return/Esc를 쓰며 배경 캔버스 AX·키보드·drop을 차단한다. 새 고정 창·좌우 패널은 만들지 않는다.

검색 진입/필터/취소/현재 재선택은 음악·Undo/Redo·현재 캔버스 위치를 보존한다. 다른 편곡 선택은 기존 AlbumEditing.selectArrangement의 재생 선택 의미로 한 번 mutate한 뒤 소유 composition으로 이동한다. 다른 composition·원본 섹션·track·asset·편곡 내용은 보존한다. 요청은 프로젝트·revision·세션·현재 선택/원본/편집 상태와 소유 composition ID를 고정한다. 대상/음악 변경·녹음/준비/import 중이면 결과를 비활성화하고 재진입 안내를 보인다. 다른 검색/명령/프로젝트 열기에서 overlay를 정리한다.

작성 중인 이름이 있다면 기존 이름 확정 규칙으로 먼저 적용한 뒤 요청을 고정한다. 이름 오류는 원래 필드에서 해결하며 검색 뒤에 늦은 이름 commit이 들어가 새 요청을 즉시 무효화하지 않도록 한다.

## 소유와 검증

Core ArrangementSelection.swift/관련 테스트: 목록·검색·소유 검증/no-op/변경 범위. Native App ArrangementPickerView.swift, AppStore/RootView/InlineCircleEditor/AlbumWorkspace/CirclrApp/CanvasCommands와 overlay 전환·키보드/drop 진입점. Info build63, README/CHANGELOG/docs25/31/77, QA helper/보고서. 오디오 엔진·MCP·원본 앱/root/ports/곡은 보존한다.

Core 테스트 후 전체 Swift(기존 물리 playback 제외)/Python/키트/release를 검사한다. authored fixture의 여러 곡·동명/긴 이름/많은 편곡에서 직접 버튼·단축키·명령 진입, #전각/한글 검색, 키보드 선택·no-op/Redo 보존·단일 Undo·다른 소유 거절·외부 변경 안내·다른 overlay 왕복·저장 재열기를 native로 확인한다. 1024px 창/콘솔 상태의 실제 픽셀·AX·원본/전체 음악 데이터·최종 소스/앱/kit를 대조한다. 가짜 곡/샘플 데이터는 QA에만 두고 제품 목록은 실제 프로젝트에서 읽는다. 물리 재생은 이 UI 검증과 별도다.

## 실행 결과와 후속 범위

build63 구현·검증 완료. Swift457개·Python28개와 최종 release, 실제 2곡/67편곡·26상태·24화면을 검사했다. 설정 검색 버튼이 스크롤 아래 가려지는 것을 발견해 설정 맨 위로 옮겼다. 현재 재선택/Redo, 다른 곡 범위, 이름 확정, 오래된 요청, 빈 편곡, 저장/재열기와 최종 소스·앱 보존 근거는 [QA 보고서](../qa/arrangement-search-review.md)에 있다. 사용자 재요청에 따른 독립 review dispatch도 실제 thread limit으로 거절돼 순차 검토했다.

다음 UI slice는 `HierarchySettingsEditor`의 `다음 섹션 연결` 메뉴다. 많은 섹션과 동명 사용을 번호·경로로 구분하고, 기존 연결의 생성/재생 경로/전환/해제를 한 화면에서 찾는 UX를 먼저 정한다. 기존 PortConnectionsEditor의 직접 연결 흐름을 확인해 중복 검색 화면을 만들지 않는다. 음악 설정의 스크롤 깊이는 현재 출처/유효값·직접 입력/Undo·원본 범위를 보존하는 별도 계약으로 다룬다. 물리 I/O 출고 조건은 이 UI 완료와 분리해 유지한다.

섹션 연결의 후속 slice는 [build64 계약](78-section-connection-workspace.md)과 [QA](../qa/section-connection-review.md)에서 구현·검증했다. 음악 설정/작업 복귀는 다음 범위로 유지한다.
