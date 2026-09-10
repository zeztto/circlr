# 내장 신스 cutoff 오토메이션 구현 계획

상태: build127 이후 소스를 읽어 작성한 계획이다. 구현·테스트·Release·native 청취를 수행한 결과가 아니다. 목표는 한 곡에서 브레이크다운의 닫힌 음색을 후렴으로 열어 가는 변화를 서클의 시간에 작성하고, GUI/MCP 편집부터 바운스·복원까지 같은 결과로 이어 가는 것이다.

## 현재 소스와 필요한 연결

[AutomationParameter](../Sources/CirclrCore/Automation.swift)는 gain/pan만 지원하고 lane 개수는 최대2개다. 같은 파일의 AutomationLane/Span은 beat/seconds 구간의 선형·hold 보간을 수행한다. [AutomationDSP](../Sources/CirclrAudio/AutomationDSP.swift)는 완성 PCM에 gain/pan을 적용한다.

[SectionGraphRenderer](../Sources/CirclrAudio/SectionGraphRenderer.swift)는 instrument node로 들어온 MIDI를 모아 ProductionInstrument.render에 전달한다. [ProductionInstrument](../Sources/CirclrAudio/ProductionInstrument.swift)의 SynthEngine은 생성 시 patch.cutoff를 받고 note/render만 노출한다. [CirclrSynth.h](../Sources/CirclrRealtime/include/CirclrSynth.h)와 [synth.c](../Sources/CirclrRealtime/synth.c)에 렌더 중 cutoff 제어 경로가 없다. 완성 PCM에 새 필터를 거는 것으로 신스 내부 cutoff를 대신하지 않는다.

## 파라미터 계약

첫 대상은 내장 synthesizer를 사용하는 `.instrument(trackID)` node다. 저장 이름은 `synthCutoff`, 값은 절대 Hz로 제안한다. [SynthPatch.validate](../Sources/CirclrCore/ProductionModel.swift)의 기존 범위와 같은 유한한40–20,000Hz를 받는다. engine2/3의 DSP는 key tracking·velocity·filter envelope·motion 이후 실제 cutoff를40–18,000Hz로 clamp한다. automation은 그 앞의 base cutoff를 바꾸며 이 기존 보정을 없애지 않는다. 따라서20,000Hz 값이 실제 최종 필터 주파수20,000Hz라는 뜻은 아니다.

곡선 없음 또는 enabled:false는 기존 patch.cutoff를 그대로 사용한다. enabled 곡선은 base cutoff를 대체하고 patch 값에 곱하지 않는다. 곡선이 비어 있으면 삭제라는 기존 편집 계약을 유지한다. cutoff의 fallback을 공통 neutral=0으로 계산하지 않는다. 첫 점 이전·마지막 점 이후 및 release tail은 활성 곡선의 경계 값을 유지한다.

**보간은 Hz 선형으로 고정한다.** 기존 `.linear` 의미를 바꾸지 않는다. 400→6,400Hz의 중간값은3,400Hz다. `.hold`는 다음 점 경계에서 전환한다. 세로축·슬라이더의 위치만 log-frequency로 표시한다: `n = log(hz/40) / log(20000/40)`. 실제 곡선은 Hz 값을 계산한 뒤 log 위치에 그리므로 log 축에서 두 끝점을 직선으로 연결해 잘못 표시하지 않는다. 향후 octave/log 보간은 별도 명시적 shape 계약으로 추가하며 이번 범위에 숨겨 넣지 않는다.

## 타깃 검증과 저장 호환

공통 descriptor에 id·표시 이름·Hz 단위·범위·표시 변환·지원 대상·fallback 정책을 둔다. target validation은 node만 보지 않고 실제 track.instrument.kind까지 확인한다. audio/rhythmAudio·MIDI·output·effect·sampler·AU에 cutoff를 쓰면 UI에서 숨기고 Core/MCP에서 거절한다. 비활성 cutoff lane도 미지원 타깃에 남겨 두지 않는다. 악기 종류 변경으로 기존 cutoff lane이 무효해질 때는 명시적 제거 없이 조용히 버리지 말고 원자적으로 거절한다.

