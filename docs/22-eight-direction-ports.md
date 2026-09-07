# 8방향 포트와 다중 입출력

작성일: 2026-09-07 · 상태: 사용자 요구 확정, 상세 계약 제안 · 기준 앱: 0.10.0

**서클 둘레의 8방향 어디에나 연결을 붙이고, 연결점에 IN·OUT을 표시한다. 서클은 여러 입력과 여러 출력을 지원한다.** 왼쪽 입력·오른쪽 출력으로 방향을 고정하지 않는다.

8방향은 배치 기준이다. 포트나 케이블을 8개로 제한한다는 뜻이 아니다. 여러 케이블의 분기·합산과 서로 독립적인 여러 입출력 포트를 함께 설계한다. 이번 변경은 문서이며 현재 앱의 포트 UI나 엔진이 갱신된 것은 아니다.

## 1. 방향과 포트의 구분

기본 연결 위치를 45도 간격의 8개 방향으로 정한다. 사용자가 가까운 위치에 놓으면 해당 방향으로 붙는 방식을 제안한다. 연속 360도 임의 각도는 이번 확정 요구에 포함시키지 않는다.

```text
                     위 · N · 0
          왼쪽 위 · NW · 7     오른쪽 위 · NE · 1

       왼쪽 · W · 6        서클        오른쪽 · E · 2

        왼쪽 아래 · SW · 5     오른쪽 아래 · SE · 3
                    아래 · S · 4
```

- 어느 방향이든 IN 또는 OUT이 될 수 있다. 위쪽 입력과 아래쪽 출력, 오른쪽 입력과 왼쪽 출력도 가능하다.
- 같은 방향에서 IN과 OUT을 함께 쓸 수 있다. 겹치면 해당 방향의 연결 영역 안에서 표식을 나누고 선택 시 펼쳐 보여준다.
- 포트는 신호의 정체성이고 방향은 화면 배치다. 연결 위치 이동으로 IN이 OUT이 되거나 신호 종류가 바뀌지 않는다.
- 한 논리 OUT을 여러 방향에 표시해 분기할 수 있다. 이때 같은 포트 이름을 유지한다. 별개의 output bus인 것처럼 번호를 바꾸지 않는다.
- 노드가 실제로 제공하는 입출력만 연결 가능하다. 입력 없는 소스에 가짜 IN을 만들거나 stereo 출력 하나를 독립적인 8개 bus로 표시하지 않는다.

**예:** 한 synth의 `OUT 메인`에서 위쪽은 reverb로, 오른쪽은 mix로 연결할 수 있다. compressor는 `IN 메인`을 아래쪽에, `IN 사이드체인`을 왼쪽 위에 배치한다. 케이블이 어느 쪽으로 향하든 신호는 OUT → IN이다.

## 2. IN·OUT 표시와 연결 조작

| 요소 | 계약 |
|---|---|
| 방향 표시 | 포트 옆 `IN` / `OUT`과 안쪽·바깥쪽 화살표. 빈 점·채운 점이나 색만으로 구분하지 않음 |
| 포트 식별 | `IN 메인 · 오디오`, `IN 사이드체인 · 오디오`, `OUT 메인 · 스테레오`, `OUT MIDI`처럼 실제 역할과 형식 표시 |
| 케이블 | OUT → IN 화살표를 표시. 선택하면 양 끝의 서클·포트 이름과 연결 종류가 드러남 |
| 새 연결 | OUT 또는 IN에서 시작 가능. 반대편의 호환 포트를 고르면 항상 OUT → IN 순서로 저장 |
| 둘레에 놓기 | 가장 가까운 8방향을 preview. 호환 포트가 하나면 연결, 여러 개면 같은 캔버스의 작은 선택기로 포트를 고름 |
| 분기 추가 | 이미 연결된 OUT에서도 새 케이블을 시작할 수 있음. 기존 연결을 대체하지 않음 |
| 연결 교체 | 선택한 케이블의 끝점을 끌어 재연결. 성공 전까지 기존 연결 유지, Esc/무효 대상은 원상 복귀 |
| 위치만 바꾸기 | 명시적 **연결 위치 이동**으로 같은 포트를 다른 방향에 배치. 신호 대상·gain·길이·시간은 유지 |
| 연결 해제 | 선택한 edge 하나만 제거. 다른 분기·입력·노드는 유지 |
| 잘못된 연결 | IN↔IN, OUT↔OUT, 신호 형식 불일치 등 원인을 연결 위치에 표시. 임의 변환이나 기존 선 제거 없음 |

