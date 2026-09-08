# 오디오 녹음 lifecycle · 0.20 실행 계약

시작 기준: 0.19 `040bb2b`. 목표는 장치 연결·종료가 느려도 캔버스와 STOP이 반응하고, 실제 입력 상태와 파일 보존 결과를 확인할 수 있는 녹음 흐름이다. 사용자의 오디오 장치·OS 권한·다른 실행 앱은 변경하지 않는다.

역할은 development-lead/planner → native C/Swift audio utility → Core take editing → native App/UI utility → read-only review/security → QA → lead release다. agent engine audit dispatch가 실제 한도 오류로 실패하여 delegation은 none이다. `p1zza-development-lead`, `p1zza-planner`, `p1zza-ui-ux-designer` 지침을 적용한다. 검증된 소스·문서·테스트는 `codex/recording-lifecycle`의 source checkpoint로 기존 승인된 private remote에 보관한다. 실제 입력 acceptance 후 main 통합·앱 교체·로컬 키트 갱신을 별도로 판단한다.

## 파일 책임과 상태 계약

- `Sources/CirclrAudio/AudioRecorder.swift`, `CaptureControl.swift`, 기존 `Playback.swift`: AVAudioEngine 생성·input 접근·tap·start·stop과 TakeWriter 마무리는 전용 serial worker만 수행한다. MainActor facade는 idle/starting/recording/cancelling/finishing/failed 상태와 결과를 전달한다. backend factory를 주입하여 실제 driver 지연·실패·늦은 완료를 재현한다.
- `Sources/CirclrRealtime/capture.c`, `include/CirclrCapture.h`, `ring.c`: callback에서 lock/파일 I/O 없이 atomic 수집 gate·frame count·peak를 기록한다. 중지는 gate를 먼저 닫고 진행 중 callback이 끝난 뒤 drain한다. section repeat의 최대 녹음 frame을 제한한다. 큰 입력 block은 ring block 크기로 나눠 기록한다.
- `Sources/CirclrCore/AudioTakeEditing.swift`: 원래 project/arrangement/use/track/lane 대상 검증, 실제 frame 길이의 take 생성·활성화·기존 take 보존을 한 atomic 편집으로 적용한다. 다른 문서 또는 삭제된 대상에는 삽입하지 않는다.
- `Sources/CirclrApp/RecordingWorkspace.swift`, `AppStore.swift`, `RootView.swift`, `InlineCircleEditor.swift`, `AudioWorkspace.swift`, `CirclrApp.swift`, `AgentWorkspace.swift`: 권한·장치 연결 동안 project/revision/선택 요청을 유지한다. STOP/선택/편집/문서 변경은 pending 시작을 취소한다. 시작 후의 저장은 캡처한 원래 대상에 적용한다. 늦게 도착한 다른 문서의 파일과 실패 원본은 Finder로 찾을 수 있게 한다. 종료 요청은 진행 중 파일 마무리를 기다리고 새 dirty 상태를 확인한다.

## 사용자 흐름

선택 트랙의 직접 녹음 버튼과 ⌥⌘R, 기존 명령 검색을 사용한다. 권한 확인·장치 연결·녹음 중·마무리·취소 후 장치 정리는 실제 상태로 표시한다. 녹음 시간은 받아들인 frame 수에서 계산하며 meter는 실제 callback의 peak다. mono 입력은 1채널, 다채널 장치는 기본 첫 두 채널을 기록한다고 명시한다. 입력 장치/채널 선택과 반주 transport 동기·latency 보정은 이후 범위다.

장치 start가 10초를 넘으면 수집을 차단하고 취소 상태로 바꾸되 기존 worker가 종료될 때까지 새 장치를 중복 열지 않는다. OS driver 호출을 강제로 중단했다고 주장하지 않는다. 캔버스는 계속 사용할 수 있다. Stop은 gate를 즉시 닫고 파일 마무리를 background에서 기다린다. 반환이 늦어도 다른 음악이나 문서에 take를 붙이지 않는다.

## 검증과 출고

1. 독립 `.build/recording-quality`: delayed start → cancel → late completion cleanup → retry, failure/timeout/duplicate start, slow stop/main actor responsiveness, frame/peak/limit·ring chunk·실제 CAF readback, atomic take destination/Undo 전제 및 반복 경계 테스트.
2. Swift 전체 offline 회귀와 Python MCP/kit, `.build/recording-release` release build.
3. 전용 0.20 QA 앱·사본에서 작은 창 직접 녹음 UI/키보드·취소·편집·저장 복원 검사. 실제 마이크 권한이 필요하면 사용자 macOS 선택을 기다리며 그 검사만 분리한다. fixture callback/장치 주입과 실제 마이크 녹음 증거를 구분한다.
4. version/kit/README/CHANGELOG/QA 기록과 source/QA/dist UUID·codesign·private remote 일치를 확인한다. 이전 앱·곡·입력 파일을 보존한다.

Apple의 [inputNode](https://developer.apple.com/documentation/avfaudio/avaudioengine/inputnode)와 [installTap](https://developer.apple.com/documentation/avfaudio/avaudionode/installtap(onbus:buffersize:format:block:))가 입력 tap 기반 수집의 API 근거다. 전용 worker·cancel gate·timeout은 circlr의 구현 계약이며 Apple이 driver의 강제 취소를 보장한다는 의미가 아니다.

## 진행 기록

소스·전용 0.20 앱과 오프라인 검사는 준비됐다. MCP에 revision이 필요한 `circlr_record`를 추가했고 `snapshot.recording`에 phase/busy/실제 시간·peak·format·보존 경로를 제공한다. 읽기 전용 전문 역할은 녹음을 시작할 수 없다.

추가 QA 책임 파일은 `Tests/CirclrAudioTests/RecordingRoundTripTests.swift`와 `qa/verify-recording-native.py`다. 전자는 실제 장치 없이 CAF→테이크→저장·재열기→바운스의 PCM 보존을 검사하고, 후자는 정확한 QA 사본과 실제 native timeline의 2초 제한을 확인한 뒤 명시적으로 허용된 녹음만 요청한다. 문서 재열기·직접 버튼·단축키 안내까지 확인했다. `StudioNavigationView.swift`의 선택 메뉴 대비를 고쳐 작은 창에서 다시 검증했다. 실제 입력과 녹음 중 UI 검증이 남아 출고를 보류한다. [검사 근거와 후속 시나리오](../qa/0.20-review.md).
