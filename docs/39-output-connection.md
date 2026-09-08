# 출력 연결 상태 · 대기와 재생 취소

2026-09-08, 기준 `91b419e`, `codex/daw-integration`. 이전 턴은 framing 구현·native 검증·private push로 progress다. development-lead → UI/UX 계약 → native Swift utility → 같은 실행자의 read-only 검토 → QA 순서. 실제 도구 한도에 의해 delegation none이며 이전 spawn 실패를 반복하지 않는다.

## 계약

관찰된 cold 연결은 백그라운드 `AVAudioEngine.mainMixerNode`의 HAL 호출에서 대기하며, 현재 10초 timeout 뒤에도 연결 Task는 살아 있다. 이를 숨긴 채 오류만 표시하면 사용자는 음악 준비와 장치 대기를 구분할 수 없다. 이 단계는 HAL 지연을 해결했다고 주장하지 않고 실제 작업 수명과 조작 상태를 일치시킨다.

- 기존 재생 시계 아래의 좁은 한 줄에 출력 연결/대기 시간·늦은 준비 완료를 표시한다. 별도 패널은 추가하지 않는다. tooltip/접근성 설명은 지금 정지 가능한 대상이 재생 요청이며 시스템 연결 작업이 남아 있음을 설명한다.
- 물리 연결은 한 번 시작해 공유한다. 재생 대기 취소·timeout·재시도는 새 물리 작업을 만들지 않는다. monotonic 시간으로 timeout과 경과를 계산한다.
- 연결 단계(플레이어 연결, 시스템 출력 응답, 믹서 연결), 실제 phase, 재생 대기 outcome, attemptID/횟수를 snapshot으로 제공한다. raw 장치 정보나 계정 정보는 읽지 않는다.
- 정지/Task 취소/새 요청은 늦은 완료에 의한 자동 재생을 막는다. timeout은 nonmodal 상태로 표시하고 음악 편집을 계속 허용한다. 실제 engine 오류는 기존 오류 처리를 유지한다.
- 출력 연결 snapshot은 GUI/콘솔/MCP가 공유한다. 연결 준비 완료 후에는 사용자가 다시 재생해야 한다. 정상 재생 시 상태 줄은 숨긴다.

## 소유와 파일

native Swift utility: 새 `Sources/CirclrAudio/PlaybackOutputConnection.swift`, `Playback.swift`, `Tests/CirclrAudioTests/PlaybackOutputConnectionTests.swift`. MainActor 상태와 단일 detached 장치 작업을 분리하고 제어된 연결 지연으로 취소/timeout/재시도를 검사한다. 입력 녹음과 PCM은 변경하지 않는다.

App utility: `Sources/CirclrApp/AppStore.swift`, 새 `PlaybackOutputStatus.swift`, `RootView.swift`, `AgentWorkspace.swift`, 필요 시 `MovieRecording.swift`. 상태 publication은 단계 변화/정수 초 변화에 제한한다. 음악 render generation/정지 gate를 유지한다. MCP 응답은 additive이며 도구 schema와 키트는 바꾸지 않는다.

QA/doc utility: build 25, 별도 버전 QA 앱과 authored fixture. `README.md`, `CHANGELOG.md`, roadmap, 전용 QA 문서·helper. 사용자 0.19 앱, 이전 QA 앱/프로젝트·소스 branch는 보존한다. 실제 마이크·장치/TCC 변경은 하지 않는다.

## 검증과 Git

Native 후속 범위: 재생 팔로우가 MIDI 편집기를 제거한 뒤 Space 정지가 소실되는 것을 관찰했다. `AlbumCanvas.swift`의 편집기 제거 경로를 통합해 제거 대상 내부의 first responder/field editor만 캔버스로 옮기며 콘솔·외부 입력 포커스는 건드리지 않는다. `PlaybackVisualization.swift`의 `canvasKeyboardFocus`로 실제 포커스를 기록하고 MIDI 편집기→재생 follow→Space 정지와 콘솔 입력 보존을 확인한다.

1. 제어된 연결 테스트: timeout/취소/동시 요청의 late completion, 단일 물리 attempt, ready 재사용, 상태 순서. Task 취소가 기존/다음 요청에 섞이지 않음을 검사한다.
2. `./scripts/swift-local.sh test --scratch-path .build/integration-quality --skip testArrangementRenderExportAndPlayback`, Python MCP/kit 26개, release build `.build/integration-release`.
3. 정확한 QA bundle/project/socket에서 cold 재생→대기 상태→정지→같은 attempt 재생, 완료 뒤 재생/정지. 작은 창/콘솔 닫힘의 상태 표시와 keyboard/AX 재생 취소. OS가 즉시 준비되면 제어된 테스트와 실제 cold 관찰을 분리한다. timeout은 기존 live handle을 다시 관찰하며 프로세스 재시작 근거로 삼지 않는다.
4. 코드/보안 read-only review, 패키지 UUID/signature/kit, 원본 음악 보존을 확인하고 같은 private branch에 checkpoint commit/push한다. 전체 E/사용 앱 출고·장기 개발 목표는 active다.

## 결과

최종 build 25 UUID `923B584A-9708-38E6-898F-31E3CC5FE73D`. Swift 236개·Python 26개 및 native 증거 verifier 통과. 최초/중간 후보는 105초·162초, 최종 새 프로세스는 2초에 같은 단계로 연결됐다. 시간 차이를 코드의 지연 해결 효과로 해석하지 않는다. 최종 앱에서 MIDI 편집기 제거 후 canvasKeyboardFocus=true와 Space 정지, 콘솔 입력 유지, 음악·배치 불변을 확인했다. [상세 증거와 한계](../qa/output-connection-review.md). 전체 목표는 progress다.
