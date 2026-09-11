# 앱별 출력 장치 선택 계획

상태: build109 구현·Release·mock/fixture·UI-only mock native 검증 완료. 최종 Release40.31초, 테스트38개/16.992초, 출력9개·리듬6개 상태 checker 및 시각/source 검토를 통과했다. 실제 장치 변경/readback/hotplug/물리 재생은 미검증이다. 현재 증거는 [구현·검증 기록](125-output-device-implementation.md)에 정리한다. 아래는 설계 계약이며 시스템 기본 출력을 바꾸지 않고 arrangement playback worker의 장치를 지정한다. 현재 HAL timeout의 해결책으로 확정하지 않는다.

## 확인된 API와 선행 제약

설치된 macOS SDK의 `AudioToolbox.framework/Headers/AudioUnitProperties.h:2426`은 `kAudioOutputUnitProperty_CurrentDevice`를 Global scope의 읽기/쓰기 `AudioObjectID`로 정의한다. worker가 소유한 output AudioUnit에 `AudioUnitSetProperty`로 지정하고 `AudioUnitGetProperty`로 실제 값을 확인할 수 있다. 시스템의 `kAudioHardwarePropertyDefaultOutputDevice`에는 쓰지 않는다.

`AVFAudio.framework/Headers/AVAudioIONode.h:117`은 underlying `audioUnit`을 공개한다. 그러나 `AVAudioEngine.h:430`은 `outputNode`를 처음 접근할 때 생성한다고 명시하고, 같은 헤더의 main mixer 설명은 필요할 때 output node에 연결한다고 명시한다. 설계 당시 `OutputWorkerService.swift`는 engine/player 생성 후 `mainMixerNode`를 얻었다. build109는 output node 획득과 장치 선택을 mixer 획득 전에 구분한다. 실측 stack은 이 접근에서 `GetOutputNode → GetIOUnit → AudioDeviceCreateIOProcID → HAL SetPropertyData → mach_msg` 대기를 보였다.

따라서 `engine.outputNode.audioUnit`을 얻고 CurrentDevice를 지정하는 구현도 **선택 적용 전에 기본 output node 생성에서 멈출 수 있다**. 장치 선택 기능 구현과 이 stall을 우회하는 backend 개발은 별도 검증 과제다. raw·재서명 helper 모두 stall한 동시간 대조가 있어 서명을 원인으로 확정하지 않는다. 장치 또는 활성 client의 이름만으로 원인을 판단하지 않는다.

근거: `qa/generated/output-stall-build89/stall-summary.json`, `qa/generated/output-signature-build89/summary.json`, `qa/generated/output-device-build90/client-summary.json`. SDK 경로는 `xcrun --show-sdk-path` 결과 아래 `System/Library/Frameworks`를 기준으로 한다.

## 구현 단위와 계약

