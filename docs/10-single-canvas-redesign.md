# 0.5.0 하나의 캔버스로 편집하기

> 역사 기록: 원 내부 편집과 밝은 외관은 0.6.0의 [다크 캔버스·사각 편집 창](11-dark-canvas-editors.md)으로 대체됐다. 아래 결과는 0.5.0 당시의 검증이다.


사용자 피드백: 움직임이 자연스럽지 않고 UI가 거칠다. 좌·우·하단의 별도 작업 영역을 원하지 않으며 하나의 큰 화면 안에서 모든 작업을 수행한다.

## 구현 전 계약

- 소유: UX는 p1zza-ui-ux-designer, 구현은 native-ui-developer, 검증은 qa. 실행 슬롯 1개라 순차 수행한다.
- 범위: `Sources/CirclrApp/`, 순수 이동 수학은 `Sources/CirclrCore/CanvasGeometry.swift`, 관련 Tests, 문서와 버전. audio engine/프로젝트 음원은 보존한다.
- Git: 기존 미커밋 작업을 유지하고 같은 workspace에서 수정. 외부 배포/commit/PR 없음.
- 화면: 단일 AppKit canvas + 작은 상단 도구. `HSplitView`, 좌측 library, 우측 inspector, 하단 editor 영역 제거.
- 진입: 서클 double-click/Return → 원이 확대되며 내부에 편집 내용을 표시. 이는 canvas에 붙은 view이며 별도 window나 화면 가장자리 panel이 아니다.
- 복귀: Esc/송폼으로 버튼 → 이전 camera 위치로 돌아가며 같은 원과 연결을 유지한다.
- 세부 기능: 원 내부의 연주/설정/이펙트 전환. track·take·rhythm·arrangement는 메뉴에서 선택. 글로벌 설정·연결 전환·Audio Unit GUI도 동일 canvas 안에서 연다. OS 열기/저장 및 마이크 권한 dialog는 OS의 파일/권한 처리에 한해 유지한다.
- 이동: pointer 이동은 grid와 무관하게 연속 추종. drop할 때 선택 전체를 한 번 snap하며 상대 간격 유지. 이동 하나는 undo 하나.
- 카메라: pan/zoom은 view-local preview, pointer/viewport center 기준 zoom. 최종 상태만 저장한다. 확대 애니메이션은 짧게 공간 관계를 설명하며 Reduce Motion이면 즉시 적용한다.
- 갱신: 정지 상태 timer가 전체 ObservableObject를 갱신하지 않는다. 재생 시간은 별도 meter object에 분리하고 canvas는 필요한 때만 갱신한다. 음악 plan/context는 revision별 cache.
- 시각: 흰 기능성 canvas, 낮은 대비의 dot grid, 읽기 쉬운 원형 링/섹션명, 차분한 중립색과 단일 accent. macOS system font의 한국어 fallback을 사용한다. web/mobile view는 대상이 아니며 1440×900 및 1024×768 desktop을 검증한다.

## 인수 시나리오

1. 빈 프로젝트와 기존 곡에서 캔버스가 창을 채우고 split/sidebar/bottom editor가 없다.
2. 서클 추가→원 안에서 MIDI 입력→다른 트랙→설정→재생→Esc. 별도 편집 창이 나타나지 않는다.
3. 글로벌·전환·사운드 노드 편집도 동일 캔버스에서 접근할 수 있다.
4. drag 도중 부드러운 pointer 추종, release snap, undo, group 상대 간격, cursor 고정 zoom 수학을 확인한다.
5. 확대/복귀 후 원래 공간 위치와 camera가 유지된다. 별도 playback state update로 모델 전체를 매 frame 재구축하지 않는다.
6. 실제 native 앱에서 이동·확대·note·템포 수정·저장/열기, 화면 두 크기와 음원 회귀를 확인한다.

검증: `./scripts/verify.sh` + CUA 실제 앱 조작. 측정하지 않은 FPS/latency 또는 사용자의 주관적인 자연스러움 만족을 완료 근거로 주장하지 않는다.

## 검증 중 확인한 초기화 문제

0.5 첫 native 실행에서 Playback.init의 engine.mainMixerNode가 시스템 출력 장치 IPC를 기다리며 창 표시를 막는 stack을 확인했다. 범위를 Playback.swift의 출력 연결 시점으로 한정해 실제 재생 시 한 번 연결하도록 변경한다. 음원 render나 프로젝트 음악 데이터는 바꾸지 않는다. 초기화 후 장치 접근 여부와 재생 회귀를 다시 검증한다.

## 0.5.0 실행 결과 — 2026-09-07

### 화면과 움직임: 통과

CUA로 `dist/써클러.app`의 실제 창과 접근성 트리를 확인했다. 기존 1440×980 창, 새 기본 1440×900 창, 직접 모서리를 끌어 줄인 약 1030px 폭의 작은 창에서 검증했다. 도구가 창 이미지를 리사이즈하므로 작은 창의 정확한 논리 pixel 크기까지 측정했다고 주장하지 않는다. 최종 작은 창에서 MIDI 첫 박 숫자와 트랙·입력·건반·탭이 잘리지 않는 것도 확인했다.

