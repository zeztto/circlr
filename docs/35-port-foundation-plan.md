# 8방향 포트 · 실행 계약

시작 기준은 `040bb2b` (0.19)다. 녹음 0.20의 native 권한 대기와 독립적으로 `codex/eight-direction-ports` worktree에서 진행한다. 녹음 branch의 변경·QA 앱·open job을 건드리지 않는다. 최종 통합 시 녹음 변경을 보존하고 충돌을 검토한다.

역할은 development-lead/planner → native Swift Core utility → read-only review → QA → App/UI utility다. 실제 도구가 단일 agent 한도를 반환하여 delegation은 none이다. 사용자가 요구한 전체 포트 기능은 [8방향 계약](22-eight-direction-ports.md)을 따르며 아래 각 단계의 완료를 전체 완료로 취급하지 않는다.

검증된 단계는 독립 private branch의 source checkpoint로 commit/push할 수 있다. 이는 main 통합이나 앱 출고가 아니며, E의 native·배포 gate를 생략하지 않는다.

## A · 신호와 배치의 공통 기반

소유 파일: 신규 `Sources/CirclrCore/CirclePort.swift`, `CirclePortLayout.swift`, `CirclePortGeometry.swift`; 기존 `Model.swift`, `ProjectStore.swift`, `HierarchyScene.swift`; 신규 Core/Audio 검사와 이 문서.

- 현재 실제로 실행되는 MIDI/audio/main/sidechain/송폼 포트에 stable ID·IN/OUT·수용 정책을 부여한다. Audio Unit이 제공하지 않는 별도 bus나 그룹 alias를 만들지 않는다. 이후 독립 다중 bus 구현은 B에서 이어간다.
- logical connection은 원래 from/to 주소·edge ID를 가진다. 같은 ID를 공유하는 섹션의 다른 use·편곡안 배치는 별개다. 그룹 접기는 화면 endpoint만 투영하고 원래 connection을 유지한다.
- 포트 배치는 project의 선택적 `portLayout`에 저장한다. 기존 필드가 없으면 E OUT/W IN이며, 음악 데이터나 실행 계획을 migration으로 다시 쓰지 않는다. 배치 transaction은 projectID/musicRevision/layoutRevision을 모두 확인하고 layoutRevision만 증가시킨다. no-op는 기록을 늘리지 않는다.
- layout만 되돌리는 Core 명령은 현재 음악을 덮어쓰지 않고 새 layoutRevision으로 복원한다. 앱 Undo 기록이 음악/배치 명령을 구분하도록 C에서 연결한다.
- 배치의 0…7 octant와 유한 geometry, 중복·개수·길이 제한을 저장 시 검사한다. 삭제된 edge의 이전 배치는 Undo를 위해 유지할 수 있으나 새 배치 요청은 존재하는 logical edge만 받는다.
- geometry는 화면 좌표에서 OUT/IN과 sidechain을 별도 반경에 놓고, 도형과 hit가 같은 계산을 사용한다. 같은 포트의 여러 cable은 같은 logical output을 유지한다.

검사: legacy JSON·기본값, 모든 octant geometry/hit, IN↔OUT 역방향 정규화·신호 불일치·sidechain 역할, 다른 use 배치 분리·stale/atomic/no-op·배치 Undo와 음악 보존, 그룹 투영·저장/재열기, 방향 변경 전후 renderer의 PCM 동일성. `.build/ports-quality`의 전체 offline 검사와 독립 release build를 사용한다. 실제 UI 검사는 C 이후에만 주장한다.

## 후속 단계와 완성 조건

B. 독립 2 IN/2 OUT routing과 compiler/renderer의 port별 실제 buffer. fan-in/fan-out·sidechain·MIDI 합류·바운스 복원과 PCM 분리를 확인한다.

C. `AlbumCanvas`·`AlbumWorkspace`·scene·AppStore에 8방향 IN/OUT hit·새 연결·재연결·배치 이동·화살표·키보드 목록을 연결한다. 한 gesture 한 Undo, 취소·잘못된 대상 무변경, 시간 손잡이 우선순위 고정, 작은 창과 축소 상태에서 보이지 않는 hit 제거를 확인한다.

