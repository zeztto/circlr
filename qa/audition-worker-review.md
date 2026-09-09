# build 43 · 미리 듣기 worker 검증

2026-09-09, `codex/daw-integration`, 기준 `1ca6cc3`. [실행 계약](../docs/57-audition-worker.md). UI 밖으로 미리 듣기 작업을 옮기고 취소·노트 수명을 검증했다. **HAL 지연 해결과 실제 정상 음원 재생은 미검증**이다.

## 구현과 검토

`AuditionTransport`가 신스·샘플러·Audio Unit 준비를 한 번만 수행하고, 성공한 backend의 노트·sample 렌더·정리를 직렬 worker에서 실행한다. MainActor에는 backend를 보관하지 않는다. 현재 누른 0–127 pitch만 보관하며 준비 중 놓은 노트를 나중에 재생하지 않는다. 노트 token은 같은 pitch의 재누르기와 이전 180 ms 자동 note-off를 구분한다. 준비 중 취소/다른 target은 기존 준비와 정리가 끝날 때까지 새 physical backend를 만들지 않는다.

10초 준비 timeout은 요청/held notes를 취소하며 취소할 수 없는 장치 호출의 소유는 유지한다. 샘플러는 렌더·buffer 생성 후 유효성 검사, 음소거 start 후 재검사를 수행한다. 실제 sample 단위 STOP 지연이나 third-party plugin의 내부 동작을 보장하는 변경은 아니다. 준비·정리·실패를 기존 transport 상태 줄에 표시하고 Space로 취소한다. MCP snapshot의 `audition`은 additive이며 기존 write schema와 kit는 유지한다.

코드 검토에서 factory 결과의 참조가 남은 동안 다음 factory가 실행될 수 있는 경계를 발견해 다음 drain을 queue에 예약한다. backend deinit을 인위적으로 막는 검사로 순서를 확인했다. Instrument는 snapshot을 직접 비교해 노트마다 Audio Unit state를 JSON/base64로 만드는 일을 제거했다. Native에서는 새 요청이 기존 physical 대기의 경과 시간을 초기화하는 문제를 찾아 보완하고 해당 회귀 검사를 추가했다.

동일 실행자가 UI/UX → native Swift utility → 읽기 전용 code/security review → QA로 역할 전환했다. 실제 단일 슬롯과 이전 `agent thread limit reached` 거절 때문에 독립 리뷰로 세지 않는다. 기존 원본 파일 읽기 경로, 입력 pitch/velocity 범위, 취소/교체 identity, 준비 결과/오류의 stale 처리, queue cleanup을 검토했다. 인증·네트워크·마이크 권한·사용자 파일 쓰기 경로는 추가하지 않았다.

## 자동 검사와 패키지

- 최종 Swift **345개, 실패 0, 24.777초**: `./scripts/swift-local.sh test --scratch-path .build/connection-workspace-quality --skip testArrangementRenderExportAndPlayback`. `.build/audition-tests-final.log`. 실제 장치 의존 기존 1개를 제외했다.
- 새 `AuditionTransportTests` **12개**: lazy init, 준비 전 release, 늦은 취소, 최신 target 대기, timeout, blocked note render, 재누르기와 오래된 release, warm reuse, blocked stop/deinit, prepare/note failure, 같은 track의 instrument 교체, 경과 시간, 잘못된 note를 검사한다. factory/노트/stop/deinit의 Main thread 실행 여부도 확인한다. 제어된 backend 검사이며 실제 소리 증거가 아니다.
- Python MCP/kit **26개**, `.build/audition-python.log`. QA helper 3개 문법 및 evidence checker 실행.
- 최종 release **7.23초**, `.build/audition-release-final.log`, warning 없이 성공. 최종 QA 앱 `qa/generated/audition-worker/elapsed/써클러 통합 검증.app`, bundle `com.circlr.integrationqa`, 0.20.0 build43. UUID **FBB45280-1B68-3B55-8089-3F3F4A4FACD8**.
- `check-audition-evidence.py`: source 8개·kit 25개 해시, 파일 기반 Mach-O 37개 section·strict signature, 원본 fixture/자산 보존, 6개 JPEG·snapshot과 stack의 서로 다른 thread를 검사했다. `elapsed/verification.json` passed, `physicalAuditionCompletion=not_verified`를 명시했다.

