# 기본 DAW 작업 흐름 확장

2026-09-08 사용자 요청: 드럼·신스 공통 스텝 에디터, 오디오 녹음·편집, 오토메이션, MIDI editing을 실제 제작에 사용할 수 있도록 완성한다. 기존 단일 다크 캔버스, 시간 궤도, 기존 음악/Undo/저장/MCP를 유지한다. 0.15 UI 개선은 먼저 검증·패키징·private push했다.

서브 에이전트 요청에 따라 독립적인 코드 조사를 실제 dispatch했으나 `agent thread limit reached`로 실패했다. 현재 총 1 slot이므로 사용자 요청을 작업 중단 사유로 삼지 않고 역할별로 순차 실행한다. 추가 slot이 제공되면 read-only 오디오/automation 조사부터 분담한다.

## 상태와 남은 완료 조건

| 작업 | 현재 구현 | 확장·완료 조건 |
|---|---|---|
| 스텝 | 0.16 구현·native 검증 완료 | 일반 Note/Lane을 그대로 편집하는 16-step page, 드럼/음정 row, 해상도, 세기/길이, 키보드, MCP, Undo/바운스 |
| MIDI | 0.17 선택/quantize/transpose/복제·format 0/1 노트 import·native 검증 완료, 기존 MIDI 녹음/테이크 | CC/페달/피치 벤드·tempo map import, 다중 노트 드래그·고급 연주 편집 |
| 오디오 녹음 | 입력 tap·ring buffer writer·CAF·테이크, 0.17 permission 대기/취소·문맥 guard | 장치 시작의 비동기화·실패 복구, 입력 상태, 실제 녹음→편집→bounce |
| 오디오 편집 | import, source trim/시작/길이/gain/tempo follow, 바운스 원본 복원 | 분할·복제·fade·무음/삭제·정확한 source 범위·Undo/저장 |
| 오토메이션 | 데이터/편집/재생 경로 없음 | stable target ID, 점/곡선, gain/pan 우선, tempo/local clock/repeat, 실제 render/export·MCP·Undo |
| 엔진 | prepared PCM, 일부 live synth/recording | 장치 lifecycle, transport/record sync, 이후 continuous render/PDC·plugin crash 격리 |

## 실행 순서

1. **0.16 스텝 편집**. `CirclrCore/StepEditing.swift`는 Note/Lane에 편집을 적용하고 별도 패턴 복제 저장소를 만들지 않는다. `CirclrApp/StepEditor.swift`를 기존 Inline MIDI 영역의 `궤도 / 스텝` 전환으로 제공한다. grid 1/4·1/8·1/16·1/32와 triplet, 16칸 page, 드럼 row/음정 row, 선택 note velocity/length는 공통 setter를 사용한다. 현재 time signature·section length를 보존하며 오프그리드 노트를 UI 진입만으로 양자화하지 않는다. 소리 내기/바운스는 기존 graph 그대로다.
2. MIDI 편집 명령을 Core에 통합하고 page 복제·비우기·quantize/transpose와 MIDI import를 추가한다. 경계 밖 클립·노트, repeated section 원본/변형, 다중 source lane을 검증한다.
3. 오디오 edit의 source-safe split/duplicate/fade와 녹음 lifecycle을 구현한다. 기본 경로부터 native 녹음 결과의 파일·파형·재생/bounce 동등성을 확인한다. 현재 Scarlett 장치 제약이 재현되면 OS 설정을 임의 변경하지 않고 다른 구현과 검증을 계속한다.
4. volume/pan 자동화부터 schema → validation/compiler → renderer → 같은 canvas editor → MCP 순서로 완성한다. 곡선이 실제 소리에 반영되는 impulse/constant/tone/tempo fixture를 사용한다. 신스 filter와 plugin parameter 자동화는 유효한 parameter descriptor와 DSP 경로가 연결된 뒤 노출한다.
5. 8방향 포트와 공통 import/Splice·실시간 엔진·계정 콘솔·아티스트 catalog는 기존 로드맵과 병행 후속 범위다. 사용자의 기본 DAW 요청이 추가됨에 따라 step/audio/automation을 포트 구현보다 우선한다.

## 0.16 acceptance

