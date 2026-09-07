# 재생 비주얼라이저와 팔로우

상태: 구현·native 검증 · 0.11.0

## 사용 경험

하나의 캔버스에서 재생 위치와 신호 흐름을 함께 읽는다. 활성 서클은 실제 소리의 세기에 반응하는 얇은 외곽 파동과 궤도 잔상을 표시한다. 연결선 위의 작은 빛은 OUT에서 IN으로 이동한다. MIDI는 실제 예약된 노트의 velocity와 길이를, 오디오·악기·이펙트·믹스는 렌더된 PCM의 envelope를 사용한다. 임의의 가상 음량을 만들지 않는다.

상단 재생 버튼 옆에 `재생 팔로우`를 둔다. 기본은 켜짐이며 재생을 시작하면 현재 섹션을 화면의 작업 영역에 맞춘다. 재생 섹션이 바뀌면 부드럽게 다음 섹션으로 이동한다. 현재 섹션 안에서는 카메라가 안정적으로 유지되고 궤도 재생점이 움직인다. 전환 중 동시 재생은 두 섹션 모두 표시하며 팔로우는 늦게 시작한 섹션을 따른다. insert 전환은 앞 섹션을 유지하고, 최종 잔향에서는 마지막 위치를 유지한다.

휠·핀치·캔버스 드래그·선택·정밀 편집 또는 명시적 focus를 시작하면 이번 재생의 팔로우를 일시 중지한다. 버튼은 `팔로우 재개`로 바뀐다. 선택·Undo·음악 상태는 카메라 팔로우가 바꾸지 않는다. 정지하면 잔상·입자도 멈추고 사라진다. macOS 동작 줄이기 설정에서는 이동 입자·파동을 생략하고 재생점과 활성 색을 유지한다.

## 실행 소유권과 파일

1. native audio/core: `Sources/CirclrAudio/PlaybackAnalysis.swift`, `Renderer.swift`, `SectionGraphRenderer.swift`, `Sources/CirclrCore/PlaybackPosition.swift`. 렌더 준비 단계에서 작은 60 Hz envelope를 추출하고 재생 시간과 section/composition/source phase를 결정한다.
2. native app: `Sources/CirclrApp/PlaybackVisualization.swift`, `AlbumCanvas.swift`, `AppStore.swift`, `RootView.swift`, `CanvasState.swift`, `AgentWorkspace.swift`. 표시 루프·신호 그리기·팔로우 상태·컨트롤·읽기 전용 에이전트 상태를 연결한다.
3. QA: `Tests/CirclrCoreTests/PlaybackPositionTests.swift`, `Tests/CirclrAudioTests/PlaybackAnalysisTests.swift`, `qa/0.11-review.md`, 검증용 `.circlr` 사본 및 native 화면 증거.
4. 패키징: `Resources/Info.plist`, `README.md`, `CHANGELOG.md`, `dist/써클러.app`. 0.11.0 로컬 앱으로 빌드한다.

단일 실행 슬롯에서 역할별 순차 수행한다. 기존 untracked workspace를 보존하고 이번 변경만 검토한다. commit·원격 배포는 범위가 아니다.

## 정확성과 비용

- 기준 시간은 AVAudioPlayerNode의 실제 sample time이다. 표시 타이머 자체의 누적 시간을 곡의 시간으로 사용하지 않는다.
- envelope는 준비된 오디오와 함께 보존한다. 실시간 오디오 callback에 UI·파일 작업을 넣지 않는다.
- 연결되지 않은 가지, 음소거된 출력 경로, gain 0 연결에 신호를 만들지 않는다. 반복·템포 변경·동시 섹션·잔향을 분리한다.
- 재생된 plan과 프로젝트의 musicRevision이 다르면 해당 그래프의 표시와 자동 팔로우를 멈춘다. 상태에서 다시 재생해야 반영됨을 알린다.
- 시각화 데이터는 선택적으로 생성하며 WAV·바운스의 PCM을 변경하지 않는다. 정지·최소화·가려진 창에서는 화면 프레임 작업을 멈춘다.
- 콘솔과 상단 조작 영역을 제외한 작업 영역을 기준으로 섹션을 맞춘다.
- 콘솔 표시와 크기가 바뀌면 다음 표시 프레임에서 작업 영역을 다시 계산한다. 화면 탐색으로 팔로우를 멈춘 뒤에는 마지막으로 보던 가지가 편집 선택 때문에 가려지지 않도록 유지한다.
- 입자의 이동 속도와 처리 노드의 회전은 흐름을 읽기 위한 표현이다. 플러그인 내부의 지연 시간을 측정하거나 새 소리를 생성하는 기능은 아니다.
- MCP의 `snapshot.playback.seconds`는 실제 시간이고 `displaySeconds`·신호·phase는 마지막 표시 프레임 기준이다. 최소화 중 마지막 프레임의 값은 그대로 유지된다.

## 검증 계약

`./scripts/swift-local.sh test`를 격리된 module cache에서 실행한다. 실제 오디오가 있는 fixture로 envelope와 MIDI 시간, 무음·음소거·gain 0·분리된 경로·잔향을 검증하고 시각화 사용 전후 PCM이 일치하는지 비교한다. 순수 시간 함수는 반복·변박·local tempo·겹침·insert와 선택 섹션 재생을 검증한다.

검증 앱은 기존에 승인된 `com.circlr.hierarchyqa`와 별도 복구 위치를 사용한다. 사용 중인 검증 앱의 dirty 상태부터 확인하고 필요한 사본을 보존한다. f0r h3r 사본으로 신호 이동, 섹션 팔로우, 사용자의 수동 조작·재개, 정지, 최소화 중 재생, 1024×740 이상의 화면과 콘솔 표시 상태를 확인한다. production 복구 파일은 사용하지 않는다.

실행 결과와 검증 한계는 [0.11 검증 기록](../qa/0.11-review.md), 자동 native 시나리오는 [실행 스크립트](../qa/verify-playback-native.py)에 기록한다.