D. MCP의 포트 조회·명시적 연결·layout revision 명령, 그룹의 노출 binding을 구현한다. 컴퓨터 화면을 조작하지 않고 같은 명령으로 편집할 수 있어야 한다.

E. native 8방향 조작·VoiceOver·저장 복원·기존 v4 PCM을 검증한 후 0.20과 통합한다. README/CHANGELOG/version/kit·패키지/서명/UUID를 갱신하고 기존 승인 범위의 private source만 commit/push한다. 현재 단계에서는 새 사용 앱을 배포하지 않는다.

A 결과: 신규 Core 10/Audio 1개를 포함한 전체 오프라인 Swift 159개와 release build가 통과했다. 중복 배치의 scene crash를 수정하고, 13개 분기·모든 방향·sidechain 포함 PCM 불변을 확인했다. [QA 근거와 남은 범위](../qa/ports-foundation-review.md).

## B 실행 계약 · 독립 스테레오 bus

사용자의 한도 해제 안내 후 read-only compiler/renderer 검토를 재요청했으나 실제 `spawn_agent`가 다시 `agent thread limit reached`를 반환했다. 동시 agent가 실행된 것으로 보고하지 않으며 이번 slice는 native Swift utility가 단독 수행한다.

- `MusicCircleContent.router(AudioRouter)`에 실제 스테레오 2 IN / 2 OUT과 최대 네 개의 gain route를 정의한다. 기본값은 IN 1→OUT 1, IN 2→OUT 2다. 좌우 채널은 하나의 스테레오 bus 안에서 보존한다.
- `MusicConnection`의 선택적 `fromPortID`/`toPortID`를 compiler에서 검증한다. 기존 생략된 단일 main/sidechain 연결은 그대로 해석한다. 다중 bus의 node-only 연결은 임의 bus를 고르지 않고 거절한다.
- renderer는 `(nodeID, portID)`별 PCM과 소비자 수를 사용한다. 같은 입력의 fan-in만 합산하며 출력 간 PCM은 공유 합산하지 않는다. node gain/automation/mute는 각 출력에 적용한다. 기존 node observer의 router 값은 시각화를 위한 합계이며 실제 routing buffer와 분리한다.
- Core 편집과 scene/catalog가 명시적 port ID를 보존한다. 기존 효과 삽입은 다중 출력에서 명시적 선택 없이 신호를 합치지 않아야 한다. 새 router 생성/편집 UI와 MCP 공개는 C/D에서 연결한다.
- 검사: 다른 두 stereo 입력의 분리, matrix 교차/분기/합류, sidechain, MIDI 합류, bus 소비자 수와 메모리 상한, mute/gain/automation, 잘못된 port/gain/순환의 atomic 거절, legacy JSON, 프로젝트 저장/재열기, 두 track 바운스/복원의 명시적 포트 보존. 기존 전체 offline 검사와 release build를 재실행한다.
- 전체 8방향 UI·group binding·Audio Unit 다중 bus 호스팅은 이 slice의 완료 판정에 포함시키지 않는다. B 완료 후에도 C/D/E를 이어간다.

B 결과: 신규 Core 5개/Audio 8개를 포함한 전체 offline Swift 172개와 warning 없는 release build를 통과했다. 2×2 matrix, port별 PCM·fan-in/fan-out·sidechain·MIDI 합류, 두 트랙 바운스/embedded 저장/원본 복원을 확인했다. [B 검증과 native 후속 범위](../qa/ports-bus-review.md). 다음 C에서는 router의 생성·matrix/port 선택과 연결선별 bus envelope도 UI 계약에 포함한다.

## C 실행 순서 · 직접 연결 편집과 gesture

C1은 같은 캔버스의 연결 편집기에 선택 서클의 IN/OUT·대상·각 끝점의 8방향·기존 연결 목록을 모은다. 이름 검색과 키보드 접근으로 우클릭 하위 메뉴를 줄인다. explicit Core 연결 명령과 layout 전용 Undo를 먼저 연결하고 케이블/재생 모션이 동일한 곡선을 사용하게 한다. router 생성·2×2 matrix 조절도 이 편집 경로에서 제공한다.

