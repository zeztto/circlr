# MIDI pitch bend의 연주·편집 계약

상태: build132 이후 수립한 설계와 단계별 기록이다. 내장 신스 연결과 가져오기 취소 복귀는 [build133 검증](155-pitch-bend-synth-and-import-return.md)에서 완료했다. 파일 가져오기는 [build134 검증](156-midi-pitch-bend-import.md)에서 구현했다. 전체 GUI 표현 편집·모든 backend 렌더 지원 완료는 아니다. 전체 DAW와 UI 개선 목표의 표현 편집 작업이며 단계 완료를 기능 전체 완료로 바꾸지 않는다.

## 실제 손실 지점과 방향

`MIDIImport.swift`는 track/channel별 Note를 만들지만 channel message는 제외한다. `MIDIImportPart`는 channel을 drums 여부로만 사용한다. `Note`에는 채널이 없다. 조사 당시 없던 `Lane`/`RhythmPattern`의 bend 저장은 아래 Core 연결 단계에서 추가했다. `SectionGraphRenderer.swift`는 여러 source의 notes를 합치며 `ProductionInstrument.swift`, C Voice/Event, AU worker는 그 출처를 받지 않는다. 악기 전역에 bend 배열만 추가하면 독립 MIDI 서클의 음정이 같이 바뀐다.

저장값은 14-bit raw 값과 RPN range 상태를 유지하고, DSP에는 해석된 반음과 안정적인 source identity를 전달한다. 반음 곡선만 저장하여 원래 wheel 값과 범위를 잃는 방식은 사용하지 않는다. 같은 MIDI source의 함께 울리는 노트에는 bend가 함께 적용된다. 다른 source는 같은 파일 채널 번호라도 별도 연주 영역이며 graph edge 순서로 서로의 controller를 덮어쓰지 않는다.

## MIDI 근거와 제품 결정

