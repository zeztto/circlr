# 앨범 전체를 편집하는 중첩 서클 작업 공간

TEMPLATE_VERSION: session-bootstrap-v1
DATE: 2026-09-07
ACTIVE_ROLE: development-lead → architecture/core → native-ui → qa
COMMUNICATION_MODE: concise Korean
PREVIOUS_GOAL_TURN: progress / 섹션 내부 그래프 설계 문서 작성
DELEGATION: none / 실행 슬롯 1개, 순차 역할 전환
STATUS: 구현 중; 전체 목표 완료 아님

## 목표와 확정된 변경

전체 앨범을 곡·악장 서클로 구성하고, 그 안의 섹션과 오디오·MIDI·이펙터를 모두 서클로 편집한다. 확대할수록 같은 캔버스에서 노트·파형·이펙트의 상세 편집이 가능해야 한다. 사용자가 이번 답변으로 **같은 캔버스에서 직접 정밀 편집**을 선택했다. 이전 사각 편집 창 중심 UX와 `곡→섹션→음악`까지만 다루던 제안은 이 목표로 확장한다.

앨범/곡/악장은 공간적 folder에만 그치지 않고 저장되는 음악 구성이다. 곡마다 편곡안을 유지하고, 앨범 순서 및 곡 안 악장의 순서와 섹션의 실행 경로를 구분한다. 상위 서클을 접거나 이동해도 내부 ID·연주 시간·효과·연결을 보존한다. 글로벌 설정과 각 수준의 상속·개별 설정을 유지한다.

## 경계와 작업 순서

1. **Core / 저장** — `Sources/CirclrCore/{Model,AlbumModel,Compiler,Editing,ProjectStore}.swift`, `Tests/CirclrCoreTests/AlbumTests.swift`. 앨범의 곡·악장 포함 관계와 재생 순서, 편곡안 소유권, 상속, 기존 곡의 명시적 migration, package round-trip을 구현한다. 기존 asset와 섹션 ID를 보존한다.
2. **내부 음악 그래프 / 실행** — `Sources/CirclrCore/{SectionGraph,SectionGraphCompiler}.swift`, 기존 Model/Compiler/Editing, `Sources/CirclrAudio/Renderer.swift`와 core/audio 테스트. 실제 오디오·MIDI 데이터, 악기와 효과 경로, local clock, 반복, 원본/사용별 변형을 연결한다. 기존 per-track effect 위치와 plugin state를 보존한다.
3. **Native 계층 캔버스** — `Sources/CirclrApp/{AlbumCanvas,AlbumWorkspace,CanvasState,AppStore,RootView,CanvasView}.swift`. 실제 앨범 데이터로 중첩 원을 표시하고, 카메라·선택·생성·이동·연결·이름·삭제·undo를 구현한다. 같은 캔버스에서 깊이를 바꾸고 상위/전체로 복귀한다.
4. **직접 정밀 편집** — `Sources/CirclrApp/{EditorView,AudioLaneView,UnifiedSectionView,CircleWorkspace,EditorWindow,MusicControls}.swift`와 새 캔버스. MIDI·파형·clip 속성·effect parameter를 확대된 서클의 작업 영역에서 편집한다. 선택 대상의 stable ID와 지연 callback을 검증한다. plugin이 제공하는 native 창은 plugin 자체의 별도 제약이다.
5. **통합/검증/배포본** — 전체 core 테스트, 필요한 audio 테스트, app build 및 native CUA 검증. 현재 사용자 곡을 보존한 QA 사본에서 열기·편집·undo·저장/재열기·재생/내보내기와 닫기 최소화를 확인한 뒤 README/CHANGELOG/Info.plist/검증 기록을 갱신한다.

변경은 로컬 untracked 작업 트리에서 수행한다. 자동 commit/PR/원격 배포는 없다. 기존 앱과 사용자 package는 최종 통합 전 보존한다. OS 오디오 설정·외부 계정·서버·인증 변경은 필요하지 않다. 모델과 UI를 다른 데이터 원본으로 만들지 않는다.

## 검증 명령과 실제 시나리오