새 enum을 모르는 구버전이 새 문서를 안전하게 거절하도록 schemaVersion3을 신규 기능의 저장 경계로 제안한다. 기존 version1/2를 여는 것만으로3으로 올리지 않고 cutoff lane이 처음 저장되는 명시적 편집에서 승격한다. 승격한 문서는 lane을 지워도 자동 downgrade하지 않는다. Undo는 편집 이전의 정확한 schema를 복원해야 한다. 구현 전에 [ProjectStore](../Sources/CirclrCore/ProjectStore.swift)의 decode 순서와 오류 안내를 확인해 header preflight 또는 동등한 안전한 거절을 보장한다. unknown enum을 버려 읽는 호환 처리는 금지한다.

현재 version1/2 guard가 있는 [Compiler](../Sources/CirclrCore/Compiler.swift), [SectionGraphMigration](../Sources/CirclrCore/SectionGraphMigration.swift), [AlbumModel](../Sources/CirclrCore/AlbumModel.swift), [SectionInsertion](../Sources/CirclrCore/SectionInsertion.swift)도 함께 점검한다. 기존 schema fixture·렌더는 유지하며 상한 숫자만 일괄 바꾸고 끝내지 않는다. 새 형식 지원은 앱 build/capability와 문서에 명시한다.

## 렌더 API와 시간

C render-owned API를 추가해 현재 frame의 cutoff 또는 읽기 전용 cutoff span을 전달한다. 제어는 render thread에서만 소비하고 voice의 oscillator phase·age·envelope·필터 적분 상태·chorus·steal tail을 재생성하지 않는다. 기존 note producer가 비동기로 s->cutoff를 직접 쓰게 만들지 않는다. 기존 정적 render 호출은 그대로 남겨 곡선 없는 프로젝트의 경로를 보존한다. UI thread의 값 변경과 실시간 callback의 data race를 피한다.

ProductionInstrument.synth는 음표 이벤트와 cutoff automation을 동일 sample clock에서 평가한다. sample마다 또는 정확한 span 평가로 처리하고1024-frame 블록 시작 값만 사용하는 계단 근사로 끝내지 않는다. hold 경계·tempo 경계·반복 경계에서 event ordering을 정의하고 block size와 무관한 출력을 검사한다. render callback에서 allocation·lock·파일 I/O를 추가하지 않는다. smoothing을 암묵적으로 넣어 hold/기준 PCM을 바꾸지 않으며 실제 discontinuity가 문제가 되면 명시적 곡선 편집으로 해결한다.

SectionGraphRenderer는 plan.automation에서 synthCutoff를 해당 instrument render에 전달하고 gain/pan만 기존 AutomationDSP로 보낸다. cutoff가 후단 PCM 처리에서 두 번 적용되지 않도록 한다. ordinary/shared MIDI의 fan-in을 동일 instrument 음원에 적용하며, 다른 instrument node의 automation이나 원본 track patch를 바꾸지 않는다. node.startBeat·local tempo·부모 tempo map·명시 length/repeat의 기존 compile 의미와 tail을 유지한다. pre-output 바운스에는 instrument cutoff가 포함되고 output gain/pan은 기존 규칙을 따른다.

LiveSynth는 같은 C engine을 사용하지만 note 미리 듣기에는 곡의 transport clock이 없다. 미리 듣기는 patch 기준 음색을 유지하고, 실제 곡의 automation을 라이브 audition에 적용했다는 주장을 하지 않는다. 향후 continuous render/transport와 연결할 때 동일 frame-domain 제어 API를 재사용한다. prepared song playback·오프라인 바운스는 이번 end-to-end 대상으로 포함한다.

