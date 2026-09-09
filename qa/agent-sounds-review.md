# MCP 음색 목록 검증 — build 62

2026-09-09, `codex/daw-integration`, 기준 `dad574f720d2fe35899f9a2b2db9da7d00a8c57f`. 현재 1 slot 및 직전 실제 dispatch 거절을 근거로 구현/읽기 전용 코드·입력 경계 검토/QA를 순차 수행했다. 독립 agent 검토를 주장하지 않는다.

## 자동 검사

- AgentSoundCatalogTests 6개/실패0, 0.005초. 페이지 완전성/경계·GUI와 같은 Unicode/#번호/제조사 필터, 타입/드럼 분리, plugin state 제외, catalog ID 변경, 입력 오류, Codable/기존 인자 호환, 실제 Core apply의 instrument 보존을 검사했다.
- 전체 `./scripts/swift-local.sh test --scratch-path .build/navigation-reveal-quality --skip testArrangementRenderExportAndPlayback`: 451개/실패0, 27.092초. 기존 HAL 환경의 물리 playback 한 테스트는 제외했다.
- `python3 -m unittest mcp.test_server qa.test_agent_kit`: 28개/실패0, 0.217초. 도구23개 handshake/read-only6개, 조회 IPC/schema, 쓰기 차단과 kit hash/설치를 포함한다.
- release 67.44초. UUID `BFC9D1E8-AB46-3671-B3CF-25FE27233D59`, 0.20.0 build62. 최초 관련 테스트는 fixture raw string 안의 `"#5`가 문자열을 닫는 구문 오류로 실패했고 테스트 delimiter를 고친 뒤 관련/전체 테스트를 실행했다. 제품 런타임 결함은 아니며 실패 로그를 보존했다.

## 실제 MCP와 GUI

`qa/prepare-agent-sounds-qa.py`는 원본 3트랙/2 authored asset의 사본과 두 번째 section use, 수정된 EP cutoff731을 준비한다. ID `85605F18-3F74-5A6D-842A-594EED4EB518`, baseline r14. `qa/verify-agent-sounds-native.py`는 정확한 QA bundle/build/path/projectID와 출력 카운터를 검사한 뒤 실제 Python stdio MCP handshake와 tools/call을 수행한다. GUI 조작을 대신한 가짜 응답은 사용하지 않는다.

| 흐름 | 확인한 결과 |
|---|---|
| 초기 · 최소화 · 재실행 조회 | 각 7페이지·254개(신스10/은행235/AU악기9), 10검색. 모든 페이지와 catalogID가 3회 전체 일치 |
| 전각 #５ / 피아노 / 드럼 / #26 / 드럼 #128 | 4 / 21 / 9 / 1 / 0개. #5는 program4의 LSB0·8·16·24, TR-808은 program25/LSB0/drums=true |
| Apple 효과 / Apple 악기 / E.Piano 1v / 없는 이름 | 23 / 3 / 1 / 0개. AU type 분리·state 없는 descriptor, 마지막 이후 offset은 빈 items |
| 성공한 조회와 read-only apply 거절 | 조회 전후 snapshot 전체 동등. 실제 apply는 adapter에서 거절되어 앱으로 전달되지 않음 |
| 잘못된 target/filter · stale_catalog | 명확한 native 오류. 오류 이벤트 외 음악/revision/선택/창/출력·녹음 유지 |
| 같은 native request ID, 다른 검색어 | 두 sounds 읽기가 각각 #5/#26을 반환하고 상태 동등. 쓰기 retry cache에 들어가지 않음 |
| 조회한 E.Piano 1v를 기존 instrument에 병합 | r15에 kind/program4/LSB16/drumsfalse만 바뀜. cutoff731 포함 모든 기존 patch와 다른 음악 보존 |
| MCP Undo → GUI Redo | r16 기준 음악 복원, r17에 같은 변형 복원. 음악 외 저장된 보기 상태는 별도 비교 |
| 저장·종료·재열기 | focused-saved와 reopened manifest 전체 일치. GUI의 실제 이름/#5/변형16·편집 위치 복원 |

초기/최소화/재실행 suite마다 10검색과 전체 페이지를 수행했다. 최소화 요청의 즉시 응답은 animation이 완료되기 전 false여서 최초 QA assertion이 실패했다. 후속 snapshot에서 minimized=true/visible=false를 확인하고 그 상태의 전체 조회 전후 동등성을 검사했다. 재요청으로 창 상태를 추정하지 않았다.

GUI 4개 화면(`applied-editor`, `current-catalog`, `program-five`, `reopened-editor`)을 저장했다. #5 검색의 실제 네 이름/변형과 적용 범위·현재 선택·입력 포커스가 MCP 결과와 일치한다. CUA API를 잘못 호출한 한 번의 오류 뒤 세션을 reset해 문서를 다시 읽었다. 이후 screenshot으로 새 인덱스가 생성된 상태에서 이전 숫자를 사용해 Help 메뉴를 열었으며, 공개 Cancel action으로 닫고 최신 전체 AX에서 찾은 인덱스로 다시 진입했다. 이 QA 조작 오류는 음악을 바꾸지 않았고 최종 증거에서 분리했다.

## 코드·입력 경계 검토와 보존

Core는 기존 SoundSelection 검색을 사용해 GUI와 의미를 공유한다. catalog ID에는 schema·공개 metadata·notice만 들어가며 plugin state는 encode 전에 제거한다. offset/limit/query/category/드럼 조합을 native에서 검사한다. Python은 타입/길이/숫자 범위를 IPC 전에 확인하고 read-only 도구 집합에 sounds만 추가했다. 값과 음색 이름은 JSON 데이터로 전달하며 shell 실행·새 파일 읽기·네트워크·오디오 시작 경로를 만들지 않는다. App의 startup catalog를 재사용하고 성공한 읽기는 activity/쓰기 cache에 쌓지 않는다. 기존 apply 전체 instrument 교체 의미와 revision/Undo/권한 경계를 바꾸지 않았다. 최종 검토에서 차단 결함은 발견하지 않았다.

`qa/check-agent-sounds-evidence.py`가 저장 상태6개, stdio suite3개, AX/JPEG4쌍, 소스10개 hash, Mach-O section37개, 최종 signed app과 Codex kit25파일을 대조했다. 빌드 후 제품 소스/kit 변경은 없으며 생성 자료는 Git 제외다. 원본 fixture SHA `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`, root HEAD `d88ea5d8d5d87cf49c5ef06154397c36ba1019d7`, ports HEAD `1d304eb244f60a21c3598b89d05192d3512d719d`, 사용자 앱0.19.0 build21을 보존했다. owned QA 프로세스0, 라이브러리1, 모든 capture의 output/audition attempts0, 재생·녹음 없음.

catalog는 이 Mac에서 발견한 시작 시점의 목록이며 설치 환경에 따라 달라진다. 실제 AU instantiate/음질·물리 I/O·VoiceOver 전체 사용 검증은 이번 범위가 아니다. 편곡안의 메뉴 깊이는 실제 소스 경로를 조사했으며 [다음 UI 계약](../docs/76-agent-sound-catalog.md#다음-ui-작업의-실제-진입-경로)으로 남긴다.
