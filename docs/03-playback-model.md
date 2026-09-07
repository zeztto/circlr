# 재생과 음악 데이터 규칙

> 설계 기준 문서. 0.4.0에서 실행 가능한 범위는 [프로토타입 계약](08-prototype-contract.md)과 [검증 기록](09-prototype-verification.md)을 따른다. 이 문서의 장기 동작 전체가 구현됐다는 뜻은 아니다.

버전: 0.3 · 소유 역할: planner / architecture · 상태: 검토용 계약 제안

이 문서는 제품 구현을 위한 최종 schema가 아니다. 상호작용이 어떤 음악적 결과를 내는지 모순 없이 설명하기 위한 기본 모델이다.

## 두 그래프와 하나의 재생 계획

| 모델 | 노드 | 연결의 의미 | 반복 규칙 |
|---|---|---|---|
| SongGraph | 섹션 사용, 반복 묶음, 시작·끝 | 다음에 무엇을 연주할지 | 횟수가 명시된 음악 반복 허용 |
| SignalGraph | source, instrument, effect, bus, output | audio/MIDI가 어디로 흐르는지 | 기본은 순환 없는 경로; feedback 별도 보류 |
| ExecutionPlan | 시간에 배치된 occurrence와 처리 명령 | 특정 편곡안의 실제 실행 순서 | 모든 반복을 결정한 유한 계획 |

일반적인 한 곡에는 한 시점에 하나의 진행 위치가 있다. 여러 트랙의 동시 연주는 섹션 안에서 처리한다. 전환 overlap과 잔향은 예외적으로 인접 섹션의 audio가 겹치는 명시적 구간이다. SongGraph에서 선을 두 개 그었다고 두 섹션을 동시에 연주하지 않는다.

## 기본 객체

| 객체 | 주요 정보 | 소유 범위 |
|---|---|---|
| Project | revision, 글로벌 MusicalContext, RhythmPattern library, 트랙, 미디어, 섹션 원본, 편곡안, signal graph | 하나의 곡 |
| Track | stable ID, audio/instrument 유형, input, device chain, base mix | 편곡안들이 공유 |
| MediaAsset | stable ID, 파일 참조, checksum, sample rate, 길이 | 원본 audio를 비파괴 보관 |
| SectionDefinition | stable ID, 이름, 길이, 로컬 MusicalContext 정책/map, clip·automation | 공유 가능한 음악 원본 |
| SectionUse | stable ID, definition 참조, clip override, 추가/제외 clip, 길이·mix·MusicalContext override | 특정 편곡안의 사용 위치 |
| FlowNode | stable ID, SectionUse 참조 또는 RepeatGroup, repeatCount | 그래프에서의 자리 |
| Transition | stable ID, edge 참조, 시간 방식, 범위, 대상 IDs, 연주/automation, tail 정책 | 두 사용 위치 사이 |
| Arrangement | stable ID, 이름, 시작·끝, graph, 분기 선택, revision | A안·B안 |
| Occurrence | plan ID, use ID, 방문 번호, 반복 회차, global start/end, 유효 내용 revision | 한 번의 실제 재생 |
| ExecutionPlan | source revision, resolved occurrence, occurrence별 clock map, host transport map, device routing, dependency 목록 | 재생/export snapshot |
| MusicalContext | tempo, scale, meter, BeatGrid, RhythmAssignment의 값과 상속 정책 | 글로벌·원본·사용별 설정 |
| RhythmPattern | ID, 반복 길이, 원래 meter, MIDI/trigger/audio 참조, drum map·Track ID | 실제 리듬 연주 원본 |
| ResolvedMusicalContext | 유효 설정·map·출처 revision | 링·editor·재생 공통 입력 |
| CanvasGroup | 이름, 포함 node IDs, frame, 접힘 상태 | 화면 정리; 음악 동작 없음 |
| PerformanceLog | plan ID, sample clock, 적용 명령, 녹음 구간과 take 참조 | 실제 실행 이력 |

화면상의 좌표·공간 그리드·snap·zoom·group은 LayoutState에 저장한다. 그룹 이동·정렬은 음악 설정과 재생 계획을 변경하지 않는다. 객체의 ID는 이름이나 위치를 바꿔도 유지한다. 표시 이름으로 plugin parameter나 clip을 연결하지 않는다.