C2는 이 명령에 8방향 드래그·둘레 drop의 포트 선택·케이블 선택·끝점 재연결·위치 이동 gesture를 붙인다. hidden hit 제거, 시간 손잡이 우선순위, Esc/무효/삭제/stale 대상의 원상 유지, 한 gesture 한 Undo를 검증한다. C3에서 native 작은 창·키보드/VoiceOver·저장 복원·포트별 envelope를 검사한다. C1만 통과한 경우 C 전체 완료로 보고하지 않는다.

C1 소유: 신규 Core `CircleConnectionEditing.swift`와 검사, App의 연결 편집기·AppStore Undo entry·AlbumCanvas 곡선·PlaybackVisualization. 전용 포트 QA bundle은 녹음 QA와 별도 저장/agent socket을 사용하며 실행 중인 두 기존 앱을 건드리지 않는다. native 검증 가능한 상태가 되기 전에는 사용 앱에 배포하지 않는다.

C1 결과: 전체 offline Swift 178개, Python 22개와 release build를 통과했다. native 직접 편집기에서 각 끝의 8방향 선택·음악 불변·배치 Undo/Redo·저장/재열기, 라우터 생성·명시적 IN/OUT 연결과 matrix 숫자 입력의 단일 적용을 확인했다. 숫자 입력이 되돌아가는 실패를 발견해 수정했으며 실패 증거도 보존한다. [C1 검증](../qa/ports-ui-review.md). 독립 리뷰 agent 호출은 다시 실제 슬롯 제한으로 거절됐으므로 같은 agent의 역할 전환 검토다.

C2 시작 시 현재 새 연결 gesture의 빌드된 기반을 재사용한다. 케이블 선택·끝점 드래그 재연결·명시적 배치 이동, router의 캔버스 IN 1/2·OUT 1/2 식별과 방향에 맞는 임시 연결선, native 드래그/취소/stale 검증을 이어간다. C3의 작은 창·시간 손잡이 충돌·VoiceOver·bus별 envelope, D/E의 외부 명령·binding·녹음 통합과 사용 앱 출고 gate는 열린 상태다.

## C2 작업 계약

- 역할: development-lead/UX 계약 → native Swift utility 구현 → 동일 agent read-only 검토 → QA. 추가 agent slot이 직전 호출에서 거절되어 delegation은 none이다.
- 케이블 클릭은 음악 선택을 바꾸지 않고 그 선을 강조한다. 같은 캔버스의 작은 도구막대에 실제 포트 이름, 재연결/위치 이동 모드와 해제를 제공한다. 두 끝점은 모드가 정해진 뒤 드래그하며 일반 포트의 새 분기 추가와 구분한다. 시간 손잡이는 기존 우선순위를 유지한다.
- 재연결 preview는 원래 선과 함께 표시한다. 유효한 다른 포트에 놓을 때만 ID/gain을 보존해 적용한다. 위치 이동은 원래 서클 둘레의 octant만 바꾸며 graph/music revision은 유지한다. Esc, 잘못된 대상, project/music/layout 변경은 무변경이다. 한 drag는 하나의 Undo다.
- 소유 경로: 신규 Core `CircleCableGesture.swift`와 geometry의 cable hit, 관련 Core 검사. App `CanvasPorts.swift`, 신규 `CanvasCableEditing.swift`, `AlbumCanvas.swift`, `CanvasCommands.swift`, 필요 시 읽기 전용 `PlaybackVisualization.swift` 진단. README/CHANGELOG와 C2 QA 기록을 갱신한다. API schema·인증·외부 plugin·배포 앱은 이번 계약의 변경 대상이 아니다.
- 검증: Core의 양 끝 재연결/배치·stale/실패 atomic·curve hit 검사, `swift test --scratch-path .build/ports-quality --skip testArrangementRenderExportAndPlayback`, release build. 전용 port QA fixture에서 cable 선택·mode 전환·실제 drag·Esc·Undo·저장/재열기를 수행한다. 숨겨진 port hit와 router 번호·preview 방향도 확인한다.
- Git: 기존 `codex/eight-direction-ports`의 `f7f9e50`부터 독립 source checkpoint를 만든다. C2에서 발견한 미완성 native 시나리오는 명시하고 main 통합·사용 앱 교체는 E gate에서 진행한다.

