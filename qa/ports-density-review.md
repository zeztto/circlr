# C3c · 포트 가독성과 시간 손잡이 검증

2026-09-08, 기준 `1d3e0ae`, `codex/eight-direction-ports`. 전용 `com.circlr.portsqa` 앱과 허용된 `ports-playback.circlr`만 사용했다. 소스 checkpoint이며 사용 앱 출고가 아니다.

## 변경과 검토

선택 서클의 모든 논리 포트를 8방향에 반복해 보이던 표시를 대표 지점+실제 연결 위치로 줄였다. 포트 클릭/P 선택으로 해당 포트만 펼치며, 드래그 중에는 같은 신호·반대 방향·같은 graph의 가까운 대상을 상세히 보여준다. persisted octant·logical port ID·음악 schema와 renderer는 유지했다.

포트 이름은 논리 포트마다 한 번, 선택 끝점 우선으로 배치한다. 라벨·포트 점·시간 손잡이·편집기·도구막대와 겹치지 않는 사각형만 선택한다. 공간이 없으면 텍스트를 생략하고 실제 포트 점·선택 도구·접근성 이름은 유지한다. 짧은 클릭은 선택이며 연결 mutation을 만들지 않는다. 드래그 중 도구막대는 숨기고 hit 차단도 해제한다.

시간 손잡이는 실제 표시 조건과 클릭 조건을 통일했다. 화면에 가려진 손잡이는 hit되지 않으며, 보이는 손잡이 근처 23pt 이내의 일반/선택 케이블 포트 점을 제외한다. 궤도 시간 편집과 연결 편집의 우선순위가 모호하지 않게 한다.

development-lead/UX 계약 → native Swift utility → read-only review → QA 순서로 진행했다. 독립 리뷰 spawn은 실제 agent 한도 오류로 거절되어 같은 실행자의 역할 전환 검토다. 입력·좌표·표시/hit 일치·stale gesture·숨긴 도구의 hit 조건을 검토했다. 인증·외부 요청·MCP 쓰기 명령은 변경하지 않았다.

## 자동 검증

`swift test --scratch-path .build/ports-quality --skip testArrangementRenderExportAndPlayback`: **194개, 실패 0, 19.344초**. 실제 장치 재생에 의존하는 단일 검사는 기존대로 제외했다. `swift build -c release --scratch-path .build/ports-release`: **22.29초**, warning 없음. 최종 QA 앱 codesign 검증 통과, 실행 파일 UUID **2EB45141-E31D-369F-BFF7-63843C4568D0**.

신규 4개 검사는 router 기본 4개/선택 11개 표시, 선택 포트의 모든 8방향 hit, 작은 확대에서의 hidden hit 부재, 기존 비기본 연결 위치·MIDI/flow/sidechain 표현, 라벨의 가림·중복·선택 우선순위·유한 좌표를 검사한다. 촘촘한 배치에서 한 라벨이 빠진 초기 실패를 보존했고 대각선 배치 후보를 보완한 뒤 통과했다. 로그는 Git 제외 경로 `qa/generated/ports-foundation/ports-c3c-*.log`에 있다.

## Native 증거

원본은 Git 제외 경로 `qa/generated/ports-ui/`에 보관한다. JSON의 effective graph·saved manifest·runtime snapshot과 실제 CUA 동작을 대조했다.

| 시나리오 | 증거 | 확인 결과 |
|---|---|---|
| 전후 화면 | `c3c-before.png`, `c3c-overview.png`, `c3c-click-selected.png` | 반복 라벨 제거, 네 포트 이름 식별 |
| 대표 지점 → 클릭 선택 | `c3c-overview.json`, `c3c-click-selected.json` | 실제 handle 4→11, 음악 r7 유지, graph 동일 |
| 대각선 IN → 오디오 OUT 드래그 | `c3c-reverse-drag.json`, `c3c-reverse-undo.json` | OUT→IN 정규화, northeast 저장, 음악 r7→8→9, 한 Undo로 네 연결 복원 |
| 궤도 시간 드래그·Undo | `c3c-final-time-base/moved/undo.json` | 음악 r9→10→11, source 1 `startBeat`만 0→0.5, 케이블 유지, 원래 graph 복원 |
| 도구막대에 가려졌던 대상 드래그 | `c3c-final-covered-base/connected.json`, `c3c-final.json` | IN 2 NE→source 1 OUT, 실제 OUT→IN/NE 저장, r11→12→13, 한 Undo로 원본 graph 복원 |
| 키보드 회귀 | 최종 앱 CUA 상태 | P→Return의 IN 1 prefill·검색 포커스 확인 |
| 저장 후 같은 파일 재열기 | `c3c-final.json`, `c3c-reopened.json` | open job 완료 확인, 음악 r13·effective graph·port layout 동일 |
| 라벨 기하와 시간 손잡이 | `c3c-native-assertions.json` | 저장한 10개 화면 상태의 라벨 ID 중복 없음, viewport 안, 라벨·포트 점과 겹침 없음, 보이는 시간 손잡이와 port hit 분리 |

처음 클릭·역방향 드래그는 UUID **B123B7A0-29CC-3FF2-B3F4-730CFCA805E2**에서 확인했다. 시간 드래그와 가려진 대상 연결·키보드 회귀·최종 화면은 위 최종 UUID에서 확인했다. `c3c-final-overview.png`는 최종 앱의 실제 화면이다. 검증 종료 시 음악 그래프와 자유 배치 보기 모두 원래대로 복원했고 revision은 편집/Undo 이력에 따라 r13이 됐다.

## 남은 범위

이 검증은 실제 오디오 청감·실시간 엔진·VoiceOver 발화를 대신하지 않는다. 모든 MIDI/sidechain/송폼·접힌 그룹·최소 너비·밀집 궤도 조합과 드래그 중 외부 변경 전체 행렬은 여전히 후속이다. 다음은 D의 명시적 포트 조회/연결/배치 revision MCP와 group binding, E의 녹음 branch 통합·기존 음악 회귀·사용 앱 출고다.
