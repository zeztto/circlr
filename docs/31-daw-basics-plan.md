# 기본 DAW 작업 흐름 확장

2026-09-08 사용자 요청: 드럼·신스 공통 스텝 에디터, 오디오 녹음·편집, 오토메이션, MIDI editing을 실제 제작에 사용할 수 있도록 완성한다. 기존 단일 다크 캔버스, 시간 궤도, 기존 음악/Undo/저장/MCP를 유지한다. 0.15 UI 개선은 먼저 검증·패키징·private push했다.

서브 에이전트 요청에 따라 독립적인 코드 조사를 실제 dispatch했으나 `agent thread limit reached`로 실패했다. 현재 총 1 slot이므로 사용자 요청을 작업 중단 사유로 삼지 않고 역할별로 순차 실행한다. 추가 slot이 제공되면 read-only 오디오/automation 조사부터 분담한다.

2026-09-09 build 56: 독립 검토 dispatch도 같은 thread limit으로 거절되어 순차 검토했다. 궤도·그리드·스냅을 음악 Undo/Redo와 분리하고 실제 MIDI·서클 이동·저장 복원을 검증했다. [보기 이력 계약](70-canvas-view-history.md) · [QA](../qa/view-history-review.md).

build 57: 접힌 그룹 내부 작업 이동을 scene에만 적용하고 음악 이력을 보존했다. 상위 복귀·명시적 그룹 Undo·MCP·저장된 편집 화면 재열기를 검증했다. [계약](71-navigation-group-reveal.md) · [QA](../qa/navigation-reveal-review.md).

build 58: 추가 에이전트 재시도가 실제 `agent thread limit reached`로 거절되어 순차 역할 전환을 유지했다. 오디오 대상 트랙 검색·번호 구분과 요청 충돌 보호를 구현하고 99트랙 native import/Undo/Redo·저장 재열기를 검증했다. [계약](72-library-track-search.md) · [QA](../qa/library-track-search-review.md).

build 59: 작업 검색에서 실제 섹션·서클로 직접 이동하고 섹션·트랙·종류 필터를 제공한다. 다중 역할 메뉴, 긴/동명 경로와 MIDI/오디오/이펙트 진입을 정리하고 편집 이력·외부 변경·저장 복원을 검증했다. [계약](73-direct-work-navigation.md) · [QA](../qa/direct-work-navigation-review.md).

build 60: 에이전트 한도 해제 요청 후 read-only 조사 dispatch를 재시도했으나 현재 세션에서 thread limit으로 거절됐다. 순차 작업으로 음색·AU 직접 검색, 설정 보존과 서클/전역 이펙트 선택을 구현하고 실제 앱의 취소·Undo/Redo·외부 변경 차단·재열기를 검증했다. [계약](74-sound-selection-search.md) · [QA](../qa/sound-selection-review.md).

## 상태와 남은 완료 조건

build 72: 피아노 롤 선택 보기/F, 작은 창의 눈금 가림과 넓은 선택 기준 노트 복귀를 구현했다. Swift496개·Python29개·native9상태 [QA](../qa/selection-reveal-review.md). 오디오 정밀 UI와 물리 입출력 출고 조건은 남아 있다.

build 71: MIDI·오토메이션 점·오디오 커서를 서클/원본별로 기억하고 현재 작업의 선택을 문서에서 복원한다. 삭제된 참조/파일 교체를 검증하며 트림 Undo/Redo의 원본 커서 시간도 유지한다. Swift496개·Python29개,30상태/34화면과 음악/자산 보존 통과. [계약](85-editor-selection-memory.md) · [QA](../qa/selection-memory-review.md). 다음은 선택 노트의 가시성·오디오 정밀 조작이며 물리 입출력 출고는 별도다.

build 70: 부모 AX 좌표와 스텝 객체 재사용으로 캔버스 직접 조작을 개선했다. 스크롤 경계 행·셀 입력/Undo·검색/페이지·노트·오토메이션 점·서클·포트·케이블을 native로 확인했다. AppKit14개·Swift491개·Python29개,14상태/21화면과 음악/자산 보존 통과. [계약](84-accessibility-geometry.md) · [QA](../qa/accessibility-geometry-review.md). 다음은 선택 상태 복귀와 오디오 정밀 입력 가시성이다.

