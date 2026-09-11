# 에이전트 음색 목록 조회 — build 62

session-bootstrap-v1: development-lead, baseline=dad574f, branch=codex/daw-integration. 직전 build61 구현·native QA·private push는 progress다. 현재 1 slot과 직전 dispatch의 thread limit을 근거로 Core/native utility → Python adapter/kit → read-only review/security → QA를 순차 수행한다.

## 계획과 계약

실제 음색 이름을 아는 GUI와 MIDI 주소만 받는 MCP 사이의 단계를 없앤다. 새 읽기 전용 `circlr_sounds`/native `sounds`는 GUI와 같은 catalog/search를 사용한다. 새 Audio Unit instantiate, 장치 시작, 네트워크·파일 업로드·문서 수정은 없다. 기존 set_instrument apply로 선택한 결과를 적용한다.

- 인자: soundTarget=`instrument`(기본)/`effect`, query(최대 256 Unicode scalar), category=`synth`/`soundBank`/`instrument`/`effect`, optional bankDrums, offset=0, limit=64(1–128), optional catalogID. 효과/악기의 맞지 않는 category나 드럼 필터는 오류다. offset은 0–1,000,000 범위이며 끝 이후는 빈 페이지다.
- 응답: schema, catalogID, target/query/filter, offset/limit/total/nextOffset, items, notices. 각 item은 stable id·category·name·detail과 적용용 synthVoice 또는 program/bankLSB/drums 또는 plugin descriptor를 제공한다. plugin state·파일 경로·음원은 목록에 포함하지 않는다. bankLSB=0도 명시한다.
- catalogID는 정렬된 공개 catalog와 notice 내용의 SHA256이다. 후속 페이지에서 다른 catalogID를 받으면 원래 페이지를 이어붙이지 않는다. 클라이언트가 catalogID를 보내면 불일치를 stale_catalog로 거절한다. query/filter는 같은 값으로 유지한다. 성공한 조회는 retry write cache와 activity에도 쌓지 않는다.
- snapshot.runtime에 build와 capabilities.soundCatalog=1을 추가한다. 이전 앱의 같은 0.20.0 버전과 구별한다. adapter는 도구 23개, read-only 역할에 sounds를 포함한다. 기존 명령/권한 경계는 유지한다.
- 반환 instrument 전체를 새로 만들지 말고 최신 snapshot 값에 bank 주소만 병합해 기존 비활성 patch/state를 보존한다. Synth/AU 선택도 기존 객체 의미를 따른다. 동명의 안정된 ID는 식별용이며 신규 쓰기 API를 만들지는 않는다.

소유: Core AgentSoundCatalog.swift/AgentProtocol.swift 및 계약 테스트, App AgentWorkspace.swift, mcp/server.py/test_server.py, Resources/Codex 문서·동기화 adapter/manifest, Info.plist build62, README/CHANGELOG/docs17/25/31/76과 QA helper/report. UI 편곡안의 실제 메뉴 진입 경로를 읽기 전용으로 조사해 다음 범위를 기록한다. 사용자 앱/root/ports/원본 fixture는 보존한다.

## 검증 계획

Core에서 Unicode/#번호·드럼/종류·페이지·stable ID·명시적 LSB0·state 제외·잘못된 입력·catalog 변경을 검사한다. Python에서 read-only 노출, schema/IPC 인자·변이 차단을 검사하고 kit를 재생성한다. 전체 Swift 회귀(기존 물리 playback 제외), Python, release build를 수행한다. 새 authored fixture/소유 QA 앱에서 실제 stdio MCP handshake → 전체 페이지 일치 → 검색 → 보존된 instrument에 병합/apply → Undo/Redo → 저장/재열기와 최소화 상태 조회를 확인한다. GUI의 실제 목록/현재 음색과 반환 주소를 대조하고 원본·음악/선택·장치 카운터·최종 앱/소스/kit hash를 검증한다. 물리 출력·실제 음질은 이 읽기 전용 연결 검증과 구분한다.

## 다음 UI 작업의 실제 진입 경로

`Sources/CirclrApp/InlineCircleEditor.swift`의 곡·악장 설정은 `StudioChoice("편곡안")`에서 이름만 나열한다. `AlbumWorkspace.chooseHierarchyArrangement`는 편곡을 음악 transaction으로 선택하고 소유 composition으로 이동한다. 후속 UI는 이 음악 의미를 유지하면서 설정을 여러 번 열지 않고 검색에 진입하게 한다. 현재 composition 소유 목록, 순번·이름·섹션 수·현재 선택을 표시하고 ↑↓/Return/Esc, 동명/긴 이름·stale 대상·한 번 Undo·저장 복원을 검사한다. 임의 편곡 ID를 다른 composition에 적용하지 않도록 소유 범위를 고정한다. 이 빌드에서는 편곡 선택 UI를 변경하지 않는다.

## 구현·검증 결과

Core query/response·identity 6개와 전체 Swift 451개, Python 28개를 통과했다. 실제 stdio MCP에서 초기/최소화/재실행 3회 각각 7페이지·254악기와 10검색을 대조했고 성공한 읽기 전후 snapshot 전체가 같았다. 명시적 invalid filter/stale_catalog는 오류 이벤트만 추가했으며 음악·선택·출력 상태를 보존했다. 반환된 #5·변형16을 최신 instrument에 병합한 apply, Undo/Redo와 전체 patch 보존·저장 재열기 및 GUI의 같은 목록을 확인했다.

offset0의 기본 조회는 최대64개다. 다음 페이지는 응답 nextOffset을 offset으로, catalogID와 query/filter를 그대로 보낸다. 반환 nextOffset이 없으면 끝이다. 전체 catalog ID는 앱 시작 때 읽은 목록의 공개 metadata에 기반하므로 설치 환경이 바뀌면 앱을 다시 시작한 뒤 새 목록을 조회한다. 현 catalog는 사용자의 저장된 sample 악기를 검색하지 않으며 `soundTarget:"effect"`는 AU 이펙트만 반환한다. 기본 내장 효과의 별도 목록 API는 이 도구 범위에 포함하지 않는다.

전체 증거·패키지·정확한 제한은 [QA 보고서](../qa/agent-sounds-review.md)에 기록했다. 전문 역할은 조회와 제안만 하고 coordinator가 기존 revision 계약에 따라 쓴다. 제품 UI와 음악/물리 I/O의 전체 완료를 뜻하지 않는다.