C2 결과: 케이블 선택·OUT/IN 재연결·위치-only drag·Delete를 구현했고, 실제 OUT/IN 각각 8방향 이동·저장값·음악 불변, IN 시작 분기와 단일 Undo, 오류/메뉴 Esc, 같은 파일 재열기 뒤 늦은 포트 선택의 거절을 검증했다. 중앙 drop·도구막대 가림·중간 확대의 bus 식별·주변 연결 숨김을 수정했다. 전체 Swift 182개/Python 22개와 최종 release build가 통과했다. [C2 QA와 빌드별 근거](../qa/ports-cable-review.md).

다음 소유는 C3의 UI/접근성·시각화다. 작은 창·고밀도 궤도의 겹침과 포트 표시, 시간 손잡이 충돌, 개별 케이블/포트 키보드 선택과 VoiceOver, bus별 envelope를 우선한다. MIDI/sidechain/송폼·그룹의 모든 pointer 조합 및 마우스를 누른 채 삭제/수정하는 확대 회귀를 함께 마친다. D/E를 완료하기 전에는 전체 8방향 기능 완료나 사용 앱 출고로 보고하지 않는다.

## C3a 작업 계약 · 실제 출력별 시각화

- 역할: development-lead 계약 → native Swift/audio utility 구현 → read-only 검토 → QA. 사용자 안내 후 키보드 접근성의 독립 검토를 다시 요청했지만 실제 도구가 `agent thread limit reached`를 반환했다. 이번 실행의 delegation은 none이며 병렬 검토가 수행되었다고 보고하지 않는다.
- 소유 파일: Audio `PlaybackAnalysis.swift`, `SectionGraphRenderer.swift`, `Renderer.swift`; App `PlaybackVisualization.swift`; Audio의 관련 검사와 신규 `PortPlaybackAnalysisTests.swift`; README/CHANGELOG와 QA 기록. 키보드·VoiceOver는 후속 C3b로 남긴다.
- 각 OUT의 node gain·automation 적용 후 PCM을 60 Hz envelope로 요약한다. router의 독립 출력을 합쳐 케이블 신호로 사용하지 않는다. 노드의 밝기는 활성 출력별 peak의 최댓값으로 표현해 역상 출력 간 상쇄를 피한다. 원본 PCM은 시각화 데이터에 보관하지 않는다.
- 활성 경로는 음소거되지 않고 gain이 양수인 트랙 출력에서 입력 포트별로 역추적한다. router는 실제 matrix의 해당 OUT→IN 경로만 통과한다. 신호가 다른 bus·gain 0 route·음소거 분기에는 전파되지 않아야 한다. MIDI는 실제 예약된 note velocity와 길이를 표시한다. 이 값은 섹션 내부 신호이며 master 이후의 청감 레벨을 대신하지 않는다.
- 케이블은 화면에 투영된 그룹 주소 대신 원래 logical connection ID로 조회한다. 출발 OUT envelope에 해당 edge gain과 section use gain을 각각 한 번 적용한다. 여러 occurrence가 겹치면 기존 peak-max 표시 정책을 유지한다. 실제 연주의 PCM·프로젝트 schema·MCP 쓰기 계약은 바꾸지 않는다.
- 메모리 사전 검사에 occurrence별 node/port envelope와 전체 signal envelope를 포함한다. 시각화 off에서는 데이터나 추가 callback을 생성하지 않는다.
- 검증: 서로 다른 stereo 출력의 envelope, 역상 출력, 한 bus만 연결/활성인 matrix, mute·gain 0, fan-out gain·sidechain·MIDI, 관측 on/off의 정확한 PCM 일치와 metadata 크기 추정. 전체 offline Swift 검사와 release build를 통과한 뒤 전용 QA 앱만 교체해 실제 화면 연결 경로를 확인한다. 하드웨어 출력·화면 모션은 실제 확인 범위와 offline 근거를 분리한다.
- Git: `f3b2ba2`부터 같은 private 개발 branch에 검증된 source checkpoint를 남긴다. C3 전체 완료·녹음 branch 통합·사용 앱 출고는 별도 gate다.