한 논리 포트의 여러 케이블은 서로 다른 방향에서 나갈 수 있다. 따라서 실제 케이블 끝점의 위치를 edge별로 저장한다. 특정 케이블의 위치 이동이 같은 포트를 쓰는 모든 케이블을 움직이지 않는다. 노드의 기본 포트 위치는 새 연결의 시작값으로만 사용한다.

연결하지 않은 포트와 8방향 후보는 서클 선택·연결 중에 상세 표시한다. 사용 중인 포트는 방향을 읽을 수 있게 유지한다. 축소해 글자가 읽히지 않으면 IN/OUT별 연결 수로 묶고, 선택·확대·키보드 포트 목록으로 개별 연결을 찾는다. 접힌 표시가 숨어 있는 hit target으로 작동하면 안 된다.

### 시간 궤도와의 조작 충돌

포트 연결 영역은 음악 눈금·playhead·시작 시간 손잡이와 구분한다. 같은 12시 위치라도 포트는 연결, 시간 손잡이는 음악의 시작 위치다. 포트의 방향은 재생에 따라 회전하지 않는다.

드래그 시작 시 `새 연결 / 재연결 / 연결 위치 이동 / 시간 편집 / 노드 이동` 중 한 조작을 고정하고 끝날 때까지 바꾸지 않는다. 겹친 작은 요소를 추정 선택하지 않고 명시적 선택을 제공한다. 실제 hit 영역은 화면 좌표 기준으로 유지하며 zoom과 표시 반경이 달라져도 그린 포트와 hit 위치가 일치해야 한다.

일반 휠 zoom, Shift 휠 편집 스크롤, 확대 시 같은 캔버스 편집을 유지한다. 케이블은 시작·끝 방향의 바깥쪽 법선을 이용해 구부린다. 선 정리는 선택한 방향을 바꾸지 않고, 교차한 선을 전기적으로 연결된 것으로 해석하지 않는다.

## 3. 멀티 입력·출력의 실행 의미

| 형태 | 동작 | 명시할 조건 |
|---|---|---|
| 하나의 OUT → 여러 IN | 같은 출력을 각 경로에 전달하는 분기 | 출력 gain을 목적지 수로 나누지 않음. processor를 분기 수만큼 중복 실행하지 않음 |
| 여러 OUT → 합산 가능한 오디오 IN | 연결별 gain을 적용해 해당 입력에 합산 | 자동 normalize 없음. 합산 결과의 level·clipping을 실제로 확인 |
| 여러 MIDI OUT → MIDI IN | 시간·출처를 유지한 event merge | 동일 note의 중첩·note-off·channel 정책과 순서를 결정적으로 처리 |
| 하나의 서클에 여러 IN | 메인·sidechain·bus 등 독립 입력 | 포트별 합산 정책을 따름. sidechain을 메인 오디오에 합산하지 않음 |
| 하나의 서클에 여러 OUT | 실제로 구분되는 출력 bus·데이터 | 출력별 ID·형식·처리 결과. 한 출력을 여러 번 표시한 것과 구분 |
| 하나의 입력만 받는 포트 | 두 번째 연결을 거절하거나 명시적으로 교체 | 기존 케이블을 조용히 제거하지 않음 |

입력마다 `single / audioSum / midiMerge / references` 등의 수용 정책을 선언하는 안을 제안한다. 포트 수·채널 수·케이블 수는 서로 다르다. mono/stereo 또는 MIDI/audio가 맞지 않으면 실제 변환기를 명시적으로 사용하며, 화면에서 연결됐다는 이유로 지원되지 않는 변환을 수행하지 않는다.