build 69: MIDI 단일/다중 선택의2열 수치 편집과 상단 복제/삭제를 제공한다. 상대 길이·세기 변경은 MCP와 Core를 공유하고 차이 보존·원자적 거절·no-op을 지원한다. Swift491개·Python29개, native14상태/25화면 통과. [계약](83-midi-selection-inspector.md) · [QA](../qa/midi-inspector-review.md). 스텝 행 AX 프레임·선택 상태 복귀·오디오 보조 폼과 물리 입출력은 후속이다.

build 68: 스텝·피아노롤·궤도·오디오·오토메이션의 표시 위치를 서클/원본별로 기억하고 현재 작업을 문서에서 복원한다. 스크롤 왕복·앱 재실행·음악 Undo·길이 축소·비정상 음역을 검사했다. Swift485개·Python28개·native19상태/43화면 통과. [계약](82-editor-view-position.md) · [QA](../qa/editor-position-review.md). 선택 노트/점/분할 커서와 보조 폼의 가시성·물리 입출력이 후속이다. 에이전트 dispatch 재시도는 thread limit으로 거절됐다.

build 67: 현재 작업 페이지·원본 범위·연결 검색/선택·최근 전환·오토메이션 파라미터를 보기 정보로 저장하고 재열기에서 검증해 복원한다. 같은 문서 재열기 후 새 검색의 저장 누락을 수정했다. Swift477개·Python28개, 최종 native18상태·20화면과 전체 음악 비교 통과. [계약](81-saved-workspace.md) · [QA](../qa/saved-workspace-review.md). 세부 스크롤/표시 구간과 물리 입출력은 후속이다.

build 66: 연결 검색·포트·대상·재연결과 최근 전환을 세션 내에서 복원한다. 서클/원본별 분리·명시적 요청 우선·삭제된 케이블 해제·실제 적용/Undo·상단/본문 키보드 복귀를 확인했다. Swift469개·Python28개·native27상태·상태 복원34화면·최종 키보드7화면 통과. [계약](80-workspace-return.md) · [QA](../qa/workspace-return-review.md). 전체 작업 페이지의 재실행 복원과 물리 입출력은 후속이다.

build 65: 음악 설정 출처를 직접 버튼으로 바꾸고 길이·반복·리듬의 가시성을 개선했다. 키보드 전달 결함을 실제 앱에서 수정했으며 Swift463개·Python28개·23상태/21화면과 전체 음악 복원을 확인했다. [계약](79-music-settings-visibility.md) · [QA](../qa/music-settings-review.md). 작업 복귀의 전체 상태 계약과 물리 입출력은 후속이다.

build 64: 섹션 연결 대상 검색·분기·전환을 기존 연결 화면으로 통합했다. 실제 32개 섹션과 다른 곡에서 번호/이름/경로 검색, 키보드 선택, 전환 왕복·재연결·해제와 음악 보존을 검증했다. Swift463개·Python28개, native27상태/22화면·저장 복원 통과. [계약](78-section-connection-workspace.md) · [QA](../qa/section-connection-review.md). 음악 설정 가시성은 build65에서 개선했으며 연결/전환/설정 작업 복귀의 전체 상태 보존은 후속이다.

build 63: 곡·악장의 편곡안을 같은 캔버스에서 직접 검색한다. 서클/설정/단축키/명령 진입, 순번·동명·빈 편곡, 음악 선택과 화면 보존, 오래된 요청 거절을 구현했다. Swift457개·Python28개, 실제 26상태/24화면·저장 복원을 검증했다. [계약](77-arrangement-search.md) · [QA](../qa/arrangement-search-review.md). 에이전트 한도 해제 안내 뒤 실제 dispatch를 재시도했으나 런타임 thread limit이 유지됐다. 다음 섹션 연결은 build64에서 통합했으며 음악 설정의 스크롤 깊이는 후속 범위다.

