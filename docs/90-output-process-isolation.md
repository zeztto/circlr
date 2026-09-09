# 출력 프로세스 분리

planning-gate-v1: 2026-09-10, development-lead → planner → native utility. 기준 cca75f6. 현재 단일 슬롯이므로 독립 agent 검토를 주장하지 않는다. 목적은 장치가 응답하지 않아도 편집·STOP·재시도가 가능한 제작 앱이다. HAL 원인 해결과 프로세스 격리는 별개의 완료 조건이다.

## 현재 연결과 유지할 계약

`Sources/CirclrAudio/Playback.swift`는 렌더된 PreparedAudio를 보관하며 offset+transport.seconds를 공개한다. `PlaybackOutputConnection.swift`는 동일 연결 worker의 완료만 기다리고 시간 초과 후에도 그 worker는 유지된다. `PlaybackTransport.swift`의 queue가 AVAudioEngine을 소유하므로 HAL 내부 정지는 강제 취소할 수 없다. `Sources/CirclrApp/MovieRecording.swift`는 playback.playing/seconds로 영상 종료와 시계를 결정한다. 이 공개 재생 계약과 음악 문서·Undo는 유지한다.

`AuditionTransport.swift`는 note token/session과 instrument/asset 문맥이 추가로 필요하다. PCM 곡 출력 전환과 별개로 live note-on/off 및 AU 수명 계약을 검증한 후 연결한다. 현재 PCM 전송만으로 연주 가능한 신스 격리가 완료됐다고 보지 않는다.

## 구현 순서와 소유 경계

1. Native utility: `Sources/CirclrAudio/OutputWorkerProtocol.swift`, `Tests/CirclrAudioTests/OutputWorkerProtocolTests.swift`. bounded newline JSON, protocol version, session UUID, 방향별 sequence 검증. 끊긴 마지막 프레임·잘못된 JSON·과대 프레임·다른 세션·중복/역행 응답을 거절한다. 이 단계는 아직 사용자 출력 경로를 바꾸지 않는다.
2. Native utility: 새 `Tools/CirclrOutputWorker/main.swift`, Package.swift의 실행 target. stdin 명령/stdout 사건, stderr 진단. helper가 실행 시 부여된 private 임시 디렉터리의 고정 audio.caf만 읽는다. 네트워크·임의 shell·사용자 경로 요청 없음. PCM frame 수/포맷/유한값 검증, 출력 시작 확인 후 started, audio device clock 기반 clock, 실제 완료 후 finished. helper는 하나의 재생 session만 소유한다.
3. Native utility: `Sources/CirclrAudio/OutputWorkerProcess.swift`에서 Process/Pipe·단일 자식·임시파일 수명 관리. 유효한 실행 파일을 고정 경로에서 실행하고 stdout 크기 제한·stderr drain·EOF/exit를 처리한다. STOP은 먼저 요청 세대를 무효화하고 정지 요청; 정리 deadline 뒤 해당 자식만 terminate/kill. 프로세스 종료 확인 전에는 새 session을 시작하지 않는다. cleanup 완료 후에만 재시도 가능. 자동 재생 재시도는 하지 않는다.
4. Native utility와 packaging owner: Playback/PlaybackTransport/PlaybackOutputConnection 및 배포 스크립트에 연결. 기존 테스트 주입 backend는 유지한다. signature/내장 helper 누락/버전 불일치 실패는 상태로 노출하며 조용한 in-process fallback은 하지 않는다. UI 문자열은 ‘장치 정리 중’과 ‘다시 재생 가능’을 실제 lifecycle에 맞춰 갱신한다. 출력 정상화로 추정해 UI만 바꾸지 않는다.
5. QA/security read-only: 실제 helper 정상 start/clock/stop/자연 종료, 의도적 hang/late packet/종료 경쟁/호스트 종료, 큰 PCM·권한 오류·취소 시 임시파일 제거, 재시작 후 이전 응답 무시. native 앱에서 편집·Undo·저장·최소화·MP4 시계 및 소리 확인. 앱 서명과 helper 배치 검증. 사용 앱 교체는 그 이후다.

## wire v1

최대 JSON 프레임16KiB(줄바꿈 제외), 수신 chunk64KiB. protocol version1, session UUID, 방향별1부터 연속 증가하는 sequence, typed payload. prepare는 총 frames만 보내며 파일 위치는 고정한다. play/started/clock/stop/stopped/finished는 run UUID로 재생을 구분한다. seconds는 유한한0이상, PCM 최대 길이는 별도 worker와 호스트가 같은 한도를 공유한다. error는 최대1024byte UTF-8과 run UUID optional. 입력 chunk가 여러 프레임이거나 JSON 중간에서 나뉘어도 처리하며 잘못된 스트림을 성공으로 부분 적용하지 않는다.

현재 구현: 1단계의 internal wire 타입과7개 테스트 통과. [검토 기록](../qa/output-protocol-review.md). 실제 앱 출력 경로에는 아직 연결하지 않았다. 나머지는 구현·실행 증거가 있어야 완료로 올린다. UI 도움말 QA나 독립 무음 진단은 실제 helper 통합과 음악 출력 증거를 대체하지 않는다.

실행 파일 구현:2단계 helper를 추가하고 실제 준비/파일 오류/EOF15개 검사와 wire7개를 통과했다. 출력 무응답 상태에서 parent EOF로 약9ms 종료 및 다음 child hello를 확인했다. 정상 start/clock은 아직 관측되지 않았고 앱 호스트 연결도 남아 있다. [검토](../qa/output-worker-service-review.md).

build76: 호스트와 기본 Playback·패키징을 연결하고 실제 앱의 timeout→정리→새session 재시도·Space 취소를 검증했다. 기존 단계별 ‘미연결’ 문장은 해당 단계의 이력이다. 정상 출력/clock/영상과 MIDI audition 연결은 아직 미완료다. [통합 계약](91-output-recovery.md) · [QA](../qa/output-host-review.md).
