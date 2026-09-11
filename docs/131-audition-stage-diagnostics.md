# 악기 미리 듣기 단계 진단

상태: build115 mocked lifecycle17개와 production diagnostics/presentation106개 검사, 공유 readout의 offscreen native15개 PNG 검증 완료. 앱 Release는78.21초·exit0으로 완료했다. 전체 앱/HAL·물리 재생 검증은 아니다.

## 오디오 진단 계약

session별 optional trace와 최대64개 ring으로 `sourceLoad`, `auInstantiation`, `engineCreation`, `mixerAcquisition`, `routing`, `engineStart`, note·cleanup을 구분한다. ProductionInstrument에 실제 단계 instrumentation을 연결했고 첫 interruption의 시점·단계를 고정한다. stale session 보고를 차단하며 기존 두 인자 factory는 내부 단계를 추정하지 않고 `backendPreparation`으로 표시한다. legacy factory와 기존 status decode 호환을 유지한다.

실패한 initializer의 Swift unwind/deinit 내부는 별도로 계측하지 않는다. 해당 구간을 세분화하거나 cleanup 원인을 확정했다고 주장하지 않는다. 단계 관측은 원인 확정이나 in-process 작업 중단의 증거가 아니다.

## 기존 상태 영역

과거 output 실패보다 현재 대기 중 audition을 우선 표시한다. 별도 패널 없이 기존108pt readout의12pt label과 footer에 단계·경과·취소를 표시한다. progress log는 단계 변화에 대응하며 초마다 같은 상태를 누적하지 않는다.

## 검증 증거

- `.build/build115-audition-tests2.log`: mocked lifecycle17 tests, 0 failures. session·trace·interruption 및 기존 동작을 검증한다.
- `.build/audition-presentation-qa/result-final.json`: 실제 diagnostics/presentation 소스를 직접 compile한106개 검사 통과, presentation fixture15개, `audioBackendConstructed=false`.
- production presentation JSON과 production `TransportStatusReadout`를 사용한 dark offscreen native fixture15개 PNG(`render-final`)를 생성했다. 15장 시각 검토도 통과했다. preparing8단계는 모두17초, stopping4원인은 모두123초이며 나머지는 idle/ready/failed다. preparing123초 렌더를 검증했다고 주장하지 않는다. 전체 앱·AppStore·transport·실제 HAL 실행을 대체하지 않는다.
- `.build/build115-release.log`: Release78.21초·exit0, UUID `3D03E2CB-5571-3713-AC7C-9B3884F21829`. source freeze hash는 QA와 동일하며 source review는 blocking finding0으로 통과했다. 기존 사용자 앱 PID86114를 유지했다. commit/push 결과는 이 문서에서 주장하지 않는다.

## 재현 명령

integration-worktree에서 실행한 명령이다. 출력 JSON과 렌더 디렉토리는 기존 증거를 덮어쓰지 않으므로 다시 실행할 때 새 출력 이름을 사용한다. 아래 명령은 이미 수행한 절차를 기록한 것이며 문서 갱신 중 재실행하지 않았다.

```sh
mkdir -p .build/audition-presentation-qa
swiftc Sources/CirclrAudio/AuditionDiagnostics.swift Sources/CirclrApp/AuditionPresentation.swift qa/test-audition-presentation.swift -o .build/audition-presentation-qa/check > .build/audition-presentation-qa/compile-final.log 2>&1
.build/audition-presentation-qa/check .build/audition-presentation-qa/fixtures-final.json > .build/audition-presentation-qa/result-final.json
swiftc Sources/CirclrApp/TransportStatusReadout.swift qa/audition-presentation-native-host.swift -o .build/audition-readout-native-host > .build/audition-presentation-qa/native-compile-final.log 2>&1
.build/audition-readout-native-host .build/audition-presentation-qa/fixtures-final.json .build/audition-presentation-qa/render-final > .build/audition-presentation-qa/render-final.log 2>&1
shasum -a 256 Sources/CirclrApp/AuditionPresentation.swift Sources/CirclrApp/TransportStatusReadout.swift Sources/CirclrAudio/AuditionDiagnostics.swift qa/test-audition-presentation.swift qa/audition-presentation-native-host.swift > .build/audition-presentation-qa/source-sha-final.txt
```

## 검증 한계

이번 범위는 대기 위치를 더 정확히 관측하는 진단이다. in-process factory 중단·프로세스 격리·실제 출력/HAL stall 해결 또는 사용자 앱 출고 완료로 표현하지 않는다. 물리 재생·readback·hotplug는 별도 검증이며 사용자 앱을 유지한다.