1. **출력 목록과 설정:** 새 `Sources/CirclrAudio/OutputDeviceCatalog.swift`와 앱의 `OutputPreferences.swift`를 둔다. 장치 열거·UID 해석·output stream·alive 확인은 UI thread 밖의 종료 가능한 별도 조회 프로세스에서 수행하고 조회 deadline을 5초로 둔다. timeout/취소 뒤에는 소유 child의 terminate·reap을 기다리며 SIGKILL 이후 플랫폼의 종료 회수에는 별도 deadline이 없으므로 총 완료 시간을 5초로 보장하지 않는다. 설정은 UserDefaults에 `시스템 기본값` 또는 명시적 UID로 저장하며 프로젝트 파일·Undo와 분리한다. 숫자 AudioDeviceID는 영구 저장하지 않는다. 외부 진단에는 UID 원문을 노출하지 않는다.
2. **시도별 선택 전달:** `Playback.swift`, `OutputWorkerProcess.swift`, `OutputWorkerProtocol.swift`를 연결한다. 각 재생 시 선택을 snapshot하고 UID를 현재 장치 ID로 해석한다. 명시적 장치 요청은 worker가 확인하기 전 준비 완료로 표시하지 않는다. 기존 default 요청은 호환하되 구형 helper가 명시적 선택을 지원하지 않으면 조용히 default로 재생하지 않고 지원 오류를 반환한다. wire 버전 또는 capability 협상과 입력 길이·형식 제한을 먼저 확정한다.
3. **worker 적용:** `OutputWorkerService.swift`에서 output node 획득과 device 선택을 별도 entered/completed trace로 남긴다. 정지된 새 engine의 output AudioUnit에 선택을 적용하고 actual CurrentDevice를 확인한 후 mixer 연결·schedule·start로 진행한다. 오류 OSStatus를 보존하되 사용자 메시지는 장치 없음, 조회 시간 초과, 적용 실패, 실제 장치 불일치로 구분한다. 기존 STOP·세션 격리·deadline·cleanup 정책을 유지한다. trace 단계 추가에 맞춰 순서 검증과 event 상한도 함께 갱신한다.
4. **설정 변경과 장치 소실:** 준비 또는 재생 중 설정 변경은 다음 재생부터 적용하며 현재 worker 요청을 바꾸지 않는다. 새 설정으로 재생하려면 기존 세션의 종료·정리를 기다린다. 명시적 장치가 분리되거나 사용할 수 없으면 시스템 기본값으로 자동 대체하지 않는다. 재생 중 device configuration 변경은 실제 출력 장치와 상태를 재확인하고 명시적 선택을 유지할 수 없으면 정지·오류로 끝낸다. 성공 이후 장치 변경 관측도 구현 범위에 포함한다.
5. **출력 UI:** 앱 설정과 기존 출력 상태 UI에서 선택 장치와 실제 확인된 장치를 구분한다. 장치 목록 조회 중·조회 실패·선택 장치 미연결·재생 준비 실패를 한국어로 표시한다. 장치 이름은 성공 상태를 대신하지 않는다. 최초 범위는 arrangement playback이며 audition·media preview·recording까지 적용된다고 표시하지 않는다.

## 검증과 완료 조건

- CoreAudio setter를 주입한 mock으로 default/명시 선택, UID 재해석, 장치 없음, setter 실패, readback 불일치, 세션 중 설정 변경, hotplug 정지 처리를 검증한다. 시스템 기본 장치 setter를 호출하지 않는 경계도 확인한다.
- wire의 구형 default 호환, 명시 선택 미지원 오류, 잘못된 선택 값, stale 응답, trace 순서·상한을 검증한다. 기존 timeout·취소·EOF·stdout drain·정리 후 재시도 테스트를 유지한다.
- UI는 키보드 선택, 목록 조회 실패, 누락된 저장 장치, 다음 재생 적용 안내, 선택값과 실제 장치 표시를 fixture로 확인한다.
- 별도로 승인된 native 검증에서 사용 가능한 두 출력 장치를 대조한다. 전후 시스템 기본 장치가 같고 worker의 readback이 명시 선택과 같은지 확인한다. started·clock·종료 증거와 실제 출력 확인을 구분해 기록한다. 장치가 없으면 native 항목을 미검증으로 남긴다.
- `outputNode` 획득에서 다시 timeout되면 해당 증거를 보존한다. 장치 선택이 적용됐거나 stall이 해결됐다고 선언하지 않는다.

## 별도 backend 대안

직접 선택한 deviceID로 IOProc를 만드는 출력 backend는 기본 output node 생성을 피하는 별도 설계 후보다. 단순 AUHAL 교체는 `AudioComponentInstanceNew` 단계에서 기본 장치 초기화를 통과할 가능성을 먼저 검증해야 한다. 직접 backend에는 실시간 callback의 allocation/lock 금지, bounded PCM buffer, underrun 정책, SRC와 장치 format 협상, playback clock, EOF/STOP, hotplug·configuration 변경이 필요하다. 이 범위를 현재 장치 선택 설정 작업에 묶지 않는다.
