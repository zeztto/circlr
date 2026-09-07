# 0.6.0 다크 캔버스와 별도 편집 창

이전 버전 기록이다. 편집 탭과 진입 버튼 구성은 [0.7.0 단일 뷰 설계](12-unified-section-workspace.md)로 대체됐다.

TEMPLATE_VERSION: ux-handoff-v1
BOOTSTRAP: session-bootstrap-v1 / 2026-09-07 / development-lead
OWNER: ui-ux-designer → native-ui-developer → qa → code-reviewer → development-lead
DELEGATION: none / 동시 실행 슬롯 1개이므로 역할별 순차 실행

## 요청과 방향

송라이터가 곡의 전체 구성을 보면서 서클을 연결·배치하고, 필요할 때 충분히 넓은 MIDI·오디오 편집기를 연다. 0.5의 원 내부 편집과 흰 화면을 이 결정으로 대체한다. 기존 음악 데이터와 재생 엔진은 유지한다.

- 기본 외관은 중성 다크. AppKit와 SwiftUI의 배경·글자·선택·입력 필드를 같은 토큰으로 맞춘다. 한 가지 민트 accent, macOS system sans, 숫자는 monospaced digit를 사용한다.
- 메인 화면은 상단 도구막대와 하나의 캔버스. 좌우·하단 고정 편집 영역을 만들지 않는다.
- 휠 위는 확대, 아래는 축소. 포인터 아래 음악 위치를 유지한다. 물리 휠은 macOS 자연스러운 스크롤 설정의 영향을 정규화하고, 정밀 스크롤 장치는 전달된 방향을 사용한다. Shift+스크롤, 가운데 버튼 드래그, 명시적 이동 도구로 pan한다. 핀치도 지원한다.
- 캔버스에 선택/이동 버튼, 숫자 배율, 전체 보기, 휠·드래그 설명을 노출한다. 직접 조작은 즉시 추종하고 버튼 줌만 짧게 보간한다. Reduce Motion에서는 보간하지 않는다.
- 서클 추가는 선택만 한다. 더블클릭, Return, 선택 서클의 MIDI/오디오 버튼은 별도의 사각 편집 창을 연다. 서클 크기와 캔버스 카메라는 바꾸지 않는다.
- 편집 창 하나를 재사용한다. 열린 상태에서 캔버스의 다른 서클을 선택하면 창 제목과 내용도 함께 전환한다. 빈 선택은 창을 닫는다. 전환 시 note 선택·임시 드래그·패턴 대상은 초기화한다. 프로젝트 교체/대상 삭제 시에도 닫는다.
- MIDI/오디오/구성/음악 설정/이펙트를 창 상단에서 전환한다. 글로벌·트랙·전환 설정도 같은 사각 창을 재사용한다. 창은 이동·크기 변경·닫기가 가능하며 별도 저장 단계 없이 동일 Project/undo를 사용한다.
- 오디오 편집 범위는 실제 가져온 clip의 시작·길이·Gain·템포 추종 속성이다. 파형 편집을 구현한 것처럼 표시하지 않는다.

## 경계와 파일

API/auth/network/deploy 변경 없음. macOS 14+, SwiftUI/AppKit, 기존 .circlr schema 유지. 기존 git 작업은 전부 untracked이므로 commit/branch/PR 없이 로컬 파일과 ad-hoc 앱을 갱신한다. 사용자 복구 곡은 보존한다.

native-ui-developer: `Sources/CirclrApp/{RootView,CanvasView,CanvasState,CircleWorkspace,EditorView,CirclrApp,AppStore,MusicControls,InspectorView,Theme,EditorWindow}.swift`, `Sources/CirclrCore/CanvasGeometry.swift`, `Tests/CirclrCoreTests/CanvasGeometryTests.swift`, `Resources/Info.plist`.
doc-updater: README, CHANGELOG, docs/04, 이 문서. qa: `qa/0.6-review.md`, `qa/generated/0.6-*`.

## 인수와 검증

1. `./scripts/swift-local.sh test --filter 'CoreTests|CanvasGeometryTests|testPlaybackConstructionDoesNotAcquireOutput|testTakeWriterPreservesSamples|testVirtualMIDIReceivesMultiplePackets'` — 줌 방향/범위/커서 고정, 기존 core 회귀.
2. `./scripts/build-app.sh` — release 빌드, bundle version, codesign 확인.
3. 실제 앱에서 modifier 없는 휠 up/down → 배율 증감, 같은 포인터 기준으로 이동. 버튼 줌·전체 보기·이동 도구·그룹 드래그 확인.
4. 서클 추가는 창을 열지 않음. MIDI/오디오 창은 요청할 때만 생성. 더블클릭 후 사각 창 이동·크기 변경, note 입력·이동·삭제·undo·저장, 탭 전환, 창 닫기와 재열기, 다른 서클 선택, 프로젝트 교체 확인.
5. 큰 창과 작은 데스크톱 창에서 다크 외관·가독성·클리핑·상태 문구 확인. native macOS 도구라 모바일 viewport는 대상 아님.
6. 최종 오디오 소리는 0.5 시스템 CoreAudio 대기 문제가 풀린 경우만 별도 확인. 이번 UI 검증을 실제 소리 검증으로 대체하지 않는다.

## 구현 중 발견하고 수정한 사항

- 숨긴 메인 제목 표시줄은 CUA 좌표 입력에서 windowNotFoundAtPosition을 발생시켰다. 기본 macOS 창 프레임을 유지한 뒤 실제 휠 입력을 확인했다.
- ViewBuilder의 여러 view에 maxHeight를 적용해 탭이 편집 영역을 밀어내던 문제를 VStack 컨테이너로 수정했다.
- 최소화한 창의 isVisible=false를 자동 열기 조건으로 사용하면 캔버스 선택 시 창이 다시 올라왔다. editorActivation이 바뀔 때만 명시적으로 복원·활성화하도록 수정했다.
- 키 포커스에 따라 SwiftUI onExitCommand가 동작하지 않는 설정 화면은 NSWindow의 cancelOperation/keyDown으로 Esc를 처리한다. 닫힌 창에 close를 반복 호출하지 않고 메인 창을 명시적으로 활성화한다. 캔버스는 첫 mouseDown을 수용하며 V/H/F는 한글 입력에도 같은 물리 키 위치로 처리한다.

최종 범위와 실행 증거는 [0.6.0 QA 기록](../qa/0.6-review.md)에 기록한다.
