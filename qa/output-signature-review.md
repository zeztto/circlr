# build89 서명 보존 대조 검증

판정: 서명 보존 복사본의 strict 검증과 byte 보존은 통과했지만 출력 준비 개선은 확인되지 않았다. 같은 실험 회차의 raw control도 2회 timeout이므로 build88의 raw 성공·재서명 실패 차이만으로 서명을 원인으로 볼 수 없다. production code와 packaging 정책 변경은 없다.

근거는 `qa/generated/output-signature-build89/summary.json`, `signature-preflight.json`, `raw-control/{invocation,attempt-1,attempt-2,summary}.json`, `preserved-helper/{invocation,attempt-1,attempt-2,summary}.json`이다. 저장된 전체 event sequence와 결과를 읽고 현재 원본 및 복사본 hash를 재검증했다. 추가 native 실행은 하지 않았다.

서명 보존 실험 앱은 `qa/generated/output-signature-build89/써클러 서명 보존 검증.app`이다. preflight의 `codesign --verify --deep --strict`는 exitCode=0이며 helper는 adhoc/linker-signed, Identifier=circlr-output-worker다. helper와 raw 파일 SHA256은 모두 `b29f100c70b5678973f7783e14089a76c5e684fc1a2ee9db2be34c2877b9e8b5`로 일치한다. preflight에 등록된 원래 앱 executable·원래 bundled helper·raw helper도 현재 hash가 그대로다. strict 서명 검증은 저장된 실행 결과에 근거하며 이 감사에서 다시 서명하거나 패키징하지 않았다.

| case | PID | 첫 시도 소요 | 둘째 시도 소요 | 결과 |
|---|---|---:|---:|---|
| raw-control | 73691 / 73761 | 10.017초 | 10.014초 | timeout / timeout |
| preserved-helper | 73826 / 73863 | 10.012초 | 10.019초 | timeout / timeout |

네 시도 모두 1초 stereo 48kHz·16bit all-zero CAF hash `f6145ad46c457c3e0b3eb7781693ffb65f61e36c64d184a5f4ee6643745545bd`를 기록한다. event sequence 1–7은 hello, fileValidation entered/completed, prepared, engineCreation entered/completed, mixerAcquisition entered다. started·clockObserved·naturallyFinished는 모두 false다. EOF 요청 후 강제 kill 없이 exitCode=0이고 임시 디렉터리 제거를 기록했다. 이는 출력 시작 성공과 구별되는 정상 정리 근거다.

이번 대조는 “서명 보존만으로 이번 timeout이 해결된다”는 기대를 지지하지 않는다. raw control도 실패했으므로 환경의 시간 변화 등 다른 변수가 남는다. 서명의 일반적 영향이 없다고 단정할 근거도 없다. 관측이 가리키는 구간은 mixerAcquisition 진입 이후이며 그 내부 원인은 아직 미확정이다.

과거 `qa/generated/output-lifecycle/engine-probe-stack.txt`는 2026-09-09 02:32:34 +0900, engine-probe PID58900의 sample이다. main thread에 `AVAudioEngine mainMixerNode → AudioDeviceCreateIOProcID_mac_imp → HALC_ShellDevice::CreateIOProcID → HALC_ProxyIOContext::_TellServerAboutStreamUsage → mach_msg` 대기를 담고 있다. 이는 과거 별도 probe의 stack으로, 이번 build89 helper가 같은 곳에서 대기했다고 확정할 수 없다. 이번 sample 요청은 소유 probe들이 이미 종료된 뒤여서 새 stack이 수집되지 않았다고 summary가 기록한다.

서명 대조 직후 제안한 정밀 진단은 새 소유 helper의 PID/session을 즉시 기록하고 mixerAcquisition/entered가 도착했으나 completed가 아직 없는 동안, 10초 관측 deadline 안에서 해당 PID만 짧게 sample하는 방식으로 계획한다. timeout event와 stack의 시각·PID·binary hash를 함께 보존하고 기존 EOF/정리 deadline을 유지한다. 같은 회차 raw control도 같은 방법으로 수집해 호출 대기 위치를 비교한다. 이 계획의 후속 실행 결과는 아래 별도 live stall 회차에 기록한다. 장치 리셋이나 시스템 설정 변경 필요 여부는 서명 대조만으로 결정하지 않는다.

## 별도 live stall 회차: 현재 helper stack 수집 완료

서명 대조 회차에서 stack을 놓친 사실과 별개로, 후속 `qa/generated/output-stall-build89`에서는 실제 정체 중인 helper 두 개를 수집했다. `stall-summary.json`, `results/{invocation,attempt-1,attempt-2,summary}.json`, `sample-1.json`, `sample-2.json` 및 두 sample txt의 실제 call graph를 대조했다. 이 문서 감사에서는 새 실행을 하지 않았다.

대상 raw binary SHA256은 `b29f100c70b5678973f7783e14089a76c5e684fc1a2ee9db2be34c2877b9e8b5`다. PID75046/75061은 mixerAcquisition/entered 이후 약 0.5초를 기다려 각 1초 sample했고, sample exitCode=0으로 수집했다. 결과 두 시도는 각각 10.013초 timeout·started=false이며 command EOF 후 강제 kill 없이 exitCode=0으로 종료했다.

`sample-1.txt`와 `sample-2.txt`의 24–64행에서 main thread 표본 857/861개는 `Worker.handle`의 `AVAudioEngine mainMixerNode → GetOutputNode → GetIOUnit → AudioDeviceCreateIOProcID_mac_imp → HALC_ShellDevice::CreateIOProcID → HALC_ProxyIOContext::_TellServerAboutStreamUsage → HALC_ProxyObject::SetPropertyData → mach_msg → mach_msg2_trap` 경로에 있다. 따라서 이번 helper의 믹서 준비 구간에서 HAL RPC 응답을 기다린 stack 자체를 직접 확인했다. 앞서 읽은 역사적 engine-probe와 호출 사슬이 일치하지만, 같은 서버 측 원인이나 같은 물리 장치라고 결론내리지는 않는다.

최종 경계: 현재 정체 호출 위치는 확보했다. 서버 측 지연의 이유, 관련 장치 identity, 시스템 변경 필요 여부는 아직 미확정이며 서명 보존을 제품 수정으로 채택할 근거는 없다. production code·packaging 정책·장치 설정은 이 감사에서 변경하지 않았다.