## 원본·변형·편곡안의 관계

- SectionUse는 원본을 참조하되 변경한 clip은 **clip 전체 단위**로 override한다. note 단위 자동 병합은 초기안에서 제외한다.
- override하지 않은 clip은 원본 수정 결과를 따른다. override한 clip은 자기 내용을 유지한다.
- 사용별 신규 clip, 원본 clip 제외, 길이 override는 별도 기록한다. 원본 clip ID를 재사용해 신규 clip으로 위장하지 않는다.
- 원본 clip 삭제 시 그 clip의 override가 있으면 충돌 상태로 표시한다. 명시적으로 독립 clip으로 보존하거나 override를 제거한 뒤 다음 계획을 생성한다. 재생 중인 기존 계획은 그대로 유지한다.
- 원본 길이·박자 변경으로 clip이 범위를 벗어나면 잘라버리지 않고 영향을 표시한다. 사용자 해결 전 새로운 전체 재생/export를 막는다.
- `독립 섹션으로 분리`는 현재 유효 내용을 새 Definition으로 고정한다. 이전 원본과의 연결이 해제된다.
- A안을 복제한 B안은 FlowNode·SectionUse·Transition을 새 ID로 소유하지만 SectionDefinition과 Track은 공유한다. B안의 순서/사용별 수정은 A안에 전파되지 않는다.
- 공유 원본과 트랙 기본 mix의 수정은 A/B 모두에 영향을 준다. 완전히 고정된 이전 소리가 필요하면 프로젝트 revision을 저장한다. 편곡안 복제가 전체 프로젝트 fork와 같다고 표현하지 않는다.

## 반복과 분기

`repeatCount = 2`는 총 두 번이다. 각 반복의 clip 위치와 section automation은 로컬 시작으로 돌아간다. instrument processor 자체는 재생 회차마다 새로 생성하지 않는다.

일반적인 SongGraph의 순환 연결은 초기안에서 허용하지 않는다. 반복은 SectionUse의 repeatCount 또는 시작·끝이 정해진 RepeatGroup으로 표현한다. 이로써 `벌스→후렴` 두 구간 반복과 무한 순환을 구분한다. 반복 묶음은 외부 입력 하나, 외부 출력 하나이며 내부를 유한 순서로 펼칠 수 있어야 한다. 중첩 반복은 후속 설계다.

여러 출구는 편곡 대안으로 저장할 수 있으나, 한 Arrangement의 실행에는 출구 하나가 선택되어야 한다. 시작 1개, 도달 가능한 끝, 양의 section 길이, 정수 반복 수, 참조 무결성을 계획 생성 전에 검증한다. 재생하지 않는 미연결 아이디어 섹션은 보관 가능하다.

확률 분기·live jump·무한 반복은 현재 핵심 사용 흐름에 포함하지 않는다. 이후 추가할 경우 선택 결과를 occurrence 이력에 기록하고, export할 때는 유한 경로로 고정해야 한다.

## 음악 시간과 sample 시간

세 시간을 분리한다.

1. **섹션 로컬 음악 시간:** 섹션 시작이 0인 quarter-note 단위 유리수 위치. 셋잇단음표 등 분할을 보존한다.
2. **편곡 위치:** 선택 경로·반복과 occurrence를 식별한다. 각 occurrence는 로컬 음악 시간에서 절대 재생 시간으로의 map을 갖는다. 이종 tempo overlap에서는 하나의 공통 beat 좌표를 강요하지 않는다.
3. **sample 시간:** audio device/export의 공통 64-bit frame 위치. occurrence별 tempo map을 적분한 시간과 시작 offset을 합쳐 대응한다. host transport의 대표 tempo/meter map은 이와 별도로 관리한다.

4/4의 8마디는 32 quarter notes, 7/8의 8마디는 28 quarter notes다. BPM은 quarter-note 기준을 기본안으로 한다. tempo가 같아도 `8마디`만으로 초 단위 길이를 계산해서는 안 된다.