- 드럼·신스 양쪽에서 스텝 입력, 지우기, polyphony, gate/velocity, page 이동/복제, 기존 off-grid 음악 보존.
- keyboard arrows로 셀 선택, Tab으로 다른 입력 이동, Return toggle, Delete 지우기. 텍스트 입력에는 음악 핫키가 개입하지 않는다.
- GUI와 MCP는 동일한 Core 명령/원본·변형/transaction 사용. 유효하지 않은 pitch/resolution/step/gate/stale revision은 atomic 실패.
- 새로운 창·dock를 만들지 않는다. 작은 창에서 grid/hit/라벨 일치, 검색에서 step editor 진입, 음색·이펙트 전환 유지.
- 실제 앱 저장·재열기·Undo·바운스 및 CLI와 음악 동등성. 기존 v4를 그대로 여는 것만으로 hash가 바뀌지 않는다.
- 구현된 UI만 노출, README/CHANGELOG/QA/version/kit 갱신 후 private source push. 오디오·프로젝트·앱·인증정보는 Git 제외.

기본 기능 전체 완료는 이 문서의 단계별 동작이 실제 검증됐을 때만 선언한다. 모델이 실제로 청취하거나 하드웨어 녹음하지 않은 항목은 수치/fixture 검사와 구분한다.

## 0.17 실행 범위와 검증 계획

소유권: native Swift utility가 `MIDIEditing.swift`·`RecordingAuthorization.swift` Core 명령과 `MIDIImport.swift` AudioToolbox 읽기를 구현한다. 이후 App의 `MIDIWorkspace.swift`·`MIDIImportView.swift`·기존 세 편집기와 `AppStore`에 연결하고, 읽기 전용 코드 검토 → QA → lead 출고 판단 순으로 진행한다. 총 1 agent slot 제약을 유지한다.

- 선택: 기존 단일 선택을 보존하면서 ⇧클릭과 ⌘A, 선택 개수·퀀타이즈·이동·복제·삭제를 편집 영역에 직접 제공한다. ⌘D는 실제 키보드 포커스를 기준으로 MIDI 노트 또는 섹션을 복제한다. 텍스트 입력에 음악 명령이 끼어들지 않아야 한다.
- Core: 그룹 transpose/time 이동은 음정·시간 간격을 보존한다. bounds 밖은 atomic 실패한다. quantize는 quarter beat 기준 분할/강도, duplicate는 fresh IDs, 오디오와 비선택 MIDI는 보존한다. `edit_notes` MCP도 같은 Core를 사용한다.
- MIDI 파일: macOS AudioToolbox로 표준 format 0/1 beat 파일을 읽는다. 16 MiB/100,000 notes 제한, 채널 분리, 이름/quarter beat/velocity/gate를 검사한다. 같은 캔버스의 선택 UI에서 새 MIDI 서클로 추가하며 기존 내용을 유지하고 필요한 이번 use만 늘린다. 파일 tempo/meter/CC를 자동 적용하지 않음을 가져오기 전에 표시한다.
- 녹음: 권한 대기 token에 project/revision/address/track/lane을 묶는다. STOP·대상 변경·다음 요청 이후의 늦은 권한 응답은 시작할 수 없다. pending 취소 UI와 snapshot 상태를 제공한다. AVAudioEngine 실제 장치 시작/음원 녹음은 이 guard 검사와 별도로 남는다.
- QA: `.build/midi-quality` Swift 검사, MCP/kit Python 검사, `.build/midi-release` release. 전용 0.17 앱/`midi-QA.circlr`에서 가져오기 → 길이 연장 → 선택 → Q/⌘D → Undo → 저장/재열기, 일반 텍스트 Cmd+A, 작은 창/콘솔 배치와 v4 WAV 보존을 확인한다. `qa/verify-midi-native.py`는 정확한 bundle/version/path를 먼저 검사한다.
- Git: main에 source/docs/tests/agent kit만 독립 commit. native 검사 통과 후 로컬 app 교체·이전 app 보관·private push. 미디어·QA 산출물·환경 설정은 기존 제외 정책을 유지한다.

0.17 결과: Swift 129/Python 20 통과와 native 시나리오는 [검증 기록](../qa/0.17-review.md)에 있다. 다음 구현은 오디오 split/duplicate/fade의 source·clock 의미를 먼저 고정한 뒤 UI/MCP에 연결한다. 같은 원본 asset을 참조하고 trim/fade를 비파괴 데이터로 저장하며, 분할 전후 PCM 동등성과 변박·tempo-follow·repeat 경계를 검사한다. 작은 창의 궤도는 콘솔을 펼치면 음높이 행이 촘촘해지는 문제가 남아 있어 편집 확대·표시 음역 개선도 이어간다.