build 62: read-only `circlr_sounds`로 실제 음색·변형·AU 목록을 조회하고 기존 apply로 주소를 병합하는 경로를 연결했다. Swift 451개·Python 28개, 실제 stdio/최소화/재실행 조회·GUI 대조와 적용/Undo·patch 보존을 검증했다. [계약](76-agent-sound-catalog.md) · [QA](../qa/agent-sounds-review.md). 곡·악장의 편곡안 검색은 build63에서 구현·검증했다.

build 61: 실제 Sound Bank 이름·계열·변형·드럼 킷 검색과 optional bankLSB 저장/로드를 연결했다. 키보드 선택·no-op·Undo/Redo·충돌 거절·비활성 신스 보존·재열기와 작은 창 안내 표시를 확인했다. Swift 445개·Python 26개, native 16상태/18화면 통과. 독립 review dispatch를 다시 시도했으나 thread limit으로 거절돼 순차 검토했다. [계약](75-sound-bank-program-search.md) · [QA](../qa/sound-bank-search-review.md). 읽기 전용 MCP 음색 catalog와 편곡안 검색은 build62/63에서 진행했으며 물리 I/O gate는 유지한다.

| 작업 | 현재 구현 | 확장·완료 조건 |
|---|---|---|
| 스텝 | 0.16 구현·native 검증 완료 | 일반 Note/Lane을 그대로 편집하는 16-step page, 드럼/음정 row, 해상도, 세기/길이, 키보드, MCP, Undo/바운스 |
| MIDI | 0.17 선택/quantize/transpose/복제·format 0/1 노트 import, 기존 MIDI 녹음/테이크. build 50 다중 노트 드래그/길이·Undo ([QA](../qa/midi-group-drag-review.md)), build 51 음높이/시작 박 조건 선택·반전·해제 ([QA](../qa/midi-selection-tools-review.md)) | CC/페달/피치 벤드·tempo map import·고급 연주 편집 |
| 오디오 녹음 | 0.20 소스·검증 앱: 비동기 시작/종료·취소·실패 복구·입력 상태·MCP·atomic take, 오프라인 왕복·native 재열기/대기 버튼 검사 통과 | 허용된 실제 입력·녹음 중 UI→편집→bounce·Undo·재열기와 출고 |
| 파일 가져오기 | build 52 다중 선택·폴더별 batch·원자적 실패/Undo, build 53 폴더 관리·오류 복구, build 54 섹션 검색·시작 박/트랙, build 55 위치 표시 통일, build 58 대상 트랙 검색·번호 구분·실제 import/Undo ([QA](../qa/library-track-search-review.md)) | 중첩 폴더 catalog dedup·실제 file promise·직접 배치 gesture |
| 오디오 편집 | 0.18 split/duplicate/fade/mute/delete·MCP·native PCM·Undo/저장 검증 | 전체 source로 trim 재확장, crossfade·time warp·comping·window 처리 cache |
| 오토메이션 | 0.19 gain/pan·선형/유지·궤도/선형 편집·MCP·native WAV/Undo/저장 검증 | synth filter·plugin parameter·MIDI CC·전역 bus, 실시간 write/touch/latch |
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

## 0.18 실행 계약

역할: development-lead → native Swift utility(Core/Audio) → native UI utility → read-only review/security → QA → lead release. 독립 Audio timing 조사 dispatch는 다시 실행 한도로 실패해 delegation은 none이다. main의 독립 기능 commit이며 이전 앱·곡·오디오를 보존하고 검증 후 private push한다.

