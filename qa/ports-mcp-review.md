# 포트 MCP D1 검증

2026-09-08, `codex/eight-direction-ports`, 기준 `1337ce5`. development-lead 계약 → native Swift utility → Python backend → security/code review → QA 역할 전환으로 수행했다. 사용자의 한도 해제 안내 후 독립 검토를 요청했지만 실제 `spawn_agent`는 `agent thread limit reached`로 거절됐다. 독립 에이전트 리뷰 결과는 없다.

## 계약과 자동 검사

포트 조회와 connect/reconnect/disconnect/move를 GUI 공통 Core 명령에 연결했다. 실제 logical 주소와 port ID를 요구하며 group alias를 허용하지 않는다. 모든 새 쓰기는 project ID, 음악 revision, layout revision을 검사한다. 연결 중복과 배치 no-op는 음악/Undo를 변경하지 않으며 move는 layout 전용 Undo다. Core는 후보 문서를 반환하고 AppStore가 실제 변경 한 번에 음악 revision/Undo를 적용한다.

- `swift test --scratch-path .build/ports-quality --skip testArrangementRenderExportAndPlayback`: **202개, 실패 0, 21.080초**. 로그 `generated/ports-foundation/ports-d1-all-tests.log`.
- 신규 `AgentPortTests` **8개**: 실포트 조회·wire roundtrip·IN 시작 정규화·중복 no-op, 재연결 ID/gain 보존·해제·다른 use 유지, 네 쓰기의 stale project/music/layout 및 누락 거절, 다중 배치 atomic/no-op·음악 보존 Undo, ambiguous bus/신호/범위/없는 edge 거절, MIDI/sidechain/flow, 잘못된 octant/type native decode 거절. 개별 로그 `ports-d1-core-tests.log`.
- `swift build -c release --scratch-path .build/ports-release`: **46.40초**, warning/error 0. 로그 `generated/ports-foundation/ports-d1-build.log`.
- `python3 -m unittest mcp/test_server.py qa/test_agent_kit.py`: **24개, 실패 0**. 최종 로그 `generated/ports-foundation/ports-d1-final-python-tests.log`.
- Python은 19개 실제 catalog, 5개 read-only catalog, 모든 쓰기의 read-only 차단, exact address oneOf/ID 길이·필수값·bool/숫자/octant/배치 크기, revision IPC 전달과 kit 동기화를 검사한다. 첫 실행의 kit 사본 불일치는 build-agent-kit으로 해결했다. 테스트를 약화하지 않았다.

오디오 엔진 코드는 변경하지 않았다. 이번 단계에서 하드웨어 재생·새 PCM 렌더·마이크 검증을 주장하지 않는다. 기존 전체 offline 회귀에는 포트 방향 변경의 PCM 불변 검사가 포함된다.

## 실제 native 앱

대상은 전용 `qa/generated/ports-ui/써클러 포트 검증.app`, bundle `com.circlr.portsqa`, 실행 UUID **9D0C0E9D-32E6-3649-B061-5216B3BF2DEF**다. 사용 앱과 녹음 QA 앱을 교체하지 않았다. 실제 문서는 전용 Application Support의 `ports-playback.circlr`, project **A727DC35-BB4D-5C79-AEB1-004A2F0CC2B0**만 편집했다. 다른 사용자 음악 파일은 대상이 아니다.

재현 스크립트 `verify-port-mcp.py`는 정확한 QA bundle/project/path, 재생·녹음·권한 대기 해제를 확인하고 고유 이름의 증거를 만든다. 최소화는 OS 애니메이션 완료를 기다린다. 첫 시도 `d1-native-mcp.json`은 이 대기 없이 즉시 확인해 실패했으며 음악 변경 전이었다. 수정 후 `d1-native-mcp-final.json` **29개 기록 단계**가 통과했다.

1. 라우터의 IN 1/2·OUT 1/2 descriptor와 원래 케이블 4개, 배치를 읽었다.
2. 창이 실제 최소화된 상태에서 IN 2부터 source 1 OUT으로 연결했다. 중복 요청은 changed:false이고 기존 배치를 유지했다. 오래된 음악 revision은 거절했다.
3. source 2 OUT→IN 1로 재연결하면서 edge ID를 보존했다. 이전 logical 주소의 ID로 해제하는 요청은 거절했다. 정확한 ID 해제 후 Undo 3회로 원래 그래프·4개 케이블·배치를 복원했다.
4. 케이블 4개의 양 끝을 합계 8방향으로 한 번에 배치했다. 음악 revision 불변, layout revision만 +1이었다. no-op와 stale layout move/undo 거절, 중간에 없는 edge를 포함한 batch 전체 무변경을 확인했다. 한 Undo로 모두 복원했다.
5. 선택·zoom 및 최소화 상태를 유지했다. save/open 완료 후 graph·케이블·배치·두 revision 및 저장 manifest를 대조했다. 음악 **13→19**, 배치 **28→34**였으며 원래 음악과 배치를 복원했다.
6. 추가 MCP 배치 **layout 34→35**, 음악 **19 유지**를 실제 AX의 `OUT 위 · IN 아래`와 대조했다. 앱의 **⌘Z 한 번**으로 배치 **36**과 원래 케이블 위치를 복원해 저장했다. `d1-ui-move.json`, `d1-ui-move-ax.txt`, `d1-ui-undo.json`에 기록했다.

마지막으로 같은 실행 파일에 최신 에이전트 키트를 넣어 25개 manifest 파일 hash와 adapter 소스 바이트를 대조하고 deep/strict 서명을 통과했다. `d1-package.json`에 기록했다. 기존 C3c QA 앱과 D1 코드 검증 앱은 별도 archive로 보존했다. 최종 패키지를 재실행해 fixture open 완료와 **r19/layout36/dirty:false**를 확인했다. 내장 adapter의 실제 stdio `--read-only` handshake/catalog/ports 조회가 통과했고 5개 읽기 도구와 실제 포트 4개를 반환했다. `d1-final-kit-smoke.json`의 원래 graph 비교도 일치한다.

## 역할 전환 검토와 다음 범위

- 새 입력은 기존 사용자 UID 전용 Unix socket과 8 MiB 경계를 사용한다. TCP/shell/외부 파일 명령을 추가하지 않았다. MCP는 주소 shape/필수 필드/범위를 검사하고 native Core가 실제 포트·신호·범위·revision을 다시 검사한다.
- ports는 요청 결과 캐시 대상에서 제외해 최신 상태를 읽는다. 새 쓰기는 기존 request-ID 중복 실행 보호를 사용한다. 기존 14개 명령 및 undo의 음악 revision 계약을 유지하며 layout guard는 undo에서만 선택 사항이다.
- 보안/코드 역할 전환 검토에서 새 변경의 고신뢰도 차단 결함은 찾지 못했다. 직접 native raw request의 unknown field 무시는 기존 Codable 정책이며, 공개 MCP schema는 unknown field를 거절한다.
- 실제 microphone/VoiceOver 발화·모든 신호/그룹 pointer 조합, 그룹 노출 binding D2, 녹음 branch 0.20과 통합, v4/패키지 전체 E gate는 남아 있다. 명시적 포트 API D1의 성공을 전체 DAW 완성이나 사용 앱 출고로 취급하지 않는다.

생성된 fixture/audio/app/실행 로그는 Git 제외 경로에 보관한다. private source checkpoint에는 소스·검사·사용 계약·QA 기록만 포함한다.
