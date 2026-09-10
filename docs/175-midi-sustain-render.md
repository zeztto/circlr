# 내장 신스의 서스테인 연주

기준: `5ce63cc`의 저장·컴파일 연결 이후 [서스테인 계획173](173-midi-sustain-plan.md)의 DSP 단계. 내장 신스 engine1/2/3의 오프라인 렌더에 CC64를 연결했다. SMF parser와 페달 편집 GUI/MCP는 아직 후속 단계이며, 설치 앱과 build149 패키지는 교체하지 않았다.

## 연주 동작

원본 Note의 길이를 바꾸지 않는다. C voice가 key-held와 deferred release를 구분하고, Swift renderer가 source/occurrence별 페달 상태를 관리한다. 페달을 누른 동안의 note-off는 건반만 해제하며 envelope release는 보류한다. pedal-up은 같은 stream의 보류 음만 release한다. 아직 누르고 있는 키·다른 source·다른 반복의 음은 유지하며 이미 release 중인 음을 다시 붙잡지 않는다.

`circlr_synth_owned_note_off_pedal`과 `circlr_synth_owned_sustain_release`는 기존64-voice pool 안에서만 동작한다. 잘못된 identity와 down 값은 변경 전에 거절한다. 이미 사라졌거나 stealing된 voice에 대한 늦은 off는 새 voice를 건드리지 않는다. 기존 `circlr_synth_owned_note_off`는 pedalDown0 경로를 사용한다. queued live 입력·음색 수식·filter·phase와 버전별 envelope 수식은 바꾸지 않았다.

Swift는 동일 frame의 note-off → controller → note-on 순서를 유지한다. 같은 시점의 pedal-up/down을 최종 상태 하나로 합치지 않는다. controller 종료 경계에 synthetic pedal-up을 추가해 반복 간 유지음 누출을 막되, 그 경계를 넘어 실제로 key-held인 긴 노트는 자르지 않는다. 원본 SMF 메시지 전체 순서 보존과는 별개인 기존 circlr sample 순서 계약이다.

initial/end 페달 이벤트까지 renderer의 합산 이벤트 예산에 포함한다. note source·시작/종료 범위·raw 값·시간순을 먼저 검증하고, 생성·렌더 중 취소를 확인한다. center bend와 all-off sustain은 기존 PCM 경로를 그대로 사용한다. AU·sampler·SoundBank의 활성 페달은 helper/asset 준비 전에 거절한다. 피치 벤드의 기존 backend 제한과 engine1의 resonance 제한도 유지한다.

## 독립 검사

실행 명령:

```sh
swift test --scratch-path .build/integration-tests --filter 'CirclrCoreTests|MIDISustain|SynthSustainAPITests|MIDIPitchBendGuardTests|MIDIPitchBendRenderTests|MIDIPitchBendExportRoundTripTests|MIDITempoRenderTests|SynthResonanceAutomationTests|SynthCutoffAutomationTests|SynthCoreTests'
```

최종 회귀는 build9.17초 후 **635개·실패0개**, 검사26.191초에 종료했다(`.build/sustain-dsp-regression-final.log`). 전체 Core와 선별 Audio이며 전체 Audio suite가 아니다. 최초 실행은 새 bounce 테스트의 `XCTUnwrap` autoclosure 안에 async 호출을 넣은 컴파일 오류로 중단됐고, 결과를 먼저 await하는 형태로 수정한 뒤 위 회귀를 완료했다.

- 신규 `MIDISustainRenderTests`9개: 독립적으로 길게 작성한 노트와 동일 owned 렌더 경로의 PCM을 비교했다. engine1/2/3, key-held 보호, 같은 pitch 재타건, source 격리, up→down 순서, release 재포착 금지, stream 끝과 반복 중첩을 확인했다. v2/v3에서는 pitch/cutoff/resonance와 공존하며 block31/64/257 결과가 같았다.
- 신규 `SynthSustainAPITests`5개: 세 엔진에서 구 API와 pedal0의 PCM 동일성, invalid 입력의 무변경, 반복 release·stale off, 65번째 voice의 stealing, held key/다른 stream 보호를 확인했다.
- `MIDISustainGuardTests`10개: 활성 페달은 신스만 지원하며 다른 backend는 준비 전에 거절한다. 기존 all-off PCM과 명시적 center bend 경계를 유지하고 synthetic 종료 이벤트를 포함한 한도를 검사했다.
- 신규 `MIDISustainBounceTests`2개: 실제 section/arrangement compiler→render, 독립 장음 reference, 반복 편곡의 mix/stem, WAV→프로젝트 패키지 저장/재열기→원본 복원을 확인했다. 노트·페달 원본이 보존되며 복원 뒤 PCM이 원래 렌더와 정확히 같았다. 24-bit WAV 재열기는 양 채널의 양자화 오차를 따로 검사한다.

회귀 뒤 WAV 양 채널 오차 assertion을 보강해 `swift test --scratch-path .build/integration-tests --filter MIDISustainBounceTests`를 다시 실행했다. 2개·실패0개, 0.702초에 종료했다(`.build/sustain-dsp-bounce-stereo.log`). 635개에 이2개를 중복 합산하지 않는다.

`swift build --scratch-path .build/app-release -c release --product circlr`는82.91초에 통과했다(`.build/sustain-dsp-release.log`). 별도 앱 패키징·설치·native 실행 검증은 하지 않았다.

C voice 처리와 Swift scheduler의 독립 읽기 전용 소스 리뷰에서 고확신 신규 결함은 발견되지 않았다. 이것은 실제 스피커 청취·연주·native GUI 검증이 아니다. 프로젝트 파일 검사는 임시 디렉터리에서 수행하며 사용자 곡과 production PID86114를 변경하지 않는다.

## 다음 연결

SMF의 CC64·CC121 처리와 전역 track/channel 순서, preserve/omit 설명을 확장한다. 내보내기의 명시적 종료 위치와 합성 pedal-up 계약을 확정한 뒤 raw/의미 round-trip을 검사한다. 이후 같은 캔버스의 MIDI 모드에서 서스테인을 직접 선택하고 초깃값·이벤트 위치/raw·원본/이번 사용/공유 범위를 편집하도록 연결한다. 새 메뉴 깊이나 고정 패널을 추가하지 않는다.