tempo·scale·meter·BeatGrid·RhythmAssignment는 각 항목마다 글로벌/원본 상속 또는 local 값을 적용한다. SectionUse에는 원본 override를 건너뛰는 명시적 global 정책도 둔다. 이전 섹션의 마지막 BPM이나 scale을 숨겨진 상태로 상속하지 않는다. 상속·pattern·scale 변환의 상세 계약은 [서클의 음악 설정](07-canvas-and-musical-context.md)에 둔다. 섹션 길이는 음악 시간으로 저장하고 마디 표시는 meter map에서 얻는다. meter를 바꿀 때 마디 수 보존과 실제 박 길이 보존 중 무엇을 선택할지 UI에서 확인한다.

sample 위치는 occurrence 시작 절대 시간과 local tempo 적분값에서 계산하고 rounding 규칙을 고정한다. 중간 계산의 정밀도를 유지하며 매 섹션의 반올림된 sample 길이를 무조건 더해 누적 오차를 만들지 않는다. MIDI 파일로 내보낼 때의 tick resolution과 양자화 오차는 별도 호환성 계약이 필요하다.

tempo 변경은 MIDI event의 sample 배치에 반영된다. audio는 기본적으로 원속도 재생이며 `tempo 따르기`를 선택한 clip만 time-stretch한다. BPM을 바꿨다는 이유로 녹음이 조용히 늘어나거나 pitch가 변하지 않는다. 길이가 섹션을 벗어나면 표시하고 trim·tail·warp 중 의도를 정한다. stretch 엔진과 품질은 미선정이다.

## 음악 설정의 재생 적용

링의 각도는 local quarter-note 위치/길이에서 계산하고 tempo는 각도의 시간당 진행 속도를 결정한다. 그룹 배치·원 크기·공간 그리드는 이 계산에 관여하지 않는다. 글로벌 설정 변경은 해당 항목을 상속하는 서클만 다시 해석한다.

Scale은 기본적으로 입력·표시 기준이며 기존 절대 pitch MIDI·drum map·audio를 자동으로 바꾸지 않는다. BeatGrid는 눈금·강세·입력 snap 기준이다. 실제 RhythmPattern은 별도 연주 데이터로, 글로벌 패턴을 따르거나 서클에서 다른 패턴/사용 안 함을 선택한다. 중복된 숨은 글로벌 패턴 재생기를 만들지 않는다.

패턴은 자신의 원래 길이로 반복하며 서클의 tempo를 따른다. 서클 meter가 달라도 원본 note를 자동 변형하지 않는다. 경계에서 반복/종료·MIDI ownership 규칙을 적용하고 pattern의 phase reset은 서클 진입·반복을 기본 제안으로 한다. audio pattern의 tempo 추종은 명시적 stretch 설정이 필요하다.

## 전환의 시간 계약

| mode | 시간 범위 | 전체 길이 | 기본 제약 |
|---|---|---|---|
| within | 앞 섹션 끝 또는 뒤 섹션 시작 내부 | 변화 없음 | 대상 구간 길이를 넘지 않음 |
| insert | 앞 섹션 끝과 뒤 섹션 시작 사이 | 지정한 음악 시간만큼 증가 | 명시적 content와 MusicalContext 필요 |
| overlap | 앞 섹션 끝과 뒤 섹션 시작 중첩 | 공통 sample 시간의 겹침만큼 감소 | 출발/도착 서클 기준 길이 또는 초 단위 anchor 명시 |

overlap은 인접한 두 섹션을 대상으로 하고 이종 tempo/meter도 설계 범위에 포함한다. 준비된 각 occurrence의 절대 시간 구간을 교차 검사하여 세 섹션의 동시 진입이나 인접 섹션보다 긴 overlap은 거부하는 것을 기본 제안으로 한다. 동일 박자·tempo의 단순 사례에서만 겹친 마디 수를 빼는 계산을 사용한다. 서로 다른 경우의 clock·plugin 처리 제약은 [이종 서클 연결 규칙](07-canvas-and-musical-context.md)에 둔다.

within 전환은 `replace`와 `layer`를 구분한다. 드럼 필인을 replace하면 해당 범위의 원래 드럼 event를 억제한다. layer는 기존 연주 위에 더한다. 전체 mix를 처리하더라도 원본 녹음 파일을 수정하지 않는다.

