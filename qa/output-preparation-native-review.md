# build88 출력 준비 native 진단 실행 계약

상태: raw Release helper 직접 실행 2회 통과, app bundle helper 직접 실행 2회 timeout, host 앱 2회 timeout·1회 취소다. 출력 시작 문제는 미해결이며 host 전용 실패로 규정할 수 없다. QA는 저장된 JSON·AX·PNG·PCM과 helper binary hash를 대조했다.

```sh
python3 qa/verify-output-preparation-native.py --binary /absolute/path/to/final/release/circlr-output-worker --out /absolute/path/to/new/evidence-directory
```

`--binary` 및 새 `--out`은 필수다. 기존 증거 디렉터리는 거절한다. 첫 시도와 명시 재시도 두 진단 case를 각각 새 session/PID에서 실행한다. 이는 제품의 automatic retry 정책이 아니다. 두 case 모두 같은 SHA256의 실제 CAF container, 1초·stereo·48kHz·16bit all-zero PCM을 독립 임시 디렉터리에 만든다. PCM 바이트와 파일 hash를 기록한다.

각 시도 관측 deadline은 10초다. 정리는 소유한 child의 stdin EOF 요청 후 3초, 미종료 시 해당 child만 kill 후 최대 3초 reap이다. 시스템 설정이나 다른 프로세스를 변경하지 않는다. stderr는 저장하지 않는다. JSON frame 16KiB, buffer 64KiB, 512 events 상한과 wire version/session/sequence, trace 단계·시간 단조, run 일치 및 clock 시간을 검증한다. 실패 메시지와 임의 추가 child 필드는 보존하지 않는다.

wire v1 trace는 `fileValidation`, `engineCreation`, `mixerAcquisition`, `routing`, `scheduling`, `engineStart`, `playerPlay` 순서에 각 `entered/completed`다. flow_audio_audit와 직접 합의했다. trace가 사이에 들어오므로 다음 event를 곧바로 prepared로 가정하지 않는다.

`attempt-1.json`, `attempt-2.json`, `summary.json`, `invocation.json`은 exclusive 생성한다. timeout/error 및 사용자 interrupt의 partial도 기록하며 마지막 stage/event를 보존한다. `started`, `clockObserved`, `naturallyFinished`, 관측 중 stdout EOF, cleanup의 command EOF/강제종료/exitCode를 각각 분리한다. 자연 finished 없이 EOF만 받은 경우 통과하지 않는다. 두 시도 started·clock·finished가 모두 있어야 complete다. OS 강제 종료나 저장장치 오류까지 파일 보존을 보장하지는 않는다.

## build88 실제 관측 감사

증거: `qa/generated/output-preparation-build88/{invocation,attempt-1,attempt-2,summary}.json`. invocation의 최종 Release helper SHA256 `b29f100c70b5678973f7783e14089a76c5e684fc1a2ee9db2be34c2877b9e8b5`는 감사 시 파일 hash와 일치했다. 이 감사에서는 추가 native 실행을 하지 않았다.

| 관측 | 첫 시도 | 명시 재시도 |
|---|---:|---:|
| PID | 71060 | 71061 |
| started 관측 상대초 | 0.532605 | 0.121681 |
| finished 관측 상대초 | 1.618462 | 1.203244 |
| 전체 소요초 | 1.620113 | 1.205043 |
| mixerAcquisition entered→completed | 84.816 ms | 91.681 ms |
| cleanup EOF→exit 소요 | 1.329 ms | 1.339 ms |

각 시도는 서로 다른 session/run으로 event sequence 1–71이 연속이고, 7개 typed stage의 entered/completed 14개가 선언 순서대로 있다. 관측 상대시간·helper trace 상대시간·clock은 각각 유한하고 단조 증가한다. hello(sequence 1), prepared(4), started(17), clock 53개(18–70, 0→1초), 자연 finished(71)가 일치하는 run으로 관측됐다. 두 시도 모두 timeout 없이 끝났고 lastStage는 playerPlay/completed, lastEvent는 finished다.

자연 finished 관측 후 command EOF를 요청했으며 두 child 모두 강제 kill 없이 exitCode=0으로 종료했다. 관측 루프의 stdoutEOF=false와 자연 종료 event를 구별했다. 임시 디렉터리 제거도 true다. 두 입력은 SHA256 `f6145ad46c457c3e0b3eb7781693ffb65f61e36c64d184a5f4ee6643745545bd`, 192068-byte CAF, 48000 frame·2 channel·48kHz·16bit·192000-byte all-zero PCM으로 동일하다. 임시 입력은 삭제되어 이 감사의 zero 여부는 실행기 검증 기록에 근거한다.

판정: 이 환경에서 최종 Release helper를 직접 실행한 무음 출력 2회는 started·진행 clock·자연 finished·정리를 통과했다. 첫 실행과 두 번째 실행의 시간 차이는 표본 두 개의 관측값이며 성능 개선이나 제품 startup hang 해결의 인과 근거가 아니다. 앱 전체 통합 경로, 다른 장치·환경, 반복 재현 안정성, 가청 출력의 청취 품질은 이 증거가 검증하지 않는다. 명시 재시도는 진단 case이며 제품 automatic retry를 추가하지 않았다.

## build88 host 앱 경로 최종 관측

`qa/generated/output-preparation-build88/host`의 전체 JSON, `play.ax.txt`, `cancelled.ax.txt`, `play.png`를 읽고 실제 WAV를 다시 검사했다. `python3 qa/check-output-preparation-host.py` 통과. 이 checker는 저장된 증거만 읽으며 앱을 호출하지 않는다.