C3a 결과: 전체 Swift 190개와 release build를 통과했다. 전용 native 앱의 출력별 케이블을 10회 확인했고 H.264/AAC 30.755초·919프레임·누락 0의 실제 캔버스 녹화에서 두 출력의 구분을 확인했다. 가려진 일반 창의 애니메이션 중단과 녹화 중 계속 진행하는 기존 정책을 구분한다. 검증 프로젝트 생성기와 helper의 정확한 허용 경로를 추가했다. [C3a QA](../qa/ports-playback-review.md). 다음은 C3b의 개별 케이블/포트 키보드·VoiceOver와 작은 화면 밀집 배치다.

## C3b 작업 계약 · 키보드와 접근성

- development-lead → UX 계약 → native Swift utility → read-only 검토 → QA. 직전 spawn이 실제 슬롯 한도로 거절되어 delegation은 none이다. C3a의 `b477aaf`에서 같은 개발 branch를 이어간다.
- 캔버스의 K/Shift K는 선택 서클의 케이블, P/Shift P는 논리 포트를 순회한다. 선택 케이블에서 Tab은 OUT/IN 전환, 좌우는 선택한 끝점의 8방향 위치 이동, 상하는 이전/다음 케이블이다. Return/L은 선택 케이블 또는 포트가 미리 지정된 연결 편집기를 연다. Esc는 선택을 해제하고 Delete는 선택 케이블만 해제한다. 키 반복으로 Undo를 쌓지 않으며 위치 변경은 음악 불변·한 키 한 Undo다.
- 마우스·키보드가 같은 선택 상태와 도구막대를 사용한다. 좁은 화면에서 조작 안내를 줄바꿈하고 도구막대를 workspace 안에 둔다. 포트 선택은 별도 창 없이 표시한다. 명령 검색에도 연결/포트 탐색을 노출한다. 텍스트·MIDI/오디오 편집기 내부 입력을 캔버스 핫키로 가로채지 않는다.
- 화면에 드러난 실제 포트는 octant 중복 없이 하나의 접근성 항목으로, 케이블은 실제 IN/OUT 이름을 가진 항목으로 제공한다. 접근성 객체를 redraw마다 교체하지 않는다. 가려진 항목을 화면 hit/접근성 대상으로 남기지 않으며 선택 뒤 편집·위치·해제 버튼을 사용할 수 있게 한다. 접힌 그룹은 실제 노출 port binding을 만들지 않는다.
- 소유 경로: App `AlbumCanvas.swift`, `CanvasCableEditing.swift`, `CanvasPorts.swift`, 신규 `CanvasConnectionNavigation.swift`·`PortKeyboardControls.swift`, `PortConnectionsEditor.swift`, `AppStore.swift`, `CanvasCommands.swift`, 필요한 `AlbumWorkspace.swift`·`InlineCircleEditor.swift`. Core 음악 schema·renderer·MCP 쓰기 계약을 바꾸지 않는다. README/CHANGELOG와 C3b QA 기록을 갱신한다.
- 검증: 기존 전체 offline Swift 및 release build. 별도 port QA fixture에서 키보드 순회·prefill·IN/OUT 위치·한 Undo·Esc·Delete/Undo·저장/같은 파일 재열기의 상태를 MCP readout과 대조한다. AX의 항목 이름·선택 상태·중복/가림 및 작은 창에서 읽을 수 있는 조작을 확인한다. 실제 VoiceOver 발화 검증 여부는 AX 검증과 구분해 기록한다. 소스 checkpoint만 private push하며 main/사용 앱은 교체하지 않는다.

