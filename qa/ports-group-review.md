# 그룹 노출 포트 D2 검증

2026-09-08, macOS 26.5.1 / Apple Silicon. 기준 `ca55dde`에서 `codex/eight-direction-ports`의 소스 체크포인트를 검증했다. [작업 계약](../docs/35-port-foundation-plan.md) · [사용법과 저장 의미](../docs/36-group-ports.md).

## 범위

그룹 alias는 같은 그래프의 실제 내부 endpoint를 가리킨다. ID·target은 고정하고 이름만 변경할 수 있다. metadata 변경은 layout revision만 증가시키며 노출 해제는 실제 음악 케이블을 유지한다. 새 연결/재연결은 공통 Core에서 실제 endpoint로 정규화한다. 다른 section clock을 연결하는 audio bridge는 구현하지 않았다.

그룹 선택 → 연결에서 내부 포트를 검색하고 노출한다. 이름/노출 해제를 같은 편집기에서 처리하고 새 alias의 연결 편집으로 바로 이동한다. 접힌 그룹의 경계 케이블에 실제 포트 이름을 표시하며, K/P 탐색·8방향 배치·Return 편집을 제공한다. 기존 연결 적용 버튼을 상단으로 이동했다.

역할은 development-lead 계약 → Swift utility/Python backend → 읽기 전용 코드·보안 검토 → native QA로 전환했다. 실제 runtime의 단일 슬롯 한도로 독립 subagent는 실행하지 못했다. 아래 검토는 같은 실행자의 역할 전환이며 독립 리뷰로 표현하지 않는다.

## 자동 검사

- `swift test --scratch-path .build/ports-d2-quality --skip testArrangementRenderExportAndPlayback`: **212개, 실패 0, 18.931초**. `ports-d2-verified-tests.log`.
- `python3 -m unittest mcp/test_server.py qa/test_agent_kit.py`: **25개, 실패 0**. `ports-d2-verified-python.log`.
- `swift build -c release --scratch-path .build/ports-d2-release`: **35.84초, 성공**. `ports-d2-visibility-build.log`.
- 로그는 ignored `qa/generated/ports-foundation/`, native 기록은 ignored `qa/generated/ports-ui/`에 있다. 원본 증거를 overwrite하지 않고 빌드별로 보관했다.

신규 Core 9개는 alias의 실제 IN/OUT·signal·policy·sidechain 의미, 같은 endpoint 중복 no-op, immutable target·이름·해제·layout Undo, 접힌 scene projection과 logical connectionID 보존, IN 시작 router bus 연결·양 끝 방향, stale/project/music/layout 거절, 재사용 use 분리·사라진 대상 보존, wire encoding·legacy 저장/재열기를 검사한다. album/상위 composition/leaf composition/sound의 그룹은 각자의 실제 멤버 주소로 resolve되는지 추가 검증했다.

신규 Audio 검사는 포트 노출·그룹 접기·저장/재열기·layout Undo 전후의 left/right PCM이 정확히 같은지 비교한다. 소리가 실제 재생된다는 주장과 구분한다. 실장치 의존 `testArrangementRenderExportAndPlayback`는 기존대로 제외했다.

오래된 `.build/ports-quality`에서 첫 테스트가 `swift_release → Project assign → AgentPortTests.fixture`의 SIGSEGV로 종료됐다. 새 scratch 경로에서는 재현되지 않았으며 최종 전체 검사가 통과했다. 오래된 incremental 산출물과 구조체 변경의 관련성이 의심되지만 compiler 원인을 확정하지 않았다. 실패 로그와 crash report를 유지한다.

## 실제 앱

전용 `qa/generated/ports-ui/써클러 포트 검증.app`, bundle `com.circlr.portsqa`, socket `~/Library/Application Support/circlr-ports-qa/Agent/agent.sock`만 사용했다. `verify-ports-native.py`는 이 bundle과 정확히 허용한 QA 파일 경로, 녹음 비활성 상태를 확인한다. 설치된 사용자 앱 connector의 쓰기는 사용하지 않았다.

`create-group-port-fixture.py`는 직접 작성한 두 출력 QA tone 프로젝트를 별도 `ports-group.circlr`로 복사하고 기존 target이면 거절한다. router와 source 1을 접힌 그룹으로 묶었다. 기존 네 음악 케이블 중 내부 하나는 숨기고 외부 세 개를 명시적으로 노출한 IN 2/OUT 1/OUT 2에 투영했다. 원래 playback fixture는 유지했다.

