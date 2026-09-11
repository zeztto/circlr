# 재생 worker · 0.20.0 build 32

2026-09-09, macOS 26.5.1 / Apple Silicon. 기준 `0b92af8`, `codex/daw-integration`. [계약](../docs/46-playback-worker.md). 새 재생 worker의 오프라인 수명과 실제 앱의 대기 중 편집·취소를 검증했다. 정상 출력 재생·청감·장치 지연 해결은 이번 증거에 포함되지 않는다.

## 구현과 검토

AVAudioEngine/player의 생성·attach·출력 획득·route·PCM buffer 생성·start/play·clock·stop·해제를 `circlr.playback-output` 직렬 queue에 모았다. UI는 NSLock으로 보호하는 작은 상태 값만 읽으며 lock 안에서 장치 호출을 하지 않는다. 재생별 UUID·취소 token과 완료 callback 검사는 이전 재생의 늦은 종료가 새 재생을 멈추지 않도록 한다. STOP은 요청을 즉시 취소하며 실제 장치 정리는 queue가 끝낸다. 정리가 끝나기 전 새 물리적 시작은 거절한다. 초기 연결은 기존 한 attempt를 재사용한다.

장치 시작은 player 음량 0에서 진행하고 blocking start/play가 반환한 뒤 취소 여부를 확인한다. 물리적 장치 호출의 강제 취소나 STOP의 sample 단위 무음 지연을 보장하는 변경은 아니다. 실패/자연 종료도 queue에서 정리한다. Clock은 16 ms 주기로 읽으며 상태 줄 publication에서는 clock 변화만으로 화면 전체를 다시 갱신하지 않는다. 실제 MP4와의 시계 회귀는 출력이 가능한 환경에서 다시 검사해야 한다.

Native에서 발견한 숫자 Return 뒤 Space 소실을 보완했다. `CommittedNumberField`의 명시적 Return/Esc는 주 창에서 `focusCanvas`로 복귀하며 Tab 종료 경로는 유지한다. 별도 창에는 포커스를 전송하지 않는다. 콘솔 문자열의 Space는 실행하지 않고 입력된다.

동일 실행자가 코드/보안 역할로 queue 소유·수명·오래된 callback·취소·실패·UI publication과 파일 변경을 검토했다. 독립 리뷰 agent 요청은 `agent thread limit reached`로 거절됐다. 새 네트워크·인증·마이크 입력·사용자 경로 쓰기 경로는 추가하지 않았다. 참고한 [Apple engine configuration 문서](https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/avaudioengineconfigurationchange)는 내부 callback에서 동기 engine 해제를 피해야 함을 설명한다. 이번 구현도 player callback에서 직접 engine을 해제하거나 정지하지 않는다.

## 자동 검사와 패키지

- Swift **293개, 실패 0, 23.892초**: `swift-tests.log`. 장치 의존 기존 `testArrangementRenderExportAndPlayback`만 제외했다.
- 새 `PlaybackTransportTests` **8개**: 실제 MainActor에서 지연된 start/stop/clock·취소·timeout·단일 backend·cleanup 전 재시도·실패·자연 종료·오래된 callback·lazy init과 worker deinit을 검사한다. 물리 장치 사용 없이 backend를 주입했다.
- Python MCP/kit **26개, 실패 0**: `python-tests.log`. 도구 쓰기 schema와 kit의 25개 파일은 그대로다. snapshot의 `output.transport`만 additive다.
- 첫 release **32.92초**, 숫자 포커스 보완 후 final release **23.67초**, warning 없이 성공. 전체 293개 검사는 포커스 보완 전이며 마지막 변경은 release/native에서 검증한 AppKit 포커스 경로다. 오디오 소스는 전체 검사 이후 동일하다.
- 최종 앱 `qa/generated/output-lifecycle/focus/써클러 통합 검증.app`, UUID **`BC4A9560-75E4-3091-9FA3-8473C5BDC735`**. 소스 binary와 파일 기반 Mach-O section **37개**, signature·kit 25 hashes·주요 source 5 hashes 일치. 첫 후보 UUID `2AC411FB-B345-3716-9DF3-C0CDA2D81AC5`도 보존한다.
- `python3 qa/check-output-lifecycle-evidence.py` 통과. 검사 범위를 offline lifecycle와 native cancellation/editing으로 기록하며 실제 청감 통과로 해석하지 않는다.

## 실제 장치 진단