C3b 결과: 케이블·논리 포트 순환, 선택 대상 prefill, 편집기 내부 Tab/방향키/Return 재연결, 포트 Delete 보호, 케이블 Delete/Undo, 양 끝 16회 방향 이동의 음악 불변과 같은 파일 재열기 상태 초기화를 실제 QA 앱에서 확인했다. 확대 중 초기 검색 포커스가 빠지는 결함은 컨트롤 준비와 카메라 완료를 연결해 수정했다. canvas 1080×673에서도 편집 적용 버튼과 스크롤을 확인했다. [C3b QA와 빌드별 근거](../qa/ports-keyboard-review.md).

다음 실행은 C3의 남은 밀집 배치/시간 손잡이/신호 종류/그룹 조합과 실제 VoiceOver 발화, D의 typed-port MCP·배치 revision 계약 및 group binding, E의 녹음 branch 통합과 앱 출고 회귀다. C3b 소스 checkpoint를 C3/D/E 전체 완료로 취급하지 않는다. 현재 런타임의 추가 spawn도 한도 오류로 거절됐으므로 이번 리뷰는 같은 실행자의 역할 전환이며 독립 서브 에이전트 검토가 아니다.

## C3c 실행 계약 · 포트 밀도와 직접 선택

- 기준 `1d3e0ae`, 동일 private worktree. development-lead → UX → native Swift utility → read-only review → QA. 독립 검토 spawn은 실제 `agent thread limit reached`로 거절되어 delegation none이다.
- 선택 서클은 논리 포트마다 대표 지점과 기존 케이블 위치를 표시한다. 포트를 클릭하거나 P로 선택하면 그 포트만 8방향을 펼친다. 실제 8방향 연결·배치 저장과 MIDI/audio/sidechain/flow 의미는 유지한다. 짧은 클릭은 선택이며 음악을 바꾸지 않는다.
- 새 연결/재연결 중에는 같은 신호·반대 방향·같은 graph의 후보를 표시한다. 가까운 대상 서클에서 상세 방향을 펼치고 멀리 있는 모든 포트의 반복 표시는 만들지 않는다. 선택 끝점의 배치 모드는 원래 포트의 8방향을 제공한다. 무효 드롭은 기존 연결을 보존한다.
- 이름은 논리 포트마다 한 번, 선택 끝점 우선으로 겹치지 않는 위치에 표시한다. 화면·편집기·도구막대·서클 이름·실제 포트 점·시간 손잡이의 영역을 피한다. 실제로 보이지 않는 포트는 hit/AX에 노출하지 않는다. 같은 draw/hit geometry를 유지한다.
- 소유: Core 신규 `CirclePortPresentation.swift`와 관련 XCTest(표시·라벨 배치만), App `CanvasPorts.swift`, 신규 `CanvasPortLabels.swift`, `AlbumCanvas.swift`, `CanvasCableEditing.swift`, 필요 시 `CanvasConnectionNavigation.swift`. 프로젝트 음악 schema·renderer·MCP 쓰기 명령·사용 앱은 변경하지 않는다. README/CHANGELOG와 QA 문서를 갱신한다.
- 검사: 표시 상태별 4→11개 방향, 기존 비기본 연결 위치 보존, 근접 후보·작은 확대·시간 손잡이/라벨 충돌과 draw/hit 일치. 전체 offline Swift와 release build. 전용 QA 앱에서 클릭/P 선택·방향 드래그·음악 불변·Undo·키보드 prefill/포커스·저장 복원과 실제 전후 화면을 확인한다. native로 확인하지 못한 모든 종류/그룹/밀집 조합은 남은 범위로 명시한다.

C3c 결과: 라우터의 실제 기본 handle 4개·한 포트 선택 11개와 음악 불변을 확인했다. 대각선 IN에서 OUT으로 연결, 도구막대에 가려진 대상 연결, 궤도 시작 0.5 beat 이동과 각각의 Undo를 실제 앱에서 검증했다. 라벨의 중복/교차/viewport와 시간 손잡이 거리, 같은 파일 재열기 복원을 저장 증거와 대조했다. 전체 Swift 194개와 release build 통과. [C3c QA](../qa/ports-density-review.md). 다음은 D의 백그라운드 포트 MCP 계약 구현을 우선하고 C3의 미검증 VoiceOver·전체 조합 검증을 병행한다. 이 상태는 C3/D/E 전체 완료나 사용 앱 출고가 아니다.

