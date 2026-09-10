# 앱별 출력 장치 구현과 검증 계약

상태: build109 구현·Release·mock/fixture·UI-only mock native 검증 완료. 최종 Release40.31초, 테스트38개/16.992초, checker 출력9개/리듬6개 상태와 시각/source 검토를 통과했다. 실제 장치 선택/readback·hotplug·물리 출력 성공은 미검증이다.

목표는 시스템 기본 출력을 변경하지 않고 곡 재생에 사용할 장치를 선택하는 것이다. 기존 [설계](107-app-output-device-plan.md)의 조회, 요청별 선택, 실제 장치 확인, 장치 소실 감시, 설정 UI를 모두 구현 범위로 유지한다. 알려진 HAL 초기화 정지를 해결했다고 가정하지 않는다.

## 경계와 데이터 흐름

- 별도 `circlr-output-device-catalog` 프로세스가 alive 출력 장치와 시스템 기본 UID를 읽는다. 앱은 CoreAudio 열거를 직접 호출하지 않는다. 조회 deadline은 최대 5초이며 취소·timeout 뒤에는 해당 child만 종료하고 회수한다. SIGTERM 유예 뒤 SIGKILL하고 `waitUntilExit()`로 기다리는 구간에는 별도 deadline이 없다. 따라서 총 완료 시간은 플랫폼 종료 동작에 의존하며 5초 이내 완료를 보장하지 않는다. 결과는 65,536 bytes·최대256개 장치로 제한한다.
- 사용자 설정은 `systemDefault` 또는 명시적인 UID이며 UserDefaults에 보관한다. 프로젝트, Undo, PCM 캐시와 분리한다. 오디오 렌더 시작 전에 선택을 고정하고 영화 녹화의 재생 경로에도 같은 계약을 적용한다.
- 기존 wire v1의 기본 장치 요청은 유지한다. 확장 capability를 알리지 않는 helper에는 명시적 선택을 보내지 않고 오류로 끝낸다. 확장 helper는 실제 장치 확인을 보고해야 재생 시작을 인정한다.
- worker가 output node를 획득한 뒤 UID를 해석하고 CurrentDevice를 적용·확인한다. 시스템 기본 장치 속성에는 쓰지 않는다. 출력 node 획득과 장치 선택 trace를 분리한다.
- 장치 또는 엔진 구성이 바뀌면 선택을 재검증한다. 명시한 장치를 유지할 수 없을 때 기본 출력으로 대체하지 않는다. listener는 세션 종료 시 해제하며 늦은 callback은 무시한다.
- 설정 UI는 곡 재생에 적용되는 범위, 다음 재생부터 적용되는 변경, 저장된 선택과 마지막 재생에서 실제 확인된 장치를 구분한다. 확인 응답이 없으면 실제 장치는 아직 확인되지 않았다고 표시한다. 미연결 저장 UID를 자동으로 지우지 않는다. 진단 상태에는 원문 UID를 노출하지 않는다.

## 현재 검증 증거와 남은 범위

- `.build/build109-output-tests-final.log`: mock·fixture 38 tests, 0 failures, 16.992초. 장치 adapter·wire·host lifecycle·catalog subprocess 계약의 자동 검증이다.
- `.build/build109-release-final4.log`: 최종 Release40.31초. 최종 앱 UUID는 `3FED7CA1-03C1-3701-9E28-4BF59247A1CA`다.
- 출력 UI-only mock 후보는 `qa/generated/output-preferences/{success3,missing3,failure4,delay4}`다. success3의 5개 상태와 missing3 1개·failure4 1개·delay4 2개, 총9개 상태를 checker로 대조했다. 음악r14를 보존했다.
- 실제 UI에서 ⌘, 진입·초기 focus·Space/↑↓/Return으로 A→B 선택·Tab·Esc·명령 진입·설정 복원을 확인했다. 저장된 장치 누락 시 선택 유지, 실패 재시도, 4초 미만 기준을 만족한 조회 취소739ms도 확인했다. 초기 Esc 실패는 native controls로, Picker 변경 후 표시 누락은 ObservedObject로 수정한 뒤 재검증했다.
- 공유 리듬은 `qa/generated/rhythm-scope/final` 6개 상태에서 r16→17→18, 동일 패턴 B에 대한 공유 변경·Undo, 일반 MIDI 배너 없음, strict 재열기를 확인했다. 출력9/리듬6 checker와 출력9장/리듬3장 시각 검토가 통과했다.
- 최종 source review는 blocker0이다. 명시 선택 미지원 거절, 실제 descriptor 선행 guard, legacy trace, cancel/stale session, listener 수명과 failure-before-cleanup, 시스템 기본 setter 미호출을 확인했다.
- 패키징은 `circlr-output-worker`, `circlr-au-effect-worker`, `circlr-au-instrument-worker`, `circlr-output-device-catalog` 네 helper를 필수로 요구하고 각각 복사·서명·검증한다. catalog 누락 시 staging 이전 실패와 각 QA packager의 strict 서명 검증 통과를 확인했다. UI-only mock 후보의 catalog는 테스트 응답을 사용하므로 실제 장치 열거 성공 증거로 계산하지 않는다.
- 실제 두 장치 readback·재생 중 hotplug·실제 started/clock·물리 재생은 수행하지 않았다. 사용자 실행 앱 PID86114만 유지하며 QA 앱/helper 잔류 없음이 관측됐다. 알려진 HAL 초기화 정지 해결을 주장하지 않는다.

## 후속 검증 계약

장치 접근 adapter mock, 잘못된 wire·구형 helper·누락된 실제 장치 응답, timeout·취소·프로세스 종료, 패키지 필수 helper와 서명을 검증한다. UI는 키보드 진입·선택, 조회 실패·재시도, 저장한 장치 누락, 설정 변경 시 프로젝트 불변을 확인한다. 테스트용 fixture와 실제 장치 증거를 구분한다.

실제 두 장치의 readback, started·clock·종료, 전후 시스템 기본 장치 불변 확인은 별도 native 검증 조건이다. mock이나 UI 통과로 이를 대체하지 않는다. 사용자 실행 앱은 그대로 유지한다.

## 병행 UI 개선

공유 리듬 패턴의 노트를 수정하는 경우 서클 속성의 ‘이번 사용’ 선택과 별개로 공유 패턴이 변경된다. 기존 작업줄에 실제 패턴 이름과 공유 영향을 표시하고, 일반 MIDI와 구분한다. 음악 데이터 정책을 바꾸지 않고 두 사용의 공유 변경과 Undo를 위 final 후보에서 검증했다.