`system_profiler`와 read-only CoreAudio 진단에서 기본 Scarlett 6i6 USB, 44.1 kHz, 512 frames, alive=1, running=0을 관찰했다. 기본 장치 조회는 약 45 ms, 뒤이은 format/frame/latency 조회는 각 1 ms 미만이었다. 시스템 출력·sample rate·다른 앱·HAL driver 설정을 바꾸지 않았다.

음악 없는 별도 engine 진단은 `mainMixerNode`의 `AudioDeviceCreateIOProcID` → `HALC_ProxyIOContext::_TellServerAboutStreamUsage` → IPC 응답을 기다렸다. 7분 이상 이어지는 같은 대기를 확인하고 진단 프로세스 PID 58900만 종료했다. `DeviceProbe.swift`, `device-probe.jsonl`, `EngineProbe.swift`, `engine-probe.jsonl`, `engine-probe-stack.txt`, `probe-termination.json`에 근거가 있다. 이 진단은 음소거 buffer만 준비했으며 engine start 단계에 도달하지 않았다.

첫 앱의 native stack은 HAL 대기가 `circlr.playback-output`에 있으며 main thread는 이벤트 루프에서 응답함을 보인다. 첫 앱의 동일 attempt는 174초에도 connecting/timedOut이었다. 최종 앱의 새 attempt는 **331초**에도 connecting/cancelled였고 transport는 idle/didStart=false였다. 이번 후보는 출력 시작까지 진입하지 못했으므로 실제 start·stop·시계와 자연 종료의 native 회귀는 미검증이다. 특정 드라이버·장치 또는 서드파티 plugin을 원인으로 확정하지 않는다.

## Native 편집과 키보드

별도 `fixtures/output-lifecycle.circlr`, project **`872A0FCD-8E1B-50AD-91D9-0E91051382CA`**, authored tone 2개·3 track, 원본 music r14. 작은 canvas **1024×673**, 콘솔 열림/닫힘. 마이크 수집은 시작하지 않았다.

| 경로 | 실제 결과 |
|---|---|
| 첫 연결 timeout과 편집 | 같은 attempt=1/device에서 10초 timeout. 출력 2 트랙 볼륨 .7→.65 Return r15, ⌘Z .7 r16. 장치 대기 중 편집·Undo·저장 응답 |
| 첫 후보 포커스 결함 | 숫자 확정 후 AX focus=window, Space 무동작. `space-retry-ax.txt`에 실패 증거 보존 |
| 수정 Return→Space | .65 Return r17에서 AX focus=canvas. Space로 재생 준비 시작, 연속 Space로 즉시 취소. 여러 재시도도 attempt `00856733-726F-4B2A-B33A-F40D798E0370` 하나 유지 |
| Esc와 Undo | .8 draft→Esc는 .65/r17 보존, focus=canvas. ⌘Z는 .7/r18로 복원 |
| 콘솔 Space | `qa `가 입력되고 재생 요청은 cancelled 유지. 문자열은 실행하지 않고 삭제 |
| 저장·재열기 | r18/dirty=false, open job completed. global/tracks/sections/arrangements/assets/patterns/portLayout은 초기와 동일. 원본 studio manifest와 양쪽 tone hash 보존 |
| 종료 | 두 후보 모두 저장 상태에서 ⌘Q로 정상 종료. 사용자 0.19 앱과 기존 QA 앱은 유지 |

AX·스크린샷·snapshot·stack·검사 로그는 `qa/generated/output-lifecycle/`의 로컬 전용 증거다. `final-canvas.png`는 콘솔을 접어도 출력 대기가 표시되는 화면이다. 처음 MCP play 검사에서 revision 인자를 받지 않는 도구에 helper 인자를 전달한 요청은 client schema에서 거절됐다. 올바른 read-only snapshot 확인 후 play를 호출했으며 잘못된 요청은 재생을 시작하지 않았다.

## 전달과 남은 범위

build 32 소스와 QA 앱은 검토 가능하다. 현재 실행 중인 사용자 0.19 앱은 교체하지 않는다. 다음은 출력이 가능한 환경에서 cold/warm 재생·Space 정지·재시작·기존 곡과 MP4 시계 회귀, 별도 허용된 실제 입력·테이크·취소·저장 회귀다. VoiceOver와 밀집 포트 경로는 기능별 대표 시나리오로 검증한다. 이 checkpoint를 전체 DAW 또는 전체 개발 목표 완료로 취급하지 않는다.
