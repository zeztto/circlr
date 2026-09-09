# 출력 helper 실행 파일 — 준비와 종료 검증

2026-09-10. 기준655c847. Package.swift에 내부 실행 파일 `circlr-output-worker`를 추가했다. 앱 Playback은 아직 이 실행 파일을 사용하지 않는다. 정상 재생/시계/청감과 앱 재시도 완료를 주장하지 않는다.

## 구현과 보안 검토

`OutputWorkerService.swift`가 version/session/sequence wire를 통해 명령을 받는다. 파일 위치는 실행 시 전달한 private 소유 디렉터리의 고정 `audio.caf`다. 해당 경로의 owner/mode/type과 파일 hard link 수를 확인하고 symbolic link를 거절한다. 같은 UID가 private 디렉터리 내용을 악의적으로 교체하는 상황까지 격리하는 sandbox는 아니다. 호스트가 독점 생성·관리하는 디렉터리 계약이 필수다. helper는 사용자 파일을 수정하거나 임의 경로/네트워크/shell 명령을 수신하지 않는다.

48kHz stereo linear PCM, 정확한 frame 수 및 finite sample을4096frame scratch로 검사한다. 압축 데이터를 허용하지 않고 준비 시 장치를 만들지 않는다. 재생은 열린 파일을 scheduleFile로 stream한다. engine/device 호출은 helper의 main RunLoop에서 실행하며 UI 프로세스에는 없다. parent EOF는 별도 stdin reader에서 exit해 main의 장치 대기를 기다리지 않는다. stdout disconnect는 SIGPIPE를 무시한 뒤 write error로 종료한다. 입력 queue는8chunk로 제한한다.

실제 테스트에서 Foundation read(upToCount:4096)가 짧은 파이프 명령을 기다리는 결함을 발견했다. `.build/output-worker-input-stack.txt`로 확인하고4096byte bounded POSIX read와 EINTR 재시도로 수정했다. 초기 formatID API 컴파일 오류도 streamDescription의 mFormatID로 수정했다. 검토는 같은 실행자의 native/code/security 역할 전환이며 독립 agent 검토가 아니다.

## 실행 증거

- `swift build --scratch-path .build/output-protocol-tests --product circlr-output-worker`: 수정 후 성공, `.build/output-worker-read-build.log`.
- `python3 qa/test-output-worker-process.py`: 실제15개 자식 프로세스 검사 실패0, `.build/output-worker-verified-process-tests.log`. 준비/STOP/EOF, 준비 전EOF, frame mismatch, 누락/공개 권한/symbolic link/hard link 파일, directory 권한, mono/다른sample rate, finite float와NaN, 중복prepare, 잘린wire/다른session. 이 검사들은 play를 전송하지 않는다.
- `swift test --scratch-path .build/output-protocol-tests --filter OutputWorkerProtocolTests`:7개 실패0, `.build/output-worker-wire-tests.log`.
- `python3 qa/verify-output-worker-native.py`: 명시적인1초 무음 PCM 출력 시도. hello/prepared 수신 후3초 동안 started 없음. 부모 command pipe를 닫은 뒤 **0.008568초에 exit0**. 이전 자식 종료 확인 후 새PID의 hello/EOF exit0를 확인했고 temporary directory도 제거됐다. 실제결과 `qa/generated/output-worker/native.json`: physicalStarted=false, clockObserved=false. 새 helper의 stack은 이번에 채집하지 않아 timeout 자체만 확정한다.

자식 종료/다음 자식 실행이 동작함을 확인했지만 앱 호스트의 재시도 UI와 같은 결과는 아니다. 이 단계에서는 사용자 앱·음악 문서·시스템 장치 설정을 바꾸지 않았다. 실제 장치 재생이 불안정하므로 기본 앱 출고 조건을 유지한다.

## 후속

호스트의 OutputWorkerProcess가 파이프 drain·고정 실행 파일·private PCM 생성·시간 제한·late session 무효화·종료 확인·임시파일 정리를 책임져야 한다. helper 종료 후 다음 자식의 준비까지 앱 상태와 연결한다. helper 배포/코드 서명·실제 start/clock/stop/완료·MP4 연동과 MIDI audition은 남아 있다.