Transition은 SectionUse 간 연결에 붙는다. 앞 섹션이 총 두 번 반복되면 출구 전환은 **두 번째 반복의 끝**에서만 실행한다. 매회 필인이 필요하면 섹션 내부에 넣는다. insert의 길이와 content는 Transition 소유의 로컬 구간으로 저장하며 reusable 섹션으로 승격할 수 있다.

## 경계에서의 연주와 잔향

| 대상 | 기본안 | 명시적 확장 |
|---|---|---|
| MIDI note | 경계에서 그 occurrence의 active note 종료 | sustain 연결을 지정한 경우 지속 |
| sustain pedal/CC | 이전 occurrence가 소유한 지속 상태 해제 | 전용 연속 track/context에서 유지 |
| audio clip | 로컬 구간 종료에서 source 입력 종료, 짧은 fade 적용 | tail handle과 pickup 범위 지정 |
| instrument release | note-off 이후 release는 남을 수 있음 | 즉시 절단은 별도 선택 |
| reverb/delay return | processor와 tail을 지속 | hard cut 또는 별도 tail render |
| 빈 트랙 lane | 새 event 없음 | 이전 음의 tail은 정책에 따라 지속 |

같은 MIDI channel/pitch의 note가 overlap하면 단순 note-off가 다음 음을 끊을 수 있다. 초기안은 공유 instrument의 모호한 sustain 연결을 막고, 명시적 voice 분리 또는 audio render가 필요하다. 지원 plugin별 note ownership 동작을 검증하기 전 자연스러운 legato를 보장하지 않는다.

pickup은 다음 섹션 로컬 0 이전의 event로 기록하고, 실행 계획이 이전 섹션 문맥에 배치한다. 곡 시작 전 pickup이 있으면 export 시작 offset에 포함해 파일 길이를 표시한다. 곡 끝의 tail도 본문 마디 길이와 별도 항목으로 표시한다.

트랙 공통 reverb에 앞뒤 섹션이 함께 들어가면 return은 섞인 상태다. 전환이 앞 섹션 꼬리만 따로 조절해야 한다면 별도 return 또는 render가 필요하다. 공통 return에서 이미 섞인 소리를 섹션별로 다시 분리할 수 있다고 가정하지 않는다.

## automation과 effect 상태

트랙 기본값 위에 section automation, 사용별 override, transition automation 순서로 명시적 우선순위를 둔다. 같은 parameter의 같은 우선순위에서 겹치는 두 curve는 암묵적으로 합치지 않고 충돌로 처리한다. gain trim처럼 더하는 값은 별도 parameter로 정의한다.

섹션 진입 시 유효 parameter 상태를 계산하고 boundary에 적용한다. transition이 끝나면 그 시점의 section/track 상태로 복귀한다. audible parameter는 smoothing하고 event 경계는 sample 위치를 보존한다.

plugin chain을 섹션마다 파괴하고 재로딩하지 않는다. 기본안은 준비된 device graph의 parameter·bypass·send를 변경한다. 전혀 다른 instrument preset/state의 전환은 미리 준비된 별도 instance나 render를 사용한다. 내부 처리 지연이 다른 경로는 latency compensation 대상이다.

## 재생 중 편집과 정지

편집 document와 현재 실행 계획은 별도 revision이다. 음표·audio 이동 등 구조 변경은 백그라운드에서 준비하고 유효한 다음 섹션 경계에 적용한다. 전환/pickup의 준비 시작 시점을 이미 지났으면 더 뒤의 경계 또는 정지 후 적용으로 미룬다. `다음 섹션부터 적용` 표시는 실제 적용 가능한 지점과 일치해야 한다.

fader 등 안전하게 smoothing할 수 있는 parameter 조작만 bounded command로 즉시 전달한다. device 추가, plugin 로딩, media decoding은 callback 밖에서 수행한다. 준비가 실패하면 기존 유효 계획을 유지하고 실패 원인을 보여준다.

정지는 신규 event를 즉시 멈추고 note-off 및 짧은 fade를 수행한다. 잔향을 듣는 일반 정지와 모든 소리를 끝내는 `모든 소리 끄기`를 구분한다. 녹음 파일 finalize 실패와 장치 분리는 별도 상태로 보고한다.

