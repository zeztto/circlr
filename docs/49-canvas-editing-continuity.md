# 배치 전환과 곡선 편집 연속성

2026-09-09, 기준 `773da53`, `codex/daw-integration`. session-bootstrap-v1의 development-lead가 범위와 검증을 조정하고 UI/UX → native Swift utility → 읽기 전용 검토 → QA 순서로 진행한다. 실제 한 슬롯이므로 delegation은 none이다.

## 사용자 결과와 계약

궤도/자유 배치를 바꿔도 선택한 서클의 화면상 중심·반경과 MIDI/스텝/오디오/오토메이션 편집 상태를 유지한다. 메뉴와 명령 검색이 같은 경로를 사용하며 Undo/Redo로 배치를 복원할 때도 적용한다. 다른 프로젝트의 초기 viewport는 기존 복원 경로를 따른다. 배치 전환은 음악 내용을 수정하지 않는다.

오토메이션 ‘전체 점 보기’는 그 시점의 끝 위치를 표시 범위로 고정한다. 마지막 점을 앞으로 움직여도 카메라가 따라 줄어들지 않는다. 범위 밖 점이 생기면 같은 버튼에서 다시 맞출 수 있고, 범위 내에서는 ‘서클 길이 보기’로 돌아온다. 파라미터/원본/서클/프로젝트 전환 시 임시 범위를 초기화한다. MCP displayBeats는 실제 표시 범위와 같다.

궤도 시작과 끝처럼 겹치는 점은 Option 클릭으로 시간 순서대로 순환한다. 일반 클릭은 현재 겹친 선택을 유지해 그 점을 바로 드래그할 수 있다. 선택 점은 마지막에 그려 강조하며 숫자 위치와 접근성 라벨로 구별한다. 데이터 ID·시간·DSP에는 선택만으로 변경이 없어야 한다.

## 실행 소유와 검증

- Native Swift: `AlbumCanvas.swift`, `RootView.swift`, `AutomationEditor.swift`, `AppStore.swift`. 장면 교체 전후 선택 anchor를 카메라에 반영하고 기존 명시 focus 명령과 프로젝트 복원은 우선한다. `CanvasCommands.swift`의 기존 전환도 같은 장면 갱신을 사용한다. 현재 편집 호스트를 불필요하게 제거하지 않는다.
- Core: `HierarchyScene.swift`, 새 `AutomationViewport.swift`, `AutomationDisplay.swift`; `HierarchyGeometryTests.swift`, `AutomationDisplayTests.swift`. 실제 두 레이아웃의 deep node 좌표/반경 보존 왕복, 범위 고정/재맞춤/초기화, 복수 hit 순환·선택 유지 검증.
- QA: `.build/integration-quality`의 targeted 및 offline 전체 Swift, Python MCP/kit, `.build/integration-release` release. build 35 전용 QA 앱과 authored fixture 사본에서 작은 창의 메뉴/명령 전환·Undo/Redo·MIDI/오디오/오토메이션 유지, 끝점 선택/드래그·범위/MCP·저장 복원을 확인한다. 실제 입력·출력·사용자 앱은 이번 실행 대상이 아니다.
- Git: build 35 source/문서/테스트만 승인된 private `zeztto/circlr` 동일 개발 브랜치에 push한다. raw QA 프로젝트·미디어·앱은 제외하며 실제 오디오·VoiceOver와 전체 로드맵 완료를 이 검증으로 대체하지 않는다.

## 실행 결과

Swift 311개·Python 26개와 최종 release를 통과했다. Native 메뉴/검색/Undo/Redo, MIDI·스텝·오디오·오토메이션의 편집 위치/크기, 끝점 선택 후 드래그와 범위 고정/재맞춤을 확인했다. 전체 점 및 배치는 r32에서 처음으로 복원하고 저장 후 재열기를 확인했다. [QA 기록](../qa/editing-continuity-review.md).

Option 클릭 순환은 Core 검사와 native event 연결을 확인했으며 도구가 modifier 유지 클릭을 지원하지 않아 실제 조합 입력은 남았다. 현재 MIDI 궤도 크기·음역 밀도·전환 뒤 MIDI/오디오 키보드 포커스는 별도 UI 개선이 필요하다. 이것을 전체 DAW 사용성 완료로 보고하지 않는다.
