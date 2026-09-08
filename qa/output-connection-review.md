# 출력 상태와 키보드 포커스 · 0.20.0 build 25

2026-09-08, macOS 26.5.1 / Apple Silicon. 기준 `91b419e`, branch `codex/daw-integration`. [실행 계약](../docs/39-output-connection.md). 단일 장치 연결의 실제 상태를 노출하고 대기 취소와 편집기 제거 후 키보드 복귀를 개선했다. 사용자 앱 0.19의 출고 대체나 HAL 지연 해결 판정은 아니다.

## 검사와 패키지

- `./scripts/swift-local.sh test --scratch-path .build/integration-quality --skip testArrangementRenderExportAndPlayback`: **236개, 실패 0, 20.871초**. 실제 장치 의존 기존 1개 검사를 제외했다. `qa/generated/output/focus-swift-tests.log`.
- 새 `PlaybackOutputConnectionTests` 5개는 제어된 async 장치로 늦은 완료/STOP/Task 취소/겹친 대기/연속 timeout/ready 재사용과 최초 상태 publication을 검사한다. 취소한 요청이 성공으로 돌아오거나 새 요청 상태를 덮지 않으며 연결 횟수는 1이다. precancelled/invalid 입력은 장치를 열지 않는다. 실제 마이크나 출력 장치를 쓰는 단위 검사가 아니다.
- Python MCP/kit **26개, 실패 0**, `python-tests.log`. 도구 schema/22개 catalog·kit 25개 파일은 유지하며 snapshot `output`과 진단 `canvasKeyboardFocus`만 추가했다.
- 최종 release **성공, 25.30초**, `focus-release.log`. 앱 `qa/generated/output/focus/써클러 통합 검증.app`, UUID **`923B584A-9708-38E6-898F-31E3CC5FE73D`**, bundle `com.circlr.integrationqa`. 이전 후보는 `output/`와 `output/final/` 경로에 별도 보존한다. 실제 source binary와 UUID/파일 기반 Mach-O sections, signature·kit hash를 대조한다.

## Native 증거

별도 `fixtures/output.circlr`, project `5A1693CD-D808-58A3-9D53-99E354FC8209`. 기존 통합 fixture의 authored tone 2개·3음 MIDI를 복사했다. music r14·port layout r4다. `prepare-output-qa.py`는 기존 대상 보존과 원본 asset checksum을 검사하며 `verify-output-native.py`는 정확한 bundle/version/project/path·입력 idle을 확인한다. 산출물은 `qa/generated/output/` 로컬 전용이다.

| 시나리오 | 관찰과 근거 |
|---|---|
| 실제 timeout과 공유 연결 | 첫 후보의 `cold-start`→`timed-out`→`retry-waiting`은 모두 attempt `59479D62-8B99-439B-AD73-4FAB13FE6231`, attempts=1, step=device. 10초 뒤 request=timedOut이며 modal 오류 없이 시계 아래 대기 시간이 보임. `cold-start.json/png`, `timed-out.json`, `retry-waiting.json` |
| Space 취소 후 늦은 완료 | 같은 attempt에서 request=cancelled, playing=false. 105초에 phase=ready가 돼도 cancelled/정지 유지. `space-cancelled.json`, `before-final-app.json`, `late-ready.png` |
| 최종 로그/대비 후보 | 두 번째 프로세스 attempt `99410CF7-4A76-47D5-B226-F326CD9BCC78`도 동일 연결 재사용. 상단의 준비 취소 버튼으로 정지한 후 콘솔을 접어도 `출력 대기`가 보임. 대기 중 MIDI 이름표를 더블클릭해 편집기에 진입. 162초 후 ready·cancelled 유지. `final-cancelled.json/png`, `final-pending-editor.png`, `final-late-ready.json` |
| 마지막 포커스 보완 후보 | attempt `9EF9FAF1-EEA9-4426-847A-168E83820823`, attempts=1. MCP STOP 뒤 2초에 ready·cancelled가 됐으며 자동 재생 없음. `focus-start.json`, `focus-cancelled.json`, `focus-ready.json` |
| 편집기→팔로우→Space | 실제 AX에서 스텝 편집기에 포커스가 있는 상태로 재생. 편집기 제거 뒤 playing=true, seconds=0.777875, canvasKeyboardFocus=true, animated=true·windowOccluded=false. Space 입력 직후 playing=false·seconds=0·canvasKeyboardFocus=true. `focus-before-play.json`, `focus-playing.json`, `focus-stopped.json` |
| 콘솔 입력 보호 | MIDI 편집기와 콘솔 입력이 함께 열린 상태에서 콘솔에 글을 입력한 뒤 재생. 편집기는 제거되지만 canvasKeyboardFocus=false, 콘솔 first responder 유지. Space 후 AX에 `ㅌ ` 값과 `재생 정지` 버튼이 동시에 존재해 공백 입력과 재생 유지 확인. 문자열은 실행하지 않음. `console-playing.json`, `console-space-ax.txt` |
| 음악/파일 보존 | 최종 정지 후 저장. `final-save.json`의 tracks/sections/arrangements/assets/portLayout/musicRevision이 `before.json`과 완전 일치. 입력은 모든 기록에서 idle |