- `./scripts/swift-local.sh test --filter AlbumTests` — 부모/자식/편곡 소유권, 잘못된 계층 거부, 깊은 상속, 순서, migration·save/load.
- `./scripts/swift-local.sh test --filter 'SectionGraphTests|CoreTests|CanvasGeometryTests|SectionGeometryTests'` — routing·local 시간·기존 곡 동작·geometry.
- `./scripts/build-app.sh` — macOS native 빌드. 실제 검증 전에는 기존 dist 앱을 교체하지 않는 별도 SwiftPM build로 컴파일을 확인한다.
- Native: 빈 앨범에 곡 2개와 악장 생성 → 섹션 2개 연결 → MIDI/오디오/악기/이펙트 연결 → 휠로 확대해 note·clip·effect 직접 편집 → 앨범으로 축소 → 곡 이동 → undo → 저장/재열기. 같은 계층과 음악 결과가 남아야 한다.
- 앨범 순서의 곡·악장과 각 섹션 반복이 실행/내보내기에 반영되어야 한다. 장치 없는 core 검증으로 실제 소리 성공을 대신하지 않는다.

## 완료 감사표

| 요구 | 필요한 증거 | 상태 |
|---|---|---|
| 앨범의 곡·악장 서클 | 저장 모델 + native 생성·이동·순서 편집 | 완료 · 아래 최종 증거 참조 |
| 곡·악장 안 섹션 서클 | 포함 관계 + native 확대/복귀 + 재생 순서 | 완료 · 아래 최종 증거 참조 |
| 섹션 안 MIDI·오디오·이펙트 | 실제 payload·routing + 저장/소리 검증 | 완료 · 아래 최종 증거 참조 |
| 같은 캔버스 직접 상세 편집 | 실제 note·waveform/clip·effect 편집, 별도 필수 창 없음 | 완료 · 아래 최종 증거 참조 |
| 상속·개별 시간·설정 | 계층별 resolver·clock 검증 | 완료 · 아래 최종 증거 참조 |
| 기존 곡 보존 | 원본 hash·migration·round-trip·효과 적용 결과 | 완료 · 아래 최종 증거 참조 |
| 실제 앱·앨범 실행 결과 | native UI 및 오디오·export 검증 | 완료 · 아래 최종 증거 참조 |

중간 단계의 테스트 통과나 문서 작성만으로 이 목표를 완료 처리하지 않는다.

## 진행 기록

2026-09-07 core 1차: `AlbumModel.swift`에 곡·악장 tree, 편곡안 소유권, 명시적 기존 곡 확장, 필드별 상속, 앨범 실행 계획을 구현했다. `Model`/`Compiler`/`Editing`/`ProjectStore`와 연결했다. 새 테스트 9개와 기존 core/geometry 19개를 통과했다. 상세 증거는 [앨범 core 검토](../qa/album-core-review.md)에 있다. 완료 감사표는 전체 native 동작이 검증될 때까지 미완료 상태로 유지한다.

2026-09-07 core 2차 및 native 1차: SectionGraph/변형/compiler/renderer, 실제 파형 로더, 계층 scene/camera, AlbumCanvas/InlineCircleEditor를 구현했다. fresh build 및 46개 자동 검증을 통과했다. 별도 QA 앱에서 같은 캔버스 MIDI 입력, 오디오 파형 trim/undo/redo, Delay 삽입, 2곡/2악장/3섹션 저장과 50초 실제 WAV export, 재생 진행을 확인했다. [중간 검증](../qa/hierarchy-native-review.md), [현재 아키텍처](15-hierarchy-canvas-architecture.md)를 기록했다.

2026-09-07 최종 통합: 위 기능을 모두 연결했다. 최종 61개 테스트와 native 편집/저장/복원/오디오 결과는 `qa/hierarchy-native-review.md`에 기록했다. 0.8.0 로컬 bundle을 준비하고 이전 0.7.1을 archive에 보관한다. 실제 외부 MIDI 장치·마이크와 임의 third-party Audio Unit의 전 조합은 검증하지 않았다. 현재 완료 범위는 앨범 계층과 같은 캔버스 직접 편집이며, 실시간 전체 DAW 엔진 완성을 뜻하지 않는다.