| 시나리오 | 증거 파일 접두사 | 관측 |
| --- | --- | --- |
| 그룹 연결 버튼 최초 열기 | d2-editor-failure, d2-editor-fixed-open | 첫 빌드에서 intent가 사라져 빈 그룹만 표시됨. 부모 선택 과정의 intent 보존으로 수정 |
| 키보드 IN/OUT 노출 | d2-ui-first-port, d2-port-id-failure | 검색 → Tab → 방향키 → 이름 → Return. IN `외부 입력`, OUT `메인 출력` 생성 후 연결 편집으로 이동 |
| MCP scalar 반환 | d2-port-id-failure, d2-native-mcp-bindings | 새 alias ID가 null이던 오류 발견. fragmentsAllowed 수정 후 실제 string ID와 duplicate no-op 확인 |
| MCP 이름·해제·두 Undo | d2-native-mcp-bindings | 음악 r1 유지, layout만 변경. target 변경과 stale 요청 거절. 이름/target/음악 그래프 복원 |
| MCP IN 시작 alias 연결 | d2-native-mcp-bindings | 실제 router OUT 1 → output 2로 정규화. from NE/to SW 배치, 한 Undo 뒤 원래 graph, 음악 r1→2→3 |
| 키보드 새 연결 | d2-ui-alias-connected, d2-top-apply | 그룹 OUT 선택 → 출력 2 검색 → Tab/Down → 상단 적용 Return. 음악 r3→4, ⌘Z 뒤 r5와 원래 graph |
| 이름 변경·노출 해제·Undo | d2-ui-renamed-ports, d2-ui-unexposed, d2-manager | 이름 `외부 스테레오 입력`, 변경 중 target control 비활성. 노출 해제 후 2개, ⌘Z 뒤 3개. 음악 r5 유지, layout r14→15→16 |
| 접힌 그룹 주변 케이블 | d2-group-navigate, d2-collapsed-ports | 그룹 편집 깊이에서 주변 서클이 숨겨지던 결함 수정. 실제 그룹 포트와 세 경계 케이블 표시 |
| OUT 8방향 키보드 | d2-keyboard-octants, d2-keyboard-octants-state | Right 8회 각각 AX 방향 확인. 음악 r5, layout r16→24. ⌘Z 한 번으로 직전 방향, layout r25 |
| OUT 직접 drag | d2-native-drag | 오른쪽 그룹 OUT을 위쪽으로 이동. 실제 from 0/to 6, 음악 r5, layout r27. ⌘Z 뒤 r28와 원래 위치 |
| K → Return 바로 편집 | d2-final-prefill, d2-final-editor | 그룹 OUT 메인 출력/출력 1 IN이 prefill. 검색 포커스, 상단 재연결 적용 버튼 확인 |
| 저장/재열기와 읽기 전용 | d2-visibility-open, d2-final-native-assertions | 같은 프로젝트의 세 alias 복원, 최종 duplicate no-op ID, 읽기 전용 5개/그룹 조회·쓰기 거절. 음악 graph 보존 |

초기 두 포트 생성·그룹 선택 수정은 UUID **89AFA57D-63C7-3BD9-817F-256C5E595210**, scalar/MCP·상단 적용·이름/해제는 **B8E83D1F-E412-3255-8197-F4F77B3F6148**에서 검증했다. 마지막 가시성 수정 이후 K/Return·8방향·drag·Undo·재열기·read-only/duplicate 검증은 **746891B9-AA8A-384B-870E-348819499743**에서 수행했다. 전체 초기 시나리오를 최종 바이너리에서 모두 반복했다고 주장하지 않는다.

최종 QA 앱은 서명 strict/deep 검증과 키트 manifest **25개 hash**, 원본 MCP adapter와의 byte 일치를 통과했다. `d2-visibility-app.json`에 경로와 UUID를 기록했다. 이전 QA 앱들은 별도 archive로 보존했다.

검증 harness에서 enum 문자열을 integer octant로 잘못 전달하거나 placement 키를 fromOctant 대신 실제 from으로 확인해야 하는 오류가 있었다. schema 실패는 IPC 전에 거절됐고 이미 성공한 편집은 snapshot으로 확인한 뒤 Undo했다. 최종 근거는 실제 `from/to` 저장값과 음악 그래프 비교다.

## 코드·보안 검토

새 MCP 쓰기의 필수 project/music/layout revision, 현재 사용자 전용 socket 경계, read-only 선차단, 유한 schema와 name/ID/그룹별 64개·전체 16384개 제한을 검토했다. alias target은 실제 그룹 멤버와 구현된 포트를 다시 검사하며 이름 변경으로 target을 치환하지 못한다. 그룹 alias가 recursive target을 만들거나 다른 use에 전파되는 경로를 허용하지 않는다. 오류 시 후보 문서를 commit하지 않고, 연결/위치/metadata Undo는 기존 공통 경로를 사용한다.

검토·native 검사에서 발견한 scalar 응답 null, 부모 선택 시 intent 소실, 주변 케이블 가림, 비활성 popup의 실제 입력 허용 문제는 수정 후 해당 시나리오로 재검증했다. 최종 같은 파일 재열기는 `d2-final-before-reopen`, `d2-final-reopened`에서 음악 r5/layout r28·3개 binding·dirty false와 임시 cable/editor intent 제거를 확인했다. 미해결 release 제한은 아래와 같다.

## 재생 제한과 후속

접힌 그룹으로 원래 logical node의 level을 전달하고 송폼 경계의 logical 주소로 전환 상태를 조회하도록 보완했다. 그러나 최종 QA 앱은 **오디오 출력 장치 연결이 10초를 넘었습니다**라는 오류로 재생을 시작하지 못했다. `d2-playback-group.json`의 16개 snapshot은 모두 seconds 0·animated false·빈 levels이며 `d2-group-playing-active.png`는 실제 오류 안내다. 재생 요청 시 화면(`d2-group-playing.png`)을 활성 모션 검증으로 취급하지 않는다. 정지·오류 안내 닫기 후 편집 기능은 정상 동작했다. 시스템 오디오 장치/TCC 설정과 마이크 녹음은 변경하지 않았다.

따라서 이번 빌드의 그룹 glow·bus별 모션·청감은 미검증이다. 이전 C3a의 실제 재생/영상 근거와 이번 offline PCM 일치는 별도로 유지한다. 장치 정상 상태에서 native 재생을 재검증해야 한다.

남은 항목: 실제 VoiceOver 발화, 모든 신호/그룹 부모·고밀도/최소 너비의 native 조합, drag를 누른 상태의 외부 변경, recording 0.20 branch 통합과 최종 곡/녹음 회귀. 이번 체크포인트는 사용 앱 출고나 전체 포트 기능 완료가 아니다. 사용자 0.19 앱과 recording 작업 디렉터리는 보존한다.
