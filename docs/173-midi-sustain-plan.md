# MIDI 서스테인 페달의 저장·연주·편집 계약

기준: build149 커밋 `67f9643` 이후의 소스 조사. 이번 단계는 독립 Core 상태 타입과 검증을 추가한다. 프로젝트 저장·SMF 가져오기·DSP·GUI/MCP 연결은 아래 후속 단계이며, 앱에서 페달을 사용할 수 있다는 의미가 아니다. 설치 앱과 build 번호는 유지한다.

## 해결할 문제와 근거

`Sources/CirclrAudio/MIDIImportExpression.swift`는 CC64를 처리하지 않아 제외 이벤트로 계산한다. `Sources/CirclrAudio/MIDIPitchBendRenderer.swift`의 note-off는 즉시 voice release를 시작한다. 노트 길이를 늘려 페달을 흉내 내면 건반을 놓은 위치와 페달을 다시 편집할 의미가 사라진다. 원래 Note와 별도의 원본 controller 이벤트를 유지해야 한다.

[MIDI Association의 MIDI 1.0 Control Change 표](https://midi.org/midi-1-0-control-change-messages)는 CC64를 Damper Pedal on/off로 정의하며 0…63은 off, 64…127은 on이다. circlr의 첫 구현은 이 MIDI 1.0 이진 연주 의미를 사용하되 원래 raw 값을 그대로 저장한다. raw 64와 127을 같은 숫자로 정규화하지 않는다. half-pedal 음향 모델이나 MIDI 2.0 Piano Profile 지원을 주장하지 않는다.

## Core 기초 계약

- `Sources/CirclrCore/MIDISustain.swift`: `MIDISustainEvent(beat:rawValue:)`, `MIDISustainState(rawValue:)`와 `isDown`, `MIDISustainSequence(channel:initialValue:events:)`.
- sequence는 Codable·Equatable·Sendable이며 channel 0…15, initialValue 기본 0, raw 0…127, finite beat 0…131072, 최대 100000개 이벤트를 허용한다. 내림차순은 거절하고 같은 beat의 배열 순서는 보존한다.
- `validate()`는 전체 시퀀스를 검증한다. `state(atBeat:)`도 조회 뒤쪽의 잘못된 이벤트를 숨기지 않는다. 반환은 조회 시점까지의 최종 hold 상태이며 입력을 변경하지 않는다. O(event count) 편의 API이므로 sample별 렌더에 호출하지 않는다.
- 최종 상태 조회와 원본 이벤트 처리는 다르다. 같은 시점의 127→0→127에는 이미 건반을 놓은 음의 release가 포함될 수 있으므로 renderer가 마지막 값 하나로 합치면 안 된다.
- 독립 타입만 추가하는 현재 단계는 `Project`, schema, 앱 UI, MIDI 파일, 기존 PCM 경로를 바꾸지 않는다. nil과 명시적인 초기 off 시퀀스의 구분은 후속 optional 저장 연결에서 유지한다.

## 후속 단계와 파일 담당

### 1. 프로젝트 저장·컴파일과 미지원 경계

Core owner가 `Model.swift`의 Lane/RhythmPattern에 optional `sustain`을 추가하고 신규 `MIDISustainStorage.swift`에서 일반 섹션·inactive use override·added lane·공유 pattern·take를 모두 검사한다. `MIDIEditing.swift`의 공유 pattern↔lane 복사도 포함한다. pitch bend와 함께 저장할 때 두 channel은 같아야 한다. 한 lane의 노트에는 channel별 소유권이 없으므로 서로 다른 channel을 조용히 합치지 않는다.

최초 명시적 sustain 저장에만 schema7을 사용한다. `ProjectStore.swift`, `Compiler.swift`, `AlbumModel.swift`, `SectionGraphMigration.swift`, `SectionInsertion.swift`의 guard와 실제 schema 승격 호출부를 함께 갱신한다. 열기·빈 화면 탐색·no-op은 승격하지 않으며 clear는 이미 승격한 버전을 낮추지 않는다. Undo는 이전 프로젝트 전체를 복원한다.

`MIDIPerformance.swift`와 `SectionGraphCompiler.swift`는 bend 또는 sustain이 있으면 하나의 source/occurrence stream을 만든다. 둘을 별도 stream으로 만들어 노트를 중복하지 않는다. initialSustain과 ordered timed sustain 상태를 같은 parent seconds clock으로 변환한다. pattern swing은 노트에만 적용한다. 부모 tempo map·local tempo·반복·잘린 길이의 기존 clock 경계를 따른다.

Audio owner는 저장 연결과 동시에 `SectionGraphRenderer.swift` 및 typed `MIDIExpressionExport.swift`에서 아직 처리하지 못하는 활성 sustain의 명시적 거절을 연결한다. 실제 출력에 연결되지 않은 보관 서클까지 전부 차단하지 않는다. 표현을 버린 파일·PCM을 성공으로 반환하지 않는다. 이 단계는 저장/거절 경계의 완료로만 기록한다.

### 2. 내장 신스의 독립 voice 연주

Audio/DSP owner 경로: `Sources/CirclrAudio/MIDIPitchBendRenderer.swift`, `ProductionInstrument.swift`(내부 `SynthEngine` 포함), `Sources/CirclrRealtime/synth.c`, `Sources/CirclrRealtime/include/CirclrSynth.h`. 정확한 C/API 선언은 수정 직전 재확인한다.

stream별 pedal 상태와 voice별 key-held/deferred-release를 분리한다. pedal-down 중 note-off는 key만 해제한다. pedal-up은 같은 stream에서 이미 key-off인 voice만 release한다. 누르고 있는 키·다른 source·다른 반복은 유지한다. release가 시작된 음을 이후 pedal-down으로 되살리지 않는다. 같은 pitch 재타건은 voice ID로 구분하고 기존 voice stealing 계약을 유지한다.

동일 sample에는 기존 note-off → controller → note-on 순서를 사용한다. controller 안에서는 같은 시간의 원래 pedal 이벤트 순서를 유지한다. 현재 Note는 SMF 전체 메시지 순서를 저장하지 않으므로 같은 tick에서 note와 CC64가 교차한 원래 순서까지 보존하는 것은 아니다. 이 제한을 import 안내와 테스트에 포함한다. occurrence의 controller 끝은 end-exclusive이며 끝 경계에서는 pedal을 해제한다. 이때 아직 key-held인 음을 일괄 종료하지 않는다. 공유 pattern의 긴 노트가 controller 경계를 넘는 기존 동작과 충돌하면 안 된다. 다음 반복은 자기 initialValue로 시작한다.

기존 allCenter 빠른 경로는 sustain의 유효 변화도 없는 경우에만 허용한다. nil/항상 off는 기존 PCM 보존을 검증한다. bend·cutoff·resonance는 지속 중인 같은 voice에 적용하며 phase/envelope/filter를 재설정하지 않는다. AU·sampler·SoundBank는 backend별 구현·검증 전까지 명시적으로 거절한다.

### 3. SMF 가져오기·내보내기

Audio owner가 `MIDIImportExpression.swift`, `MIDIImport.swift`에 기존 전역 track/channel 순서를 따라 CC64를 보존한다. controller-only 구간·선행 쉼표·마지막 pedal 위치도 import offset/길이 계산에 포함한다. CC121=0은 pedal 해제 이벤트로 해석하되 reset-only 파일에 불필요한 sustain 객체를 만들지 않는 정책을 테스트한다. 상세 reset 의미는 구현 전에 공식 MIDI receiver/reset 규격과 대조한다.

Core/App owner는 `MIDIImportExpressionPolicy.swift`, `AgentMIDIImport.swift`, `MIDIImportView.swift`의 preserve/omit 안내와 preview를 확장한다. 현재 “피치 벤드만 제외” 문구로 sustain까지 제외하면 안 된다. 미지원 표현은 이유를 보여주고 명시적인 제외 선택을 요구한다.

`MIDIExpressionExport.swift`는 sustain 또는 bend를 독립 melodic channel 배정 경로에 포함한다. 같은 파일의 nil source에도 필요한 CC64=0 seed를 넣어 이전 channel 상태가 유입되지 않도록 한다. 표현 없는 파일은 기존 byte-exact 경로를 유지한다. sustain 중 같은 pitch 재타건과 key-held overlap은 구분한다. 채널 부족·표현 불가능한 노트 중첩은 기존처럼 거절한다.

내보내기 종료 정책은 파일/API에 명시적 end beat를 전달해 정한다. 단순히 마지막 note-off를 곡의 끝으로 추정하지 않는다. 유효 controller 끝에서 pedal-up을 합성한다면 그 사실과 끝 위치를 round-trip 비교에 포함하고 합성 이벤트를 원본 raw 데이터와 동일하다고 주장하지 않는다. 이 종료 계약을 확정하기 전에는 export를 지원으로 노출하지 않는다.

### 4. 같은 캔버스의 편집과 MCP

UI owner는 `MIDIWorkspaceToolbar.swift`에서 노트/스텝/피치 벤드와 같은 깊이에 서스테인을 배치하고 `InlineCircleEditor.swift` 안의 신규 `SustainWorkspace.swift`로 연결한다. 초기값·점 추가/삭제·위치/raw 편집·전체 제거를 제공하며 on/off는 raw와 함께 표시한다. hold만 지원하고 열기만 해서는 시퀀스를 생성하지 않는다. 범위 밖 이벤트는 보존하고 보이는 범위를 맞추는 동선을 제공한다.

Core owner의 신규 `MIDISustainEditing.swift`, `SustainWorkspaceState.swift`, `AgentSustainEditing.swift`를 App의 신규 `SustainStore.swift`가 사용한다. `AppStore.swift`, `CommittedNumberField.swift`, `EditorFocusNavigation.swift`, `SavedWorkspace.swift`, `CircleEditorWorkspaceMemory.swift`, `SectionSettingsNavigation.swift`에서 숫자 identity·focus·선택 복귀를 연결한다. 유효 draft 확정 뒤 동일 주소를 재검사하고 invalid 입력은 모드 전환을 막는다. sequence/선택 index가 바뀐 stale draft로 다른 이벤트를 덮지 않는다.

MCP owner는 `AgentProtocol.swift`, `StudioWorkspace.swift`, `AgentWorkspace.swift`, `mcp/server.py`에 `edit_sustain` 및 `midiSustainEditing:1`을 추가한다. 일반 주소 arrangement/use/lane/original과 공유 주소 pattern/track은 혼합하지 않는다. insert/update/remove/setInitial/clear를 기존 apply·preview·revision·atomic batch 계약으로 처리한다. capability는 실제 저장·편집·지원 렌더 경계가 연결된 후에만 노출한다. 패키징 때 `Resources/Codex`의 생성 파일 parity를 확인한다.

## 검증 순서와 완료 기준

1. 기초 타입: `Tests/CirclrCoreTests/MIDISustainTests.swift`에서 raw 0/63/64/127, 초기 down, 같은 beat 순서·JSON 보존, 불변 입력, invalid 값/시간/channel/count/순서와 조회 뒤 invalid를 검증한다. 기존 프로젝트 schema가 그대로인지 확인한다.
2. 저장·컴파일: 신규 storage/performance 검사에서 일반/공유/inactive/take, 오래된 schema·최초 승격·Undo·stale/실패 batch 불변, 동일 source channel, 두 표현의 note 중복 방지를 확인한다.
3. DSP: key-off 지연·pedal-up 다중 release·held key 유지·재타건·release 재포착 금지·source/loop 격리·같은 sample up/down·끝 경계를 확인한다. tempo map/local tempo와 bend/cutoff/resonance 동시 적용, block31/64/257 PCM 동일성 및 nil/off 기존 PCM 동일성을 확인한다.
4. 파일: cross-track carry·CC121·초기/말미 pedal·명시적 omit·지원 거절·export 종료와 import→저장→export→재가져오기 의미를 비교한다. raw round-trip과 합성 종료 상태는 별도 주장이다.
5. native: 1019×768·콘솔122 및 compact 서클에서 직접 전환·첫 수치 가시성·Tab/오류·같은 beat 선택·원본/이번 사용/공유·외부 MCP 변경·Undo/Redo·편곡 전환·재시작을 실제 확인한다. 별도 사각 고정 패널을 추가하지 않는다.
6. 오프라인 bounce→원본 복원·취소·자산 보존을 검증한다. 물리 출력·마이크·실제 청취는 기존 정지 경계 밖이므로 별도 승인된 실행과 증거가 필요하다. 설치 production 앱을 교체하지 않는다.

서로 다른 owner는 위 허용 경로로 병렬 작업하되 공통 model/compiled packet을 Core owner가 먼저 동결한다. root가 통합 빌드·검사를 직렬 실행한다. 독립 리뷰는 source 계약, 실제 데이터, native 화면을 구분하며 기초 타입 통과를 전체 서스테인 기능 완료로 계산하지 않는다.

## 이번 Core 기초 검증 결과

`swift test --scratch-path .build/integration-tests --filter 'MIDISustainTests|MIDIPitchBendTests'`가 build 12.24초 후 신규 Sustain 6개·기존 PitchBend 8개, 총 14개·실패 0개로 끝났다(검사 0.034초, `.build/sustain-foundation-tests.log`). 독립 소스 리뷰에서도 고확신 결함은 없었다. `MIDISustainState`의 직접 initializer는 기존 bend state처럼 검증하지 않는 값 컨테이너이며, 검증된 조회 진입점은 sequence의 `state(atBeat:)`다. 이후 외부 packet을 받는 renderer는 별도 검증해야 한다.

이번 변경은 새 Core/테스트 파일과 문서뿐이다. Release 패키지·native UI·프로젝트 저장·SMF 왕복·PCM·물리 오디오는 이번 단계에서 실행하지 않았고 build149의 과거 검증으로 대신하지 않는다. production PID 86114는 유지했다.