## D1 실행 계약 · 명시적 포트 MCP

- 기준 `1337ce5`, 동일 private 개발 branch. development-lead → Swift utility → Python backend → read-only security/code review → QA. 사용자 한도 해제 안내 후 독립 계약 검토를 요청했지만 실제 spawn은 `agent thread limit reached`로 거절됐다. delegation none이며 역할을 순차 전환한다.
- `ports(node)`는 실제 논리 주소의 descriptor·endpoint·관련 케이블·배치·편집 가능 여부와 project/music/layout revision을 반환한다. 접힌 화면의 가상 주소나 octant를 새 bus로 해석하지 않는다. 현재 Core의 Codable 주소와 endpoint를 그대로 반환해 재사용한다.
- `connect_ports`, `reconnect_ports`, `disconnect_ports`, `move_ports`는 projectID/expectedRevision/expectedLayoutRevision을 모두 요구한다. 연결 두 끝과 방향을 명시하고 GUI의 `CircleConnectionEditing`·`CirclePortLayoutEditing`을 호출한다. 후보 문서에서 실패하면 전체 무변경, 실제 변경만 한 Undo다. 배치만 변경하면 음악 revision·PCM을 보존한다. 기존 undo에도 선택적 layout revision 검사를 추가한다.
- 소유: Core `AgentProtocol.swift`, 신규 `AgentPortEditing.swift` 및 XCTest; App `AgentWorkspace.swift`; Python `mcp/server.py`·`test_server.py`; README/CHANGELOG, `docs/17-agent-interface.md`, `mcp/README.md`, 신규 QA 기록/검증 스크립트. 소켓 인증·기존 도구·음악 schema·사용 앱은 유지한다. group binding은 D2다.
- 검증: Swift 전체 offline 검사(`swift test --scratch-path .build/ports-quality --skip testArrangementRenderExportAndPlayback`), release build(`swift build -c release --scratch-path .build/ports-release`), Python MCP/kit 검사. 별도 com.circlr.portsqa에서 정확한 QA fixture/socket만 사용해 조회·연결·재연결·해제·배치/no-op/stale/Undo·save/open을 대조한다. 앱 최소화 중 편집과 카메라 보존을 확인한다. 입력 오류와 read-only 차단도 검사한다. 마이크/사용자 프로젝트는 작업 대상이 아니다.
- 기존 승인 범위의 source checkpoint만 commit/private push한다. D 전체·녹음 branch 통합·main release 완료로 취급하지 않는다.

D1 결과: 포트 도구 5개와 음악/배치 revision 검사를 구현했다. 전체 Swift 202개·Python 24개, release build를 통과했다. 전용 QA 앱을 최소화한 상태의 연결·재연결·해제·원자적 배치/no-op/stale 거절·한 Undo·저장/재열기와 실제 GUI의 ⌘Z 연동을 검증했다. [D1 QA와 실행 근거](../qa/ports-mcp-review.md). 다음 D2는 그룹 경계의 노출 binding, 이어서 C3 미검증 조합과 E 통합이다. 이번 추가 spawn도 실제 슬롯 한도로 거절됐으며 역할 전환 검토를 독립 agent 리뷰로 보고하지 않는다.

## D2 실행 계약 · 그룹의 명시적 노출 포트