## Native 증거

전용 `fixtures/audition-worker.circlr`, ID `32B4C93C-E4F6-5561-BDCD-CEEB9951528B`. 기존 authored fixture를 복제하고 키보드만 자체 tone asset/oneShot=false sampler로 지정했다. 사용자 곡·Splice 파일·다른 앱/장치 설정은 건드리지 않았다.

| 검사 | 관찰 |
|---|---|
| 첫 노트 추가 | 피아노 롤 C5/3박 추가 r15. AX에서 즉시 ‘미리 듣기 취소’/0초 준비를 표시. 9초 snapshot은 attempts=1, heldNotes=0, preparing. `note-added.json/ax.txt` |
| 자동 timeout | 첫 후보는 10초 후 request를 취소했다. 이후 Space는 정지 상태를 유지했고 곡 재생 준비를 만들지 않았다. `cancelled.json/jpg` |
| 대기 중 편집 | 79초에도 MIDI 세기를 96→82로 변경 r16, 저장 성공. 다음 B4 note 추가 직후 Space r17, physical attempts=1/heldNotes=0 유지. `edited.json`, `edited-while-waiting.jpg`, `latest-cancelled.json` |
| 실제 stack | 소유 QA PID 82428의 1초 sample. Main thread는 NSApplication 이벤트 루프, 별도 cooperative worker는 `AuditionTransport.prepare` → `LiveSampler.init` → `mainMixerNode` → HAL IOProc/IPC 대기. `audition-stack.txt` |
| 최종 후보 수동 취소 | r20에서 C5 추가 r21, 준비 0초 AX 확인 직후 같은 CUA 호출에서 Space. timeout message 없이 stopping, heldNotes=0. `final-request-ax.txt`, `final-cancelled.json/jpg` |
| 최종 후보 새 요청 | 추가 note/Space r22에도 attempts=1. 실제 경과 시간이 12→37초로 이어졌다. `final-latest.json` |
| 콘솔 접기·복원 | 콘솔을 접어도 상단의 ‘미리 듣기 정리 중’과 Stop이 보임. 두 Undo r24, 저장/재열기 뒤 전체 음악·routing·원본 자산이 QA baseline과 일치. 마지막 snapshot에서도 backend 응답 대기 상태를 숨기지 않았다. `final-console-closed.jpg`, `final-restored/reopened.json` |
| 종료 | 첫/최종 후보를 ⌘Q로 정상 종료하고 정확한 QA process count=0을 확인한다. 사용자 앱은 0.19 build21 유지 |

첫 후보 3개 JPEG와 최종 후보 3개 JPEG를 구분한다. 첫 좌표 호출은 잘못된 도구 인자 형식으로 거절되어 UI를 변경하지 않았다. CUA 문서를 다시 읽고 `[x,y]` 좌표로 실행했다. 오류 시도를 성공으로 세지 않는다.

## 남은 검증

실제 연결 완료·warm note-on/off·청감·AU 플러그인/샘플러 voice steal·연속 MIDI·device hot-plug·출고 MP4는 출력이 정상 응답할 때 검증해야 한다. 이번 native 검사는 system HAL 대기가 계속되는 동안의 MainActor 응답성과 취소 요청이며, 제어된 backend에서만 늦은 완료·성공·오류·정리 완료를 관찰했다. 실제 마이크/MIDI input device start는 실행하지 않았다. song playback output attempts=0과 **audition physical attempts=1**을 구분한다.

생성 앱·프로젝트·tone·stack·snapshot은 로컬 QA 산출물이다. 승인된 private branch에 source/docs/tests/helper만 commit/push한다.