앱 export는 tail=0으로 2초, stereo 48kHz·24bit·96000 frames를 생성했다. WAV의 모든 PCM byte가 0임을 재검증했다. `pcm-verified.json`의 SHA256 `30fafbdc0facf210a26498db982f7ff8ad1e0b9a805816731c72e356a768c162`는 PCM payload hash이며 전체 WAV hash는 `71a1d35684d1d3d10b6245b8383d9d3da9bdeaf4b44354b69c5761b63c59209c`다. 준비 단계 fixture record의 offlinePCMVerified=false는 당시 상태이며 이 후속 실제 검증으로 보완한다.

첫 host 재생은 100 snapshots(0.046–10.774초)에서 didStart=false를 유지했다. timedOut은 10.131초 snapshot에서 처음 관측됐다. 최종 request=timedOut, phase=idle, attempts=1이고 9개 trace가 보존됐다. cafWrite/helperHello/fileValidation/engineCreation의 entered·completed 후 mixerAcquisition/entered까지만 확인됐다. 이는 정체 관측 구간이며 HAL의 근본 원인을 확정하지 않는다.

`play.png`에서 “믹서 준비 6초”와 “Space로 취소”가 실제 표시되며, AX에는 “믹서 준비 중 · 6초. Space로 취소할 수 있습니다.”와 재생 준비 취소 버튼이 있다.

첫 Space 조작은 timeout 후였으므로 취소 증거가 아니다. root 실행 기록상 CUA 대문자 Space key명이 실패한 뒤 lowercase 입력이 성공했고, 결과 `after-space.json`은 새 attempts=2·request=timedOut·didStart=false다. 세 번째는 root의 Space→AX→Space 조작 뒤 `cancelled.json`이 attempts=3·request=cancelled·phase=idle·didStart=false를 보인다. `cancelled.ax.txt`는 재생 버튼 복귀와 이전 출력 정리 완료, 마지막 믹서 준비 진입 정보를 제공한다. 최종 3개 attempt는 서로 다른 ID와 9개 trace를 보존하며 revision=0·dirty=false다. 키 입력 순서와 QA 앱 종료 완료는 root 실행 기록에 근거하고, 이 디렉터리에는 별도 종료 snapshot이 없다.

최종 판정은 독립 helper 2회 자연 완료와 host 2회 timeout·1회 명시 취소를 구별한다. host의 실제 started·clock·자연 완료는 검증되지 않았고 출력 시작 문제는 남아 있다. 준비 단계 표시·마지막 trace 보존·Space 취소 후 idle 복귀는 실제 UI/상태 증거로 확인됐다. 소스와 fixture는 이 감사에서 변경하지 않았다.

## app bundle helper 직접 실행 대조

추가 증거 `qa/generated/output-preparation-build88-bundled/{invocation,attempt-1,attempt-2,summary}.json` 전체를 검증했다. 대상은 `qa/generated/section-insertion/final/써클러 통합 검증.app/Contents/MacOS/circlr-output-worker`이며 SHA256 `f16b8fefdf8b2c38952360a36bf11ace417feed6035a3fbca01a0ef48df16959`가 감사 시 실제 파일과 일치한다. 앞 raw Release SHA256 `b29f100c70b5678973f7783e14089a76c5e684fc1a2ee9db2be34c2877b9e8b5`와 다르다.

동일 진단기와 동일 CAF hash로 bundle helper를 앱 없이 직접 실행한 두 case도 timeout이다. 독립 PID 72561/72613, 서로 다른 session에서 hello→fileValidation entered/completed→prepared→engineCreation entered/completed→mixerAcquisition entered의 sequence 1–7만 기록됐다. 10.007/10.004초 후 종료 정리됐으며 started·clock·자연 finished는 모두 false다. command EOF 후 강제 kill 없이 exitCode=0, 임시 디렉터리 제거 true를 확인했다.

따라서 결과는 raw build 직접 실행 성공 / bundled binary 직접 실행 실패 / host 실행 실패다. 실패가 host에만 있다는 해석은 배제한다. 관측된 정체 구간은 mixerAcquisition 진입 이후이며 코드·서명·실행 경로 차이의 인과 관계나 HAL 근본 원인은 아직 확정하지 않았다. 같은 기계 코드 여부에 관한 별도 read-only 감사 결과는 이 업데이트 시점에 대기 중이다. 추가 native 실행은 하지 않았다.

## build88 checkpoint 최종 matrix

`qa/generated/output-preparation-build88-matrix/matrix-summary.json`을 대조했다. bundle-outside 2회와 raw-resigned-outside 2회 모두 mixerAcquisition/entered에서 timeout, started=false다. 네 child 모두 command EOF 후 강제 kill 없이 exitCode=0이며 임시 디렉터리 제거를 기록했다. matrix는 originalsPreserved=true 및 copiesByteIdentical=true를 기록한다. 원본을 변경하지 않은 복사본 대조다.

앱 밖에서도 동일 실패가 나타나므로 앱 bundle 위치 하나로 실패를 설명할 수 없다. 재서명 raw 복사본도 packaged bytes와 동일하고 실패하여 서명 차이는 유력한 후속 조사 후보지만, 동시간대 원래 raw binary control이 없으므로 인과 관계는 확정하지 않는다. 이 checkpoint는 진단 증거와 취소·정리 검증으로 닫으며 startup 해결 판정은 하지 않는다. 본 최종 감사에서는 추가 실행을 하지 않았다.