- 기준 `ca55dde`, 같은 worktree. development-lead → UX → Swift utility → Python backend → read-only review → QA. 확인된 단일 슬롯에서 delegation none이다. 이전 D1은 authoritative source/private push와 native 증거를 남긴 progress다.
- 현재 CanvasGroup은 같은 그래프의 시각 그룹이며 음악 소유자/clock은 바꾸지 않는다. 노출 포트는 그룹 주소·고유 port ID·표시 이름·실제 내부 endpoint를 갖는 명시적 alias다. 하나의 alias는 하나의 기존 IN 또는 OUT을 참조한다. 여러 IN/OUT은 별도 alias로 제공한다. 서로 다른 section clock/graph를 잇는 audio bridge는 이 모델로 가장하지 않는다.
- binding은 project.portLayout의 선택적 배열에 저장해 musicRevision과 분리하고 layout 전용 Undo로 복원한다. 그룹/use별 주소를 포함하므로 재사용 use가 엉뚱한 내부 노드를 참조하지 않는다. 같은 alias의 target은 불변이며 rename은 의미를 유지한다. 제거/대상 삭제는 기존 음악 케이블을 보존하며 자동으로 다른 포트에 매핑하지 않는다. 유효하지 않은 저장 binding은 관리 목록에 표시하고 연결 후보에서 제외한다.
- 그룹의 연결 편집에서 내부 서클/포트를 골라 바로 노출하고, 이름·실제 IN/OUT·대상을 읽고 제거할 수 있게 한다. 기존 연결 편집/키보드/8방향 gesture를 그룹 포트에도 사용한다. 접힌 그룹의 기존 logical edge를 실제 alias 위치로 투영하고, unbound legacy edge는 원래 outline 표시를 유지한다. 단순 접기는 binding을 생성하지 않는다.
- Core 소유: 신규 `GroupPortBinding.swift`, CirclePort/Layout/Geometry/ConnectionEditing/History 계약, HierarchyScene, AgentPortEditing/Protocol와 관련 XCTest. App 소유: 신규 그룹 포트 관리 view, PortConnectionsEditor, InlineCircleEditor, CanvasPorts/CableEditing/ConnectionNavigation 및 명령 접근 경로. Python 소유: mcp server/schema/tests, bundled kit sync. README/CHANGELOG·사용 계약·QA 기록도 갱신한다.
- 검증: alias 실제 port 해석·IN 시작/sidechain/bus·잘못된 그룹/범위/중복/삭제/target 변경의 원자성, 접기/펼치기·readout·GUI/MCP 공통 Undo, 재사용 use 분리, legacy/save/reopen 및 PCM 불변. 전체 offline Swift, Python, release build 후 기존과 분리한 group QA fixture에서 실제 UI 노출·연결·접기·키보드·Undo·저장을 확인한다. 단계가 미완료이면 그대로 기록하고 사용 앱/main 통합은 E에 유지한다.


D2 체크포인트: 그룹 alias·layout Undo·MCP와 같은 캔버스 관리 UI를 구현했다. 실제 키보드 노출/이름/연결·노출 해제/Undo, 그룹 OUT 8방향과 마우스 드래그, native 저장/재열기 및 읽기 전용 조회를 검증했다. 그룹 경계 연결이 사라지던 `CanvasPresentation`의 가시성도 수정했다. album/상위 composition/leaf composition/sound의 소유 검사를 추가해 Swift 212개, Python 25개 및 최종 release build가 통과했다. [D2 근거](../qa/ports-group-review.md).

재생 시 접힌 그룹으로 logical node의 레벨을 전달하는 소스 경로를 보완했으나 최종 QA 앱에서 macOS 출력 장치 연결이 10초를 넘겨 재생이 시작되지 않았다. 이 빌드의 신호 모션·청감은 미검증이다. 다음은 장치 정상 상태의 D2 재생, C3의 남은 신호/밀집/VoiceOver, E의 녹음 branch 보존 통합이다. D2 체크포인트를 전체 포트 완료나 사용 앱 출고로 취급하지 않는다.

후속 관측: 동일 D2 binary에서 장치 연결 이후 재생이 진행됐고 전면 창의 7개 표본에서 그룹 레벨과 두 출력의 모션을 확인했다. 이어 녹음과 통합한 0.20.0 build 23에서 편집/바운스/Undo/저장과 전면 10개 재생 표본을 검증했다. 이전 cold start timeout의 원인이 해결됐다고 단정하지 않는다. [통합 계약](37-daw-integration.md) · [QA](../qa/daw-integration-review.md). 남은 E gate와 재생 follow 밀집 UI 개선을 이어간다.
