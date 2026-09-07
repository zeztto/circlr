# 0.7.0 한눈에 보는 서클 편집

> 이 문서는 0.7.0 구현·검증 기록이다. 이후 사용자가 섹션 내부도 오디오·MIDI·이펙터 서클을 연결하는 그룹으로 명확히 했다. 최신 목표 UX는 [중첩 서클 모델](13-nested-circle-model.md)을 따른다. 사각 정밀 편집 창은 유지하되, 전체 섹션 구성을 이 창에서만 다루는 구조는 변경 대상이다.

TEMPLATE_VERSION: ux-handoff-v1
BOOTSTRAP: session-bootstrap-v1 / 2026-09-07 / development-lead
OWNER: ui-ux-designer → native-ui-developer → qa → code-reviewer → development-lead
DELEGATION: none / 실행 슬롯 1개, 순차 역할 전환
PREVIOUS_GOAL_TURN: progress / 0.6.0 구현·실행 증거를 남겼으며 이번 목표는 그 구조의 추가 개선

## 완료 조건

사용자 요청은 서클 팝업의 여러 메뉴/탭을 없애고 하나의 뷰에서 대부분의 기능을 보이게 하는 것, 반복 횟수를 외곽 원의 개수로 표현하는 것, 전반적인 조작을 더 직관적으로 만드는 것이다. 단순히 탭 이름을 바꾸거나 모든 기능을 긴 접힘 목록에 넣는 것으로 완료하지 않는다.

- 서클 편집의 navigation tab/state를 제거한다. 기본 크기의 창에서 이름, 마디, 반복, 시작/끝, 템포·박자·스케일·리듬 기준, 선택 트랙, MIDI, 오디오, 이펙트 추가를 동시에 볼 수 있어야 한다.
- MIDI와 오디오를 같은 편집 화면에 유지한다. 트랙은 보이는 선택 목록으로 바꾸고 녹음/가져오기를 각각 직접 노출한다. 빈 상태는 짧은 inline 안내로 표현한다.
- 음악 설정은 현재 유효 값을 바로 편집할 수 있고 편집 시 개별 값이 된다. 상속/글로벌/개별 출처도 같은 위치에 표시하여 전역 변경과 혼동하지 않게 한다.
- 반복은 총 재생 횟수 기준: 1회=테두리 1개, 2회=2개. 모든 지원 값 1…256에 대해 같은 수의 동심원을 만들며 큰 값은 한정된 외곽 폭 안에서 간격을 좁히고 숫자도 병기한다. 화면에서 수백 개를 눈으로 셀 수 있다는 주장을 하지 않는다.
- 노드 hit area·포트·그룹·전체 보기 계산은 실제 외곽 반지름을 따른다. 반복 변경이 연결선 또는 클릭 영역과 어긋나면 실패다.
- 메인 선택 도구막대는 편집 버튼 하나, 즉시 반복 조절, 재사용처럼 송폼 작업에 필요한 동작에 집중한다. 이름·횟수·편집 대상을 명확히 표시한다.
- 다크 모드·휠 줌·단일 메인 캔버스·비모달 사각 창·Esc 및 focus 복원·공유 원본/사용별 변형·저장/undo를 유지한다.

## 구현 경계

API/auth/deploy/OS 설정/오디오 DSP 변경 없음. 기존 .circlr schema와 macOS 14+ 유지. 모든 파일이 untracked인 작업 트리에서 commit/PR 없이 로컬 앱을 갱신한다. 사용자 현재 곡을 먼저 확인·보존하고 QA는 별도 복사본에서 수행한다.

native-ui-developer: `Sources/CirclrApp/{CircleWorkspace,UnifiedSectionView,EditorView,AudioLaneView,CanvasView,CanvasState,AppStore,RootView,Theme,MusicControls,EditorWindow}.swift`, `Sources/CirclrCore/SectionGeometry.swift`, `Tests/CirclrCoreTests/SectionGeometryTests.swift`, `Resources/Info.plist`.
문서: README, CHANGELOG, docs/04, 이 문서. QA: qa/0.7-review.md 및 qa/generated/0.7-*.

음악 편집 창은 기본 약 1180×820으로 넓히고 작은 창에서는 동일 뷰를 스크롤한다. 다양한 이펙트/트랙 수 전체가 어떤 창에도 항상 들어간다는 비현실적인 조건을 만들지 않는다. 정상적인 1–2개 트랙/기본 설정에서 주요 기능을 동시에 노출하고 항목이 많아지면 같은 뷰 안에서 확장한다. 선택 값을 고르는 dropdown은 허용하되 화면을 바꾸는 메뉴/탭으로 기능을 숨기지 않는다.

## 검증 경로

1. `./scripts/swift-local.sh test --filter 'CoreTests|CanvasGeometryTests|SectionGeometryTests|testPlaybackConstructionDoesNotAcquireOutput|testTakeWriterPreservesSamples|testVirtualMIDIReceivesMultiplePackets'` — 기존 core와 휠, 반복 링 개수/반지름/범위, 오디오 길이 geometry.
2. `./scripts/build-app.sh` 및 codesign verify.
3. 실제 앱의 서클 창 첫 화면에서 메뉴 전환 없이 주요 기능이 동시에 표시되는지 screenshot/AX로 확인. 기본·작은 창, MIDI+오디오가 함께 있는 곡, 트랙 변경, 오디오 가져오기/위치, note 입력/수정, 반복과 tempo 변경, undo, 저장/재열기 확인.
4. 반복 1·2·3·8을 실제 캔버스로 확인. 외곽 포트 연결/선택·그룹·fit의 geometry 일치, 큰 반복 값 숫자 보존 확인.
5. 기존 휠 및 별도 창 focus 회귀. 실제 소리와 제3자 plugin 검증은 UI 결과와 분리한다.
6. 최종 목표의 각 항목을 qa/0.7-review.md에서 증거에 대응한 뒤에만 goal complete 처리한다.

## 완료 기록

2026-09-07: 단일 뷰, 공통 시간축, 반복 링, 동일값 상속 유지, 캔버스/창 수명과 저장을 실제 앱에서 확인했다. 모든 1…256 링 geometry 및 관련 자동 검증 22개 통과. 촘촘한 내부 링은 화면 배율에 따라 대비를 낮춰 moiré를 줄인다. 최종 증거와 검토 범위는 [0.7.0 QA](../qa/0.7-review.md)에 기록했다.
