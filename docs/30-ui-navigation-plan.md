# 개발 목표 실행 · 0.15 UI 탐색과 가독성

사용자 목표: 개발 계획을 최대한 진행하면서 잘 보이지 않는 UI, 불편한 조작, 지나치게 깊은 탐색을 계속 개선한다. 이 파일의 0.15 범위는 전체 목표의 첫 실행 단계이며 8방향 연결·오디오 장치·파일 import·실시간 엔진·Codex·아티스트 catalog 범위를 완료한 것으로 축소하지 않는다.

## UX 결정

- 다크 단일 canvas, wheel zoom, 원=시간 궤도, 음악·권한·기존 파일 보존. 새 dock/window를 만들지 않는다.
- 상단 `작업 이동` / ⌘J: 일시적인 canvas overlay. 섹션·트랙·역할을 검색하고 MIDI/오디오/음색/연결된 FX/출력을 바로 연다. 반복 섹션은 owner/use ID와 경로로 구분한다. 접힌 그룹은 해당 경로만 펼친다.
- 편집기 상단: 같은 트랙의 연결 경로를 직접 선택. 이전 단계로 축소하고 재확대하는 조작을 없앤다. effect의 track 소유는 실제 output 경로로 추론하며 sidechain 때문에 kick으로 잘못 바뀌지 않는다.
- canvas label: 현재 작업 범위와 직속 child 우선, ancestor title 중복 제거, 고정 읽기 크기와 충돌 회피. 작은 circle의 label도 클릭/더블클릭 가능한 대상으로 쓴다. 숨긴 장식 수준의 세부는 작업 이동에서 계속 접근 가능하다.
- 공통 가용 viewport: breadcrumb/action/console을 고려해 focus/editor/label 배치. 읽기 본문 13pt, 보조 11–12pt, 식별 가능한 선·명확한 focus 상태. macOS native system Korean font 유지.
- keyboard와 search 취소/0건/프로젝트 전환, text input 단축키 충돌, grouped/orphan/multi-output/shared FX를 검증한다. 화면 축소가 음악 clock·note·연결·Undo를 바꾸지 않는다.

## 책임과 검증

DELEGATION_PLAN: none (1 slot). UX → Swift UI implementation → Core navigation/geometry implementation → reviewer/QA를 순차 수행.

- Core: `Sources/CirclrCore/StudioNavigation.swift`, `CanvasLabelLayout.swift`, 필요 시 HierarchyScene camera. owner: navigation/geometry.
- App: `StudioNavigationView.swift`, `CanvasPresentation.swift`, `RootView.swift`, `InlineCircleEditor.swift`, `AlbumCanvas.swift`, `AlbumWorkspace.swift`, `Theme.swift`, AppStore/CirclrApp/CanvasCommands의 연결 부분. owner: native UI.
- Tests: Core navigation + label overlap/hit viewport + 기존 offline regression. 실제 최소 창(1024×772)과 가용 큰 창 QA, 1440×900 geometry 검사, 15-track v4로 검색/직접 이동/FX 전환/edit/Undo/save/reopen. mobile web은 앱 지원 표면이 아니므로 적용하지 않는다.
- README/CHANGELOG/로드맵을 실제 결과로 갱신, version/kit/bundle 일치, private source push와 native screenshot 증거를 남긴다. 기존 musical PCM 비교도 수행한다.
- Git: 승인된 private main, 기존 사용자 작업 보존. 이 목표는 후속 로드맵 작업이 남아 있는 동안 active로 둔다.

## 실행 결과

0.15 패키징과 현재 검증은 [QA](../qa/0.15-review.md)에 기록했다. 사용자가 추가로 요청한 스텝 에디터·기본 DAW 기능과 서브 에이전트 활용은 후속 범위에 통합한다. 실제 sub-agent 생성은 `agent thread limit reached`로 거절되어 현재 1-slot에서 순차 진행한다.
