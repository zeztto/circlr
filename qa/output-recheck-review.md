# 출력 장치 재점검 — build75

2026-09-10. 기준 7062807. 사용자 앱·시스템 출력 설정·sample rate·HAL/daemon·다른 앱은 변경하지 않았다. 독립 진단은 20초 deadline이며 초과한 진단 프로세스만 종료했다. 이 기록은 출력 결함 해결이나 청감 통과가 아니다.

## 현재 관측

| 조건 | 실제 결과 |
|---|---|
| 읽기 전용 장치 속성 | 기본 출력 ID96, 44.1kHz, 512frames, alive1/running1. 첫 defaultOutput 조회 약61ms, 마지막 약51ms. 속성 응답 정상만으로 IOProc 준비를 보장하지 않는다. |
| 독립 메인 스레드 무음 엔진 | 첫 실행 0.711초 종료0. mixer 약98ms, start 약8ms, sampleTime8370, stop 완료. |
| 최종 build75 앱 | 정확한 QA project를 MCP open 완료 후 재생 요청. attempt 1, device 단계13초/timedOut, transport idle/didStart=false. STOP 후 저장·snapshot 응답. |
| 직렬 큐·dispatchMain 진단 | 20초 초과. mixer.begin 다음 진행 없음. HAL IPC 스택 수집 후 종료. |
| 직렬 큐·메인 RunLoop 진단 | 20초 초과. 같은 HAL IPC 스택. 종료 완료. |
| 첫 메인 스레드 진단 재실행 | 같은 binary도 20초 초과. 따라서 첫 성공과 큐 실패만으로 스레드가 원인이라고 결론내릴 수 없다. |

앱·두 큐 진단의 stack은 `AVAudioEngine mainMixerNode` → `AudioDeviceCreateIOProcID_mac_imp` → `HALC_ProxyIOContext::_TellServerAboutStreamUsage` 대기를 보였다. 특정 드라이버·메인 스레드·장치 상태를 원인으로 확정하지 않는다. 최초 successful probe는 무음이며 음악 청감을 검증하지 않는다. 이번 native 앱은 실제 출력 시작에 도달하지 않았다.

## 재현 근거와 보존

로컬 전용 `qa/generated/output-recheck/`: `device.jsonl`, `device-after.jsonl`, `engine.jsonl`, `engine-result.json`, `native-before.json`, `native-playing.json`, `native-stopped.json`, `native-final.json`, `native-stack.txt`, `queue-final*`, `runloop*`, `main-repeat*`. `native-playing`이라는 파일명은 관측 시점을 뜻하며 내용은 playing=false다. 기존 `qa/generated/output-lifecycle/DeviceProbe.swift`, `EngineProbe.swift`를 직접 컴파일했다. QueueEngineProbe는 엔진 본문을 serial DispatchQueue로 옮기고 dispatchMain을 사용하며 RunLoopEngineProbe는 마지막 줄만 RunLoop.main.run으로 바꿨다. 큐 closure의 throwing start를 do/catch로 감싸는 컴파일 수정 후 실행했다. 기존 DeviceProbe의 generic pointer 경고는 보존했고 숫자 property만 조회했다.

MCP open과 play의 첫 호출은 schema 오류로 거절됐다. 올바른 jobID 및 무인자 play로 수정한 뒤 실제 요청했다. 앱을 파일 인자로 시작했을 때 빈 문서였으므로 해당 상태에서 재생하지 않고 정확한 fixture의 open job completed·projectID/path를 확인했다.

검증 앱은 shortcut-search/ranked의 UUID `11D16FC9-632A-3475-8F6F-F66BBCF90A4D`다. r18 음악 문서의 모든 필드(보기와 revision을 제외한 전체 비교)가 전후 일치하며 revision도18로 유지했다. 원본 studio manifest SHA `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d` 일치. STOP·저장 뒤 정확히 해당 검증 앱 PID에 SIGTERM을 보냈다. 물리 입력은 시작하지 않았다. 기존 build75 도움말 QA의 attempts0 증거는 그 이전 세션이며 이번 재생 시도와 구분한다.

## 개발 결정

출력 획득을 UI 스레드로 옮기는 수정은 하지 않는다. 같은 메인 스레드 진단도 실패했고 UI freeze 위험을 해결하지 못한다. 현재 worker의 요청 취소·편집 응답을 유지한다. 정상 start/stop/자연 종료·장치 변경·입력·MP4 시계는 미검증 출고 조건이다. 다음 오디오 구현은 별도 프로세스로 장치 작업 수명을 격리할 필요성과 PCM/clock/STOP 계약부터 검토한다. 장치 재설정은 자동 진단의 일부로 수행하지 않는다. 독립적으로 가능한 한 곡 전체 제작 동선의 사용성 점검은 계속 진행한다.