- `AudioEditing.swift`와 `Model.swift`: 원본 asset을 참조하는 split/duplicate/fade. 분할은 48 kHz 출력 sample 경계로 맞추고 source window·기존 fade를 보존한다. 원래 범위를 렌더한 뒤 필요한 구간을 사용해 resample/stretch의 접합부 재시작을 막는다. 이후 fade는 원본 초 단위이며 분할 이전의 envelope도 유지한다.
- `ClipAudioRenderer.swift`·기존 두 renderer: 기존 필드가 없는 프로젝트의 DSP 결과 유지. loop period·local tempo·명시 길이·section tail에 따라 원래 처리 구간을 복원한 뒤 slice한다. 실제 PCM 비교로 확인하며 단순 source offset 일치만으로 성공 판단하지 않는다.
- `SectionGraph`·`BounceEditing`: 분할·복제한 서클은 원래 gain/mute/context/repeat과 ordinary/sidechain 출력을 복사한다. 같은 clip의 다른 node 참조는 분리한다. 바운스의 분할 파생본은 원본 복원 시 함께 연결 해제하고 archive로 남긴다.
- `AudioWorkspace.swift`·`InlineCircleEditor`·`OrbitAudioEditor`: 같은 캔버스의 커서·분할/복제/음소거/삭제와 직접 fade 필드. 메뉴 속에 기본 편집을 숨기지 않는다. 원본 파형·선택 구간·커서·fade 표시를 구분한다. 오디오 선택 상태에서 ⌘T/⌘D를 연속 적용하며 텍스트 입력·탐색 UI가 활성화되면 음악 명령을 차단한다.
- `AgentProtocol`·`mcp/server.py`: 같은 Core의 `edit_audio` 계약, strict fields·revision·atomic batch. 기존 set_clip과 UI trim도 source bounds와 새 envelope 유효성을 검사한다.
- 검사: `.build/audio-edit-quality`의 Core/PCM tests → 전체 offline Swift, MCP/kit Python → `.build/audio-edit-release`. 전용 0.18 QA 사본에서 split→fade→duplicate→Undo→save/reopen→bounce/export 및 작은 창/콘솔 UI 검증. source/trim/local tempo/repeat/fan-out/bounce 복원·정확한 PCM과 fade 감쇠를 검사한다. Scarlett 하드웨어 녹음은 이 검증과 별도이며 automation 단계도 이어서 남는다.

0.18 결과와 실패 후 수정 사항은 [QA 기록](../qa/0.18-review.md)에 있다. 다음은 gain/pan automation의 target·시간·값 계약과 Core/PCM 검증을 먼저 작성하고, 같은 캔버스에 점 편집을 연결한다. 장치 lifecycle은 독립 작업으로 유지한다. 사용자가 한도 해제를 알려준 후 읽기 전용 코드 검토를 다시 dispatch했지만 도구는 여전히 `agent thread limit reached`를 반환했다. 성공하지 않은 delegation을 검토 증거로 계산하지 않는다.

## 0.19 결과와 다음 실행

선택 서클의 gain/pan을 같은 캔버스에서 직접 편집한다. [시간·신호·UI 계약](33-automation-plan.md)과 [148 Swift/22 Python 및 native 검증](../qa/0.19-review.md)을 연결했다. 개별 tempo의 처리 서클도 편집 좌표와 DSP가 같은 로컬 시간을 사용한다. GUI 점 드래그는 한 번의 Undo, 입력 필드는 음악 단축키와 분리된다.

다음 독립 범위는 장치 lifecycle이다. `AudioRecorder.start`의 동기 장치 연결을 UI에서 분리하고 요청 세대·취소·중복 시작·종료 정리를 정의한다. 입력 tap 이후 실제 오디오 파일과 시작/끝 시간을 검사해야 한다. 기존 Scarlett 출력 준비 timeout과 혼동하지 않고, OS 기본 장치나 권한 설정을 변경하지 않는다. 8방향 포트는 별도 Core endpoint migration → hit/keyboard → MCP/Undo 순서로 진행한다.

## 0.20 진행 상태

[녹음 lifecycle 계약](34-recording-lifecycle.md)을 구현했다. Swift 160개와 별도의 CAF→테이크→portable 저장→바운스 통합 검사 1개, Python 23개가 통과했다. 실제 앱의 잘못된 녹음 요청 거부·문서 재열기·대기 상태 버튼/단축키 안내를 확인하고 이동 메뉴의 대비를 개선했다. 실제 입력 허용을 기다리며 [남은 native acceptance](../qa/0.20-review.md)를 유지한다. 현재 사용 앱은 0.19이며, 0.20 패키지 교체·로컬 키트 갱신은 아직 수행하지 않았다.