중간 위치로 seek하거나 전환을 audition할 때는 해당 위치의 tempo·automation·MIDI 지속 상태를 복원하고 필요한 앞 구간을 pre-roll한다. reverb나 plugin의 내부 이력은 parameter 값만으로 복구되지 않는다. 빠른 audition에서 이력을 생략하면 이를 표시하고, 앞에서부터 재생하거나 render된 문맥으로 듣는 방법을 제공한다. cold start의 소리가 곡 처음부터 재생한 소리와 같다고 보장하지 않는다.

## 녹음

audio는 연속 take 파일로 저장하고 MIDI는 sample clock과 음악 시간 대응을 함께 기록한다. 섹션 경계와 각 반복 회차마다 occurrence 정보를 남겨 편집용 clip 참조를 만든다. 총 2회 반복 녹음은 take 2개이며 첫 take를 덮어쓰지 않는다.

녹음 결과는 기본적으로 현재 사용에 귀속시키고 사용자가 원본으로 승격할 수 있게 한다. count-in, input monitoring, punch 범위, 장치 latency 보정은 녹음 계약에 포함한다. 전문 comping 방식은 별도 결정이다.

편곡을 바꿔도 원본 take bytes를 보존한다. 경계를 가로지른 긴 take의 여러 clip을 유지해서 함께 옮길지, 사용별 clip만 옮길지는 명시적 선택이어야 한다.

초기 녹음 모드에서는 진행 중 take의 시간축이 바뀌지 않도록 구조 변경 적용을 녹음 정지 이후로 미룬다. 사용자는 편곡 초안을 편집할 수 있고 `녹음 후 적용` 상태를 본다. mix 조작과 그 automation 녹음은 sample clock에 기록한다.

## 저장과 내보내기

저장 단위는 Project revision이며, 모든 미디어·plugin state·참조 관계와 편곡안을 포함한다. export는 특정 revision과 Arrangement에서 생성한 유한 ExecutionPlan을 고정한다.

- 오디오 파일에는 선택한 경로, 총길이, 시작 pickup offset, tail 길이, sample rate, bit depth를 기록한다.
- export 도중 편집은 진행 중인 render에 섞이지 않는다.
- realtime와 offline은 같은 event 계획을 사용한다. 외부 plugin의 random state나 외부 장비 때문에 sample까지 같은 결과라고 보장하지 않는다.
- offline을 지원하지 않는 장비/plugin에는 realtime render 경로가 필요하다.
- stem은 동일 시작점과 동일 전체 길이로 내보낸다. shared return은 별도 stem으로 내보내는 것을 기본 제안으로 한다.
- sidechain을 위한 입력은 stem render 중에도 유지한다. master nonlinear processing을 각 stem에 적용한 합이 원래 master와 같다고 보장하지 않는다.
- graph 편집 상태는 선형 MIDI나 stem에 모두 보존되지 않는다. 완전한 편집 가능 원본은 native 프로젝트다.

## 한 곡의 시간 추적

설명용 기준: 4/4, 120 BPM, pickup/tail 없음, within 필인.

| occurrence | 섹션 사용 | 원본 관계 | 전체 마디 |
|---|---|---|---|
| 1 | 인트로 | Intro | 1–4 |
| 2 | 벌스 1 / 1회 | Verse A | 5–12 |
| 3 | 벌스 1 / 2회 | Verse A | 13–20 |
| 4 | 후렴 1 | Chorus A | 21–28 |
| 5 | 벌스 2 | Verse A + 사용별 변형 가능 | 29–36 |
| 6 | 후렴 2 | Chorus A | 37–44 |
| 7 | 브리지 | Bridge | 45–52 |
| 8 | 마지막 후렴 | Chorus A + 길이/clip 변형 | 53–68 |

마지막 후렴의 16마디는 단순 길이 연장으로 음을 자동 채우지 않는다. 8마디 material을 명시적으로 한 번 더 배치한 뒤 추가 연주를 넣는 사례다. 이 변경은 마지막 SectionUse의 override에 저장한다.

본문은 272 quarter notes, 136초다. 벌스 1의 두 번째 반복 끝의 필인을 1마디 insert로 바꾸면 그 이후 위치는 1마디씩 밀려 전체 69마디, 138초다. 이 규칙은 layout 좌표나 원의 크기와 무관해야 한다.
