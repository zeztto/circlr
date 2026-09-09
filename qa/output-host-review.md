# 앱 출력 복구 통합 — 0.20.0 build76

2026-09-10. 기준5ba4225, codex/daw-integration. [사용 흐름/수명 계약](../docs/91-output-recovery.md). 동일 실행자의 native/code/security/QA 순차 역할이다. 독립 agent 슬롯은 없었으며 독립 검토로 계산하지 않는다.

## 변경과 검토

OutputWorkerProcess는 PCM 파일 쓰기/Process/pipes를 직렬 queue에서 소유한다. 0700 임시 폴더/0600 CAF, chunk 쓰기와 finite sample 검사를 사용한다. stderr를 지속 drain하고 stdout parser 뒤 stage/runID와 취소 상태를 다시 검사한다. stdin write는 F_SETNOSIGPIPE로 disconnect 때 앱 종료를 막는다. 새 자식은 이전 termination 관측 이후에만 가능하다. 쓰기 오류/실행 실패/손상 응답도 임시파일을 정리한다. 파일 정리가 실패하면 경로와 오류 상태를 남긴다.

review에서 호스트의 늦은 started 무시만으로는 helper의 늦은 unmute를 막지 못함을 발견했다. helper stdin reader가 STOP을 즉시 token에 반영하고 장치 호출 뒤/unmute 앞뒤에서 확인하도록 보완했다. cancellation 체크와 물리 음량 변경 사이의 sample 단위 원자성은 보장하지 않는다. EOF/TERM/KILL은 해당 자식에 한정한다. PCM은 value-semantic Float 배열이므로 Sendable을 명시했다.

기본 Playback을 worker로 연결하고 기존 test backend 주입은 유지했다. MovieRecording의 공개 playing/seconds 계약은 그대로며 실제 영상 회귀는 아직 별도다. RootView 상태 글자를10pt/축소 가능82pt에서12pt/108pt로 넓혔다. build-app과 production/QA packager 모두 helper를 함께 복사·서명한다.

## 자동 검증

- 최종 Swift **513개 실패0**,31.678초: `.build/output-host-final-all-tests.log`. 장치 의존 `testArrangementRenderExportAndPlayback` 제외. 실제 출력 시작은 아래 native에서도 미달이다.
- host8개는 실제 통제된 자식으로 clock/offset/STOP·cleanup 중 재시도 거절·정리 후새session·늦은 시작·호출Task 취소·손상/EOF/실행실패/NaN·자연완료를 검사한다. ignore fixture가 play까지 진입했음을 marker로 확인한 뒤 TERM을 무시하게 해KILL 정리 경로를 검증한다. 동작 모사는 실제 장치 정상 재생 근거가 아니다.
- helper **16개 실패0**, `.build/output-host-helper-tests.log`. 기존15개와 coalesced prepare/play/STOP의 장치 생성 전 취소. wire7개는513에 포함한다.
- MCP20개 + kit9개 통과. 이외 전체 Python 영역을 검사했다고 주장하지 않는다.
- 최종 release **46.38초**, warning/error 없이 성공. 첫 release69.74초, 첫 native 후보에서 UI 확인 뒤 글자/취소 보완 및 최종 전체검사를 다시 수행했다.
- production packaging을 임시 프로젝트에서 실제2회 실행: 앱/helper Mach-O 일치·deep signature·이전 bundle archive·helper 누락시 기존앱 보존 통과. `qa/test-output-worker-packaging.py`, `.build/output-host-packaging-tests.log`. 사용자 dist를 대상으로 실행하지 않았다.

## native 결과

별도 output-host.circlr project `B39C2A06-779B-5C82-BFC8-A1CB76844977`. 원본r14·authored tone2개·3track. 첫 후보 UUID `669DFEE4-E252-3768-9A80-3571EFB8CBCF`, 최종 `FF8E5282-BDB5-3886-9AF8-F5CA68F8A947`.

첫 후보의 두 timeout 요청은 서로 다른 session으로 종료됐고 다시 재생 가능을 표시했다. Space 키 이름을 `Space`로 보낸 첫 CUA 호출은 거절됐으며 뒤 `space`는 이미 timeout 후여서 새 요청을 시작했다. 따라서 `third-cancelled.json`은 성공 취소 근거가 아니다. 이후 준비 상태를 확인한 실제 Space 입력의 attempt5는 같은ID/cancelled로 종료됐다. attempt6의 device 대기 중 출력2 gain .7→.65 r15, Undo r16·저장을 확인했다.

최종 앱에서 attempt1 `31B437C1-1D59-4887-932E-A3D8312E1028`은 device/starting 이후10초 시간 초과하고 자식 종료 후idle/timedOut이 됐다. 새 attempt2 `D738823B-33F2-4AEA-ABA6-76903AC966C1`을 준비 상태에서 Space로 취소해idle/cancelled를 확인했다. 최종 두 화면은 약1020×768에서 준비6초/다시 재생 가능과 상단 조작이 잘리지 않고 보인다.

모든 native 관측에서 physical didStart=false, playback=false다. 준비 대기와 취소 복구를 검증한 것이며 소리·정상clock·자연종료·영상/마이크 성공을 뜻하지 않는다. 입력과 audition을 시작하지 않았다.

## 보존과 출고 범위

`python3 qa/check-output-host-evidence.py` 통과. 음악 문서10상태의 전체 비교(보기/revision만 제외, 의도한gain 편집만 별도 expected), 최종r16 원본음악 복원. 원본studio manifest SHA `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`, authored asset2개 보존. 앱37/helper36 Mach-O sections, source hashes11개와 packaging source3개, kit25개 hash, deep signature 대조. 확인한 모든 attempt의 temp directory와 QA 앱/child 종료 확인.

사용 앱0.19.0 build21은 교체하지 않는다. 정상 출력/입력·MIDI audition·장치 전환·MP4 시계는 출고 조건으로 남는다. 이번 통합은 멈춘 장치 호출에서 앱 재시도를 회복하는 범위이며 HAL 원인을 해결했다고 주장하지 않는다. 생성 앱·PCM·화면·JSON·임시 프로젝트는 commit하지 않는다.