- 빈 곡이 하나의 캔버스를 채운다. 예전 좌측 library / 우측 inspector / 하단 editor와 split handle이 없다. 작은 보기·정렬·zoom 도구는 캔버스 위에 표시된다.
- 서클 추가 → 원 내부의 구성에서 `Verse`로 이름 변경 → 음악 설정에서 개별 96 BPM → Esc 복귀. 실제 링에 `96 · 4/4` 표시를 확인했다.
- 서클을 끌어 옮기고 ⌘Z 한 번으로 원위치 복귀, 다시 실행, 중심 기준 확대를 수행했다. 저장한 위치는 `(336,144)`, zoom은 `1.2`였다.
- 글로벌 설정, 연결 전환, 사운드 source의 악기·출력 설정이 원 내부에서 열린다. 새 native 편집 window나 edge panel이 생기지 않는다.
- 저장된 `.circlr`를 native 파일 선택기로 다시 열고 음악 설정과 위치가 복원되는 것을 확인했다.
- 원 안에서 MIDI note 3개 입력 → note 이동 → 저장. JSON의 사용별 lane override에 실제 note 3개가 보존됐다.
- 다시 사용으로 두 번째 서클 → 포트 드래그로 연결 → 연결을 두 번 클릭하여 전환 편집 → 영역 선택 → ⌘G → 그룹 제목 드래그 → 저장.
- 그룹 이동 후 위치는 `(475,208)`과 `(720,288)`. 재사용할 때의 상대 간격 `(245,80)`이 그대로 유지됐다. 그룹 하나, 연결 하나, 각각의 사용별 note 3개를 저장 파일에서 확인했다.
- 오디오 준비가 시스템 장치를 기다리는 중에도 정지 버튼과 Esc가 응답하고 다시 캔버스 편집으로 돌아왔다.
- 새 앱의 정지 상태에서 `ps`로 한 번 관측한 CPU는 0.2%였다. 이전 0.4 앱은 같은 세션에서 99.4–100%였고 main thread의 SwiftUI layout 반복 stack을 기록했다. 이는 FPS나 latency benchmark가 아니다.

화면 이미지는 이 작업 대화의 native screenshot 출력에 남아 있다. 데이터 근거는 [0.5 UI 기록](../qa/generated/0.5-ui-evidence.json), 화면에서 저장한 곡은 [검증 곡](../qa/generated/single-canvas-ui.circlr/manifest.json)이다. 이 곡은 앱 번들에 포함하지 않는다.

### 자동 검증

- 초기 UI 구현 직후 `./scripts/verify.sh`: 기존 Core 10 + 새 camera 4 + Audio 6 = **20개 통과**, 2026-09-07 12:07:11 KST. 이후 오디오 초기화/취소 보완 전 결과다.
- 이후 실제 출력 장치 IPC 대기를 확인해 `Playback.init`의 출력 연결을 재생 시점으로 늦췄고 연결 작업을 main thread에서 분리했다. 미리듣기도 장치 연결을 분리하며 정지/곡 변경 후 늦은 완료를 세대 번호로 무효화한다.
- 최종 장치 비의존 선택 검증: **17개 통과**, 실패 0. Core 14 + 출력 장치를 연결하지 않는 Playback 생성 1 + TakeWriter 1 + virtual MIDI 1.
- Release build와 `codesign --verify --strict` 통과. [최종 빌드 기록](../qa/generated/0.5-build.log), [선택 테스트 기록](../qa/generated/0.5-targeted-tests.log).

재현 명령:

```sh
./scripts/build-app.sh
./scripts/swift-local.sh test --filter 'CoreTests|CanvasGeometryTests|testPlaybackConstructionDoesNotAcquireOutput|testTakeWriterPreservesSamples|testVirtualMIDIReceivesMultiplePackets'
```

### 오디오 재검증: 환경 대기로 미완료

12:11 이후 전체 테스트는 CoreAudio의 `AudioDeviceGetProperty` / 장치 IPC에서 멈췄다. 이 실행을 통과로 기록하지 않는다. 현재 native 앱에서도 실제 소리의 재생과 WAV 재출력 완료를 재검증하지 못했다. 출력 장치 재연결/시스템 오디오 복구 후 `./scripts/verify.sh`와 native 재생을 다시 확인해야 한다. 다른 앱에 영향을 주는 시스템 오디오 서비스 재시작은 수행하지 않았다.

UI 편집·저장·취소 응답은 이 대기 상황에서 확인했다. 실제 마이크, 제3자 Audio Unit GUI 호환성, Reduce Motion 환경 설정을 켠 실기 동작, trackpad 관성의 주관적 느낌은 이번에 검증 완료로 표시하지 않는다. Reduce Motion 분기와 Audio Unit의 동일 canvas embedding은 구현/코드 확인 범위다.

### 기존 작업 보존

응답 없던 0.4 앱을 종료하기 전 자동 복구 JSON을 `qa/preserved/2026-09-07-before-ui-update/`에 복사했다. 원본 복구 JSON은 그대로 유지하며, `chorus` 서클이 든 내용을 열 수 있는 `복구된 곡.circlr` package도 같은 폴더에 보관했다. 이 폴더는 Git 추적에서 제외했다. 메모리에만 있고 자동 복구 파일에 기록되지 않은 변경까지 보존됐다고 주장하지 않는다.

### 코드 검토

세션 전체가 미추적 파일 상태라 staged/unstaged diff 대신 실제 변경 파일을 직접 검토했다. 이전 inspector root의 사용하지 않는 분할 UI를 제거했다. 장치 초기화의 main-thread 대기, 중단 후 지연 미리듣기 실행 가능성을 수정했다. 실제 오디오 완료와 제3자 plugin GUI는 환경 제한으로 남긴다. 사용자의 자연스러움/시각 품질 만족을 자동 테스트로 대신하지 않는다.

최종 앱에는 보존된 사용자 `chorus` 곡을 다시 열어 두었다. 원본 복구 JSON과 열 수 있는 package를 각각 유지했다.