작은 창의 실제 canvas는 **1024×673**이다. 콘솔 열림/닫힘 모두 시계 아래 상태와 기존 주요 버튼이 보인다. 최종 native verifier `python3 qa/check-output-evidence.py`가 단일 attempt·상태 순서·늦은 완료·실재생·포커스 복귀·Space/콘솔·음악 보존을 검사한다. 결과 `verification.json`은 통과다.

초기 확인에서 실제 재생 화면 뒤 Space를 입력했지만 정지되지 않았다. 재생이 자연 종료된 결과를 단축키 성공으로 인정하지 않았다. 원인은 팔로우가 first responder를 가진 편집기를 제거하면서 캔버스에 키 입력을 돌려주지 않는 경로였다. `removePrecisionEditor`는 제거 대상/내부 field editor만 캔버스로 옮긴다. 마지막 UUID의 즉시 정지 snapshot으로 수정 결과를 다시 확인했다.

일부 중간 AX click은 1초 상태 publication 후 요소 ID가 만료돼 도구에서 거절됐다. 현재 AX를 다시 읽고 관측한 버튼 좌표로 조작했다. 중간 `final-playing.json`은 실제 playing=true지만 창이 가려져 animated=false였으므로 최종 전면 모션 근거로 사용하지 않는다. `final-pending-editor.json` 저장 시점에는 이미 ready였으며 대기 중 편집 근거는 그 직전 158초를 표시한 PNG다.

## 검토·보존·남은 작업

같은 실행자의 read-only 검토에서 새 변경을 막는 결함은 발견하지 않았다. MainActor request generation, 작업을 취소하지 않는 physical worker, timeout의 monotonic 시각, 초기 상태 publication, render/movie generation guard와 문서 입력 포커스 경계를 대조했다. 독립 에이전트는 한도 때문에 실행되지 않았으며 독립 리뷰로 계산하지 않는다. 통제된 gate 검사·실제 장치·UI 포커스 증거를 서로 대체하지 않는다.

HAL 연결은 105/162/2초로 달랐다. 이 측정만으로 코드가 지연을 해결했다고 추론하지 않는다. 기존 `AVAudioEngine.start/stop`의 MainActor 경로, 장치 교체·연속 재생·driver 오류, 실제 microphone/VoiceOver/MP4 종료 복구, 큰 프로젝트 성능은 후속이다. 영상 준비 중 버튼 취소의 분기는 source/release 검증 범위이며 이번 native QA에서 새 MP4는 녹화하지 않았다.

원본 `studio.circlr` manifest SHA-256 `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`, 사용자 앱 **0.19.0 build 21**와 UUID `96FDDF3A-D327-3708-80BF-CCF68B31B6F1`은 보존한다. 승인된 private source/doc/test 범위만 commit/push하며 generated 앱·tone·프로젝트·인증정보는 포함하지 않는다. 다음은 [로드맵](../docs/25-development-roadmap.md)의 밀집/궤도 UI와 공통 import·라이브러리다.