동일한 source port → target port 연결을 다시 추가하는 기본 동작은 중복 생성을 막는다. 의도적인 이중 경로는 분기·처리·mix로 표현한다. 신호의 합류로 같은 재료가 두 번 합산되는 경우는 실제 두 경로로 표시하며 자동으로 하나를 삭제하지 않는다.

현재 음악 신호 graph의 cycle 거절을 유지한다. 8방향 연결이나 멀티 입출력이 무제한 feedback·반복 재생을 의미하지 않는다. processor feedback 지원은 delay와 실행 규칙을 별도로 정의할 과제다.

### 연결 종류별 의미

- 음악의 MIDI/audio/sidechain 연결은 위 신호 규칙을 따른다.
- 송폼의 여러 출구는 재생 경로 선택·반복·전환 규칙을 따른다. 여러 선을 그렸다고 모든 섹션을 동시에 재생하지 않는다.
- 아티스트·가사·이미지·세계관의 IN/OUT은 이름 붙인 관계의 출발·도착이다. 데이터 종류·관계명을 표시하고 audio routing으로 해석하지 않는다. 상호 참조의 순환은 음악 feedback과 별개다.
- 그룹 밖으로 연결하는 경우에는 명시적으로 노출한 포트를 사용한다. 그룹 IN과 내부 IN의 binding, 내부 OUT과 그룹 OUT의 binding은 별도 alias 관계이며 OUT→IN 케이블을 억지로 추가하는 방식이 아니다. 단순 접기·펼치기는 논리 포트를 만들거나 신호를 변경하지 않는다.

## 4. 현재 구현과 변경할 계약

소스 확인 결과이며 이번 턴에 렌더·native 동작을 재검증한 결과는 아니다.

| 현재 위치 | 확인 내용 | 필요한 확장 |
|---|---|---|
| `Sources/CirclrApp/AlbumCanvas.swift` | 포트와 케이블을 왼쪽/오른쪽에 그림. 출력 시작 hit도 오른쪽 기준 | 8방향 endpoint geometry·hit·방향별 곡선·IN/OUT 표시·양쪽 시작 gesture |
| `Sources/CirclrCore/HierarchyScene.swift` | acceptsInput/providesOutput과 node 주소 중심 scene | 실제 port descriptor·endpoint anchor를 가진 scene |
| `Sources/CirclrCore/SectionGraph.swift` | content별 단일 input/output 종류. edge는 node ID와 sidechain flag | stable port ID 배열, source/target port 참조, 수용 정책 |
| `Sources/CirclrCore/Model.swift` | 전역 SignalGraph도 node ID 중심 edge | 섹션과 전역 그래프에 일관된 포트 모델 적용 |
| `Sources/CirclrAudio/SectionGraphRenderer.swift` | 여러 MIDI 입력 취합·audio 합산·sidechain 분리, node당 PCM buffer | port별 입력·출력 buffer와 실제 다중 bus routing |
| `Sources/CirclrApp/AlbumWorkspace.swift` | node 주소로 connect/disconnect | port endpoint와 연결 유형을 받는 공통 명령 |
| `Sources/CirclrCore/AgentProtocol.swift`, `mcp/server.py` | connect는 from/to node ID와 sidechain 중심 | port 조회·지정·배치 명령, 모호한 legacy 요청의 오류 |

### 제안 데이터 모델

| 모델 | 필드와 책임 |
|---|---|
| `CirclePort` | `portID`, `direction`, `kind`, `name`, `role`, `format`, `acceptPolicy`, 실제 지원 capability |
| `PortEndpoint` | graph scope, node ID 또는 CircleAddress, portID. 논리 신호 대상 |
| `Connection` | edgeID, fromEndpoint, toEndpoint, 종류·gain 등 실행 속성 |
| `EndpointPlacement` | layout 안의 edgeID + from/to 끝점, `octant: 0...7`, 같은 방향의 표시 순서 |
| `PortDefaultPlacement` | 새 연결에 사용할 node/port별 기본 방향. 사용자가 고른 기존 edge 위치는 변경하지 않음 |
| `ExposedPortBinding` | 컨테이너 포트와 내부 endpoint의 명시적 대응. 접힌 상태의 단순 시각 투영과 구분 |

