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