[MIDI Association 메시지 표](https://midi.org/summary-of-midi-1-0-messages)는 pitch bend의 14-bit·중심 2000H·LSB/MSB 순서와 수신기/RPN 0에 따른 sensitivity를 정의한다. [RPN 표](https://midi.org/midi-1-0-control-change-messages)는 CC101/100 선택, CC6/38 data entry, RPN0의 반음/센트 및 null 선택을 설명한다. 이 공개 표는 상세 규격 전체를 대체하지 않는다.

초기 값 8192와 범위 2반음·0센트는 circlr의 명시적 기본값이다. 파일의 RPN 상태가 있으면 그 상태를 보존한다. raw 0…16383, range의 두 data byte는 각각0…127로 보존한다. 반음 환산은 `(raw-8192)/8192 * (semitones+cents/100)`으로 고정한다. 따라서 양의 최댓값은 range보다 한 step 작다. [Roland MIDI 구현 문서](https://static.roland.com/assets/media/pdf/FANTOM-06_07_08_MIDI_Imple_eng01_W.pdf)의 signed8192 환산과도 맞는다. UI는 raw 정확값과 반음 표시를 구분한다.

## 저장·시간 계약

1. `MIDIPitchBendRange`, `MIDIPitchBendEvent`, `MIDIPitchBendSequence`를 Core 독립 타입으로 먼저 검증한다. sequence는 원래 channel0…15, initialValue/initialRange, 시간순 value/range 이벤트를 갖는다. 같은 beat는 배열 순서를 유지하고 마지막 상태가 이후 구간에 적용된다. hold가 원본 MIDI 의미이며 임의 smoothing/linear 보간을 넣지 않는다.
2. 모든 beat는 finite·0 이상·131072 이하, 이벤트 최대100000, 내림차순·범위 밖 값은 거절한다. 초기 상태와 시간이 다른 sequence가 같은 음정을 내더라도 원본 데이터는 합치지 않는다. nil은 기존 연주 경로다. range 변경만으로도 현재 wheel의 음정이 변한다.
3. Lane/RhythmPattern에 optional sequence를 연결하는 단계에서 schema5 승격·구버전 읽기·Undo를 함께 처리한다. 독립 Core 타입 추가만으로 프로젝트 schema를 올리지 않는다. 공유 pattern의 setLane 복사 경로도 표현을 보존해야 한다.
4. 반복 occurrence는 별도 stable stream identity를 갖는다. 새 반복의 초기 상태가 앞 반복의 release voice를 재설정하지 않는다. note-off가 wheel을 초기화하지 않으며 source 종료 뒤 남은 release에는 마지막 유효 상태가 유지된다. source/channel과 occurrence를 평탄화하기 전에 clock으로 이벤트 시간을 변환한다.
5. 같은 sample에는 note-off → 초기/range/bend의 최종 상태 → note-on을 적용한다. raw 이벤트의 같은 beat 순서는 보존하지만 무시간 간격의 여러 MIDI 메시지를 샘플 안에서 물리적으로 재현한다고 주장하지 않는다. 모든 renderer가 같은 정렬 규칙을 사용한다.

## 구현 순서와 owner 경계

- Core 기초: 새 `Sources/CirclrCore/MIDIPitchBend.swift`와 독립 테스트. 상태 평가·검증·직렬화만 담당하며 아직 프로젝트 저장/GUI를 노출하지 않는다.
- Core 연결: `Model.swift`, `MIDIEditing.swift`, `Compiler.swift`, `SectionGraphCompiler.swift`, `ProjectStore.swift`, schema guard, `ProductionModel.swift`의 MIDIFile. 일반/공유 source와 발생별 compiled performance packet을 연결한다. raw/RPN import는 Audio owner와 합의 후 진행한다.
- Audio/DSP: `MIDIImport.swift`, `ProductionInstrument.swift`, `SectionGraphRenderer.swift`, `synth.c`, `CirclrSynth.h`. per-stream controller/voice 소유권을 유지하고 bend는 phase/envelope/filter를 리셋하지 않는다. center/nil은 기존 PCM 경로를 보존한다. queue가 가득 찼을 때 누락을 성공으로 처리하지 않는다. sampler·SoundBank·AU는 각 backend 지원과 count/time/range 검증이 필요하다.
- AU protocol: `AUInstrumentWorkerProtocol.swift`, `AUInstrumentWorkerProcess.swift`, `AUInstrumentWorkerService.swift`, `AudioUnitHost.swift`. 독립 stream을 실제 채널로 매핑할 수 없는 경우 명시적으로 거절한다. 무조건 channel0/9로 합치지 않는다. 실제 plugin의 RPN 반응은 별도 검증이다.
- UI: `MIDIWorkspaceToolbar.swift`에서 노트/스텝 옆 피치 벤드를 직접 전환하고 `InlineCircleEditor.swift` 내부 같은 공간의 `PitchBendWorkspace`를 연다. 악기 오토메이션으로 이동시키지 않는다. 실제 use·트랙·공유패턴 범위를 표시하고 선택 점의 위치/변위를 바로 편집한다. 새 고정 사이드바를 만들지 않는다.
- MCP: `AgentProtocol.swift`, `AgentWorkspace.swift`, `AgentMIDIImport.swift`, `mcp/server.py`. 일반주소 arrangement/use/lane과 shared pattern/track을 혼합하지 않는다. capability·revision·atomic batch·preview·명시적 제외 선택을 연결한다.

## import와 편집 경계

파일 track 사이에서도 동일 MIDI channel의 원래 controller 흐름은 parser가 안정적인 파일 순서로 해석한 뒤 각 독립 source에 제공한다. RPN0 selection/data entry/null/range change를 처리하고, 해석하지 못하는 관련 RPN/NRPN·increment/decrement·MPE가 표현에 영향을 주면 지원하는 것처럼 가져오지 않는다. 지원하지 못한 표현은 고정 오류와 구체적인 이유를 보여주고 사용자가 명시적으로 표현 제외를 선택한 경우에만 노트 경로로 간다. 시간 이후 state carry와 파일의 선행 쉼표를 보존한다.

노트 이동/생성은 기존 bend를 조용히 다른 구간에 붙이지 않는다. 구간 복제/잘라내기는 시작 시점의 wheel/range 상태를 seed로 합성하고 이후 이벤트를 옮기는 명시적 표현 포함 명령으로 처리한다. generate_midi의 기존 표현 유지/제거 선택도 계약에 포함한다. MIDI 저장은 raw/RPN 상태를 반영하고 재가져오기에서 의미를 대조한다. MPE/개별 음표 bend/CC 전체 지원은 이번 기능으로 주장하지 않는다.

## 완료 증거

Core에서 중심·양끝·range 변경·같은 beat 순서·직렬화·불변 입력·invalid count/time/value를 검사한다. 다음 단계는 두 source 같은 pitch의 서로 다른 bend, 두 반복의 release 중첩, tempo override/shared 반복의 sample 시간, cutoff와 동시 작동, block64/257/1024 PCM 동일, nil/center legacy byte-exact, import/export 상태 round-trip, GUI/MCP 동등 결과·Undo·저장/재열기다. native UI는1024×768·콘솔122에서 직접 전환과 고정 오류·수치·빈 곡선 Tab을 확인한다. offline export→bounce→restore와 물리 I/O/실제 청취는 별도 증거다.

## Core 기초 구현 결과

`MIDIPitchBend.swift`에 Range·Event·Sequence(Codable/Equatable/Sendable)와 조회 결과 State를 추가했다. `validate()`는 데이터 전체를 확인하고 `state(atBeat:)`는 그 시점까지 저장 순서대로 hold 상태를 평가한다. 이후 시점에 잘못된 이벤트가 있어도 조회를 성공시키지 않는다. 전체 검증을 포함한 O(event count) 편의 조회이므로 실시간 sample별 API로 사용하지 않으며 renderer는 다음 단계의 검증된 순차 cursor를 사용해야 한다.

`swift test --scratch-path .build/integration-default --filter MIDIPitchBendTests`가 8개 테스트·실패0으로 통과했다(0.020초, `.build/pitch-bend-foundation-tests.log`). raw 양끝과 중심·range-only 변경·같은 beat 순서·JSON 보존·값/시간/개수 경계·이후 invalid 이벤트를 확인했다. 별도 읽기 전용 설계/소스 검토도 PASS했다. 이 검증은 source fan-in/반복 release/실제 MIDI RPN parser/PCM을 아직 증명하지 않는다.

## 프로젝트 저장·컴파일 연결 상태

`Lane`과 `RhythmPattern`에 optional `pitchBend`를 연결하고 `MIDIPitchBendStorage.swift`에서 schema5 저장·검증 경계를 다룬다. `MIDIPerformance.swift`와 `SectionGraphCompiler.swift`는 source와 반복 occurrence를 구분하는 performance packet 및 부모 clock으로 변환한 상태를 준비한다. 이는 controller를 소리로 재생하는 DSP 구현과 별개다.

`SectionGraphRenderer.swift`는 실제 출력으로 연결된 MIDI 연주의 미지원 pitch bend를 오류로 거절한다. 음소거·연결되지 않은 보관 서클까지 일괄 차단하는 계약은 아니다. `ProductionModel.swift`의 typed MIDI 저장 경로도 선택된 연주에 pitch bend가 있으면 파일을 만들지 않고 명시적으로 거절한다. 표현을 조용히 버린 notes-only 결과를 성공으로 반환하지 않기 위한 경계다.

이 저장·컴파일 연결 단계 당시 패키지 앱은 build132였다. 이 단계 당시 실제 SMF pitch bend/RPN parser, per-stream DSP, GUI 곡선 편집과 MCP 표현 명령은 미지원이었다. 이후 내장 신스 DSP만 build133에서 연결했으며 나머지 표현 편집과 AU/sampler 지원은 남아 있다. SMF bend/RPN parser와 명시적 미지원 처리는 이후 [build134 가져오기 검증](156-midi-pitch-bend-import.md)에서 구현했다. 다음 실행은 GUI/MCP 표현 편집과 SMF 내보내기 왕복이다. 내장 신스 DSP와 nil/center 기존 PCM 보존은 build133의 완료 범위로 유지한다. 이 저장·거절 경계를 전체 연주 기능 완료로 계산하지 않는다.

## 저장·컴파일 회귀 검증

`swift test --scratch-path .build/integration-default --filter 'CirclrCoreTests|CirclrAudioTests' --skip 'AudioTests.testArrangementRenderExportAndPlayback'`는 765개 테스트, 내부 skip 2개, 실패 0개로 73.023초에 종료했다 (`.build/pitch-bend-regression-final.log`). 기초 상태 검사와 Storage 8개·Performance 6개·Export 3개·Audio guard 8개를 포함한다. Core take 경로의 P2 지적은 수정 후 재검토에서 해결됐으며 Audio 검토도 PASS했다.

명시적으로 제외한 기존 `testArrangementRenderExportAndPlayback`은 실제 재생을 포함하며, 첫 실행에서는 AU helper를 사용할 수 없어 재생 전에 실패했다. 내부 skip 2개는 `AUEffectWorkerIntegrationTests`의 실제 worker 경로와 `AUInstrumentWorkerIntegrationTests`의 bounded runner/helper 경로가 없는 데 따른다. 따라서 이 회귀 결과를 실제 AU worker·재생·물리 오디오 성공으로 해석하지 않는다. 이번 단계에서 새 native GUI나 패키지 앱 검증은 수행하지 않았다.

추가 router 검증은 `swift test --scratch-path .build/integration-default --filter MIDIPitchBendGuardTests`로 9개·실패 0개, 0.517초에 통과했다 (`.build/pitch-bend-router-final.log`). 사용하지 않는 포트와 route gain 0에서는 PCM 0을 확인했고 활성 route에서는 미지원 표현을 명시적으로 거절했다. 위 765개 회귀와 별도 실행이며 실제 장치 출력 검사가 아니다.