## GUI·MCP 동선

[AutomationEditor](../Sources/CirclrApp/AutomationEditor.swift)의 gain/pan 이분법인 수치 필드·표시 단위·nudge·정규화·눈금·도움말을 descriptor 기반으로 바꾼다. [AutomationDisplay](../Sources/CirclrCore/AutomationDisplay.swift)와 공통 숫자 입력도 Hz 정밀도를 보존한다. 선택한 신스 instrument에서 ⌘5 → 필터 cutoff → 점 입력을 같은 캔버스에서 제공한다. 다른 타깃으로 이동하면 지원하지 않는 파라미터가 선택 상태로 남지 않도록 유효성 검사를 한다.

[AgentProtocol](../Sources/CirclrCore/AgentProtocol.swift)과 [MCP schema](../mcp/server.py)의 set_automation parameter와 value 검증을 함께 확장한다. 현재 generic value 범위−1…4는 Hz를 받을 수 없으므로 parameter별 조건 검증을 정의한다. original 생략/false·true, A 원본/B override·strict revision·atomic batch를 그대로 유지한다. snapshot/inspect로 지원 descriptor를 조회할 수 있게 하고 구버전 앱에서 도구 schema만 새 기능을 광고하지 않도록 capability를 연결한다. plugin 파라미터 지원으로 일반화하지 않는다.

## 구현 순서와 검증

1. descriptor·지원 target·schema 계약과 Core 테스트를 먼저 고정한다. GUI/MCP·DSP 작업은 이 결과를 공유하고 파일 소유권을 분리한다.
2. render-owned C API와 offline instrument 경로를 연결한다. 기존 curve 없음·disabled 결과를 고정 patch와 byte/PCM 단위로 대조한다.
3. SectionGraph의 automation 전달·시간 경계·바운스 경로를 검증한다. Core original/override를 GUI/MCP와 연결한다.
4. 같은 authored 곡에서 신스 cutoff sweep을 작성하고 A/B 비교·바운스·원본 복원·Undo·저장/재열기를 실행한다. 작은 창과 키보드 가시성도 함께 확인한다.

필수 자동 검증은 다음과 같다.

- engine1/2/3 각각 lane 없음·disabled에서 기존 고정 patch PCM 유지. 일정 곡선400Hz는 같은 patch400Hz와 일치하며 지속 voice 상태가 유지된다.
- 400→6,400Hz linear의 midpoint3,400Hz, hold 경계, 첫/끝/tail 값과 nonfinite·범위 밖 입력 거절.
- sustained chord에서 초반/후반 고역 에너지 차이 측정. FFT 창·정규화·허용 오차를 고정하며 음량 차이만으로 필터 동작을 판정하지 않는다.
- 64/257/1024-frame 분할에서 동일 cutoff/time 이벤트 결과 비교. note-off·짧은 노트·긴 release·retrigger·repeat·tempo map 경계 포함.
- instrument별 fan-in/다른 node 보존, pre-output 바운스 전후 PCM·원본 복원, A 원본 sweep/B override 유지와 한 batch Undo.
- 미지원 타깃·악기 종류 변경·잘못된 schema/parameter·stale revision의 원자적 거절. 기존 version1/2 재열기·원본 파일 무변경과 새 version3의 안전한 호환 거절.
- native Hz 입력·log 눈금/실제 곡선·Tab/Undo·GUI/MCP 동등 결과·정확한 저장 재열기. 물리 출력/청취는 별도 수행 결과로 표시한다.

완료는 enum·UI 추가가 아니라 실제 cutoff 변화가 담긴 곡 렌더와 편집 복원까지 입증했을 때 판단한다. 이 계획 작성 시점에는 위 구현·검증을 수행하지 않았으며 [현행 개발 계획](138-current-development-plan.md)의 나머지 DAW·음악 품질·아티스트 범위도 유지한다.