화면 좌표는 위가 0이고 시계 방향이다. `theta = octant × π/4 − π/2`와 실제 서클 외곽 반경으로 방향을 계산한다. 이는 음악 tick의 시간 각도 계산과 별도다. 포트/케이블 위치는 layout 변경이며 `musicRevision`·BPM·note·clip·실행 순서는 바뀌지 않는다. 레이아웃 revision 또는 그에 준하는 충돌 검사는 별도 저장 계약으로 추가한다.

compiler/renderer는 node 전체 출력이 아니라 `(nodeID, portID)`를 읽고 쓴다. 여러 입출력 bus가 있는 processor도 하나의 처리 실행에서 실제 출력들을 얻는다. Audio Unit의 bus 지원은 host와 실제 plugin이 제공하는 형식에 맞춰 검증한다. 이번 설계만으로 모든 multi-output plugin을 지원한다고 표시하지 않는다.

### 기존 프로젝트 보존

1. 기존 일반 edge는 source 기본 OUT과 target 기본 IN으로 매핑한다. 화면 위치는 기존 오른쪽 `E=2`, 왼쪽 `W=6`을 초기값으로 유지한다.
2. 기존 compressor sidechain은 이름 붙인 sidechain IN에 매핑한다. 다른 main 입력과 gain·처리 순서를 보존한다.
3. 기존 node/edge ID·원본/사용별 override·접힌 그룹·bounce 원본 복원 정보를 유지한다. multi-port가 된 뒤 effect 삽입이 한 node의 모든 출력을 한꺼번에 재연결하지 않도록 경로를 지정한다.
4. 포트 이름이나 화면 순서가 바뀌어도 portID는 유지한다. plugin 교체로 포트가 사라지면 연결을 미해결 상태로 보관하고 임의의 다른 bus로 연결하지 않는다.
5. 새 schema의 구체적 버전은 구현 시 결정한다. 이전 파일은 사본 migration과 저장/재열기·음원 비교를 검증한 뒤 지원한다. 배치만 바꾼 전후의 음원은 동일해야 한다.

## 5. MCP와 AI 계약

에이전트는 8방향을 화면 클릭으로 맞출 필요가 없다. `inspect`에서 포트의 ID·IN/OUT·형식·수용 정책·연결·현재 배치를 조회한다. 연결 요청은 scope와 `fromPortID`·`toPortID`를 명시하고, 배치가 필요할 때만 각 endpoint의 octant를 지정한다.

현재 `connect`의 from/to node ID만 있는 요청은 호환 기본 포트가 유일할 때만 해석하는 안을 제안한다. 후보가 여러 개이면 포트 선택이 필요하다는 오류와 후보를 반환한다. GUI도 같은 검증을 사용한다. 실제 새 필드·operation은 아직 MCP에 추가하지 않았다.

**신호 연결**과 **연결 위치 이동**은 다른 명령이다. 후자는 layout만 바꾸며 음악 revision의 충돌 검사로 모든 배치 충돌을 해결했다고 보지 않는다. 프로젝트·아티스트 scope, 원자적 편집·Undo, 취소·재전송 경계는 기존 [MCP 계약](17-agent-interface.md)과 [Codex 계획](20-codex-account-console-plan.md)을 이어간다.

## 6. 구현 순서와 인수 기준

| 단계 | 소유와 파일 | 종료 조건 |
|---|---|---|
| A · 공통 계약 | Core: `SectionGraph.swift`, `Model.swift`, `HierarchyScene.swift`, `SectionGraphMigration.swift`, `ProjectStore.swift`; 신규 `CirclePort.swift` 후보 | 포트·형식·edge·layout 모델과 legacy migration. 섹션/전역 routing 의미 동일 |
| B · 실제 다중 입출력 | Audio: `SectionGraphCompiler.swift`, `Sources/CirclrAudio/SectionGraphRenderer.swift`, `AudioUnitHost.swift`; 관련 bounce 처리 | port별 fan-in/fan-out. 독립 2 IN·2 OUT을 가진 내장 routing 경로에서 교차 누출 없이 실제 다른 PCM 출력 확인 |
| C · 8방향 조작 | Native UI: `AlbumCanvas.swift`, `AlbumWorkspace.swift`, scene geometry; 신규 `CirclePortGeometry.swift` 후보 | 8방향 모두에서 IN/OUT 시작·연결·재연결·위치 이동. 시간 손잡이와 구분, Undo·save/reopen |
| D · 그룹·에이전트 | Core/App/MCP 담당: 노출 포트 binding, `AgentProtocol.swift`, `AgentWorkspace.swift`, `mcp/server.py` | 그룹 경계 보존과 명시적 port 조회·연결·배치. legacy 모호성 오류 검증 |
| E · 통합 QA | `Tests/CirclrCoreTests/`, `Tests/CirclrAudioTests/`, Python MCP 테스트, 향후 `qa/eight-direction-ports-review.md` | geometry·실제 신호·native gesture·기존 곡의 회귀를 별도 증거로 확보 |

이 표는 후속 엔지니어링 작업 분해다. 새 파일과 실제 다중 bus 경로는 생성 전이며, 단계 C의 그림만으로 전체 기능을 완료 처리하지 않는다. B의 최소 검증은 모든 외부 plugin 호환성을 요구하지 않는다.

| 인수 시나리오 | 기대 결과 |
|---|---|
| N/NE/E/SE/S/SW/W/NW 각각에서 IN/OUT 연결 | 모든 방향 가능, 실제 화살표와 저장된 endpoint 방향 일치 |
| 같은 방향의 여러 입력·출력, 8개 초과 연결 | 개별 포트/edge 선택 가능. 연결 수를 방향 수로 제한하지 않음 |
| 한 OUT을 여러 방향으로 분기 | 같은 portID와 출력 유지. 기존 분기 삭제·자동 gain 분배 없음 |
| 독립 입력 2개·독립 출력 2개 | 각 경로에 서로 다른 입력을 넣어 출력 분리와 port별 값 검증 |
| main과 sidechain 동시 입력 | main 합산에 sidechain이 섞이지 않고 compressor 검출에만 적용 |
| 같은 pitch·channel의 MIDI 입력 중첩 | event 순서와 note-off 처리 결정적. 중복/누락과 stuck note 검사 |
| 입력 포트에서 역방향 드래그 | 저장된 edge는 OUT→IN. 잘못된 동종 방향 연결은 무변경 |
| 방향 이동·zoom·그룹 접기·저장/재열기 | 배치 복원. 음악 revision·길이·note·PCM 불변 |
| 재연결 중 Esc·잘못된 대상·삭제된 대상 | 이전 유효 연결 유지, 원자적 적용, 한 gesture 한 Undo |
| 계층 밖 연결 | 노출된 port binding만 통과. 숨은 owner 변경이나 임의 cross-graph edge 없음 |
| 연결된 port 삭제·plugin 교체·bounce/복원 | 다른 포트로 자동 연결하지 않음. 원본 port/edge와 분기 보존 |
| MIDI/audio 불일치·제한 초과·음악 cycle | GUI·MCP 모두 원인과 함께 거절. 부분 edge 적용 없음 |
| native 키보드·VoiceOver·작은 창 | IN/OUT·역할·형식·대상 이름을 읽고 선택. 포트와 시간 손잡이 구분 |

이번 확인은 소스 조사와 문서 계약 점검이다. 앱 빌드·새 gesture·PCM 검증은 구현 이후 수행한다.
