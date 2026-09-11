# 같은 캔버스의 MIDI 서스테인 편집

상태: build151 직접 편집 구현과 아래 native 동선을 완료했다. 최종 data 감사는 PASS_DATA_ONLY, UI 감사는 PASS_WITH_SCOPE_LIMITS다. [서스테인 계약173](173-midi-sustain-plan.md)의 직접 편집 단계를 구체화하며 실제 검증 범위와 미실행 조건은 아래 결과에 구분한다. [build150 파일 연결](176-midi-sustain-file-workflow.md)의 검증과 구분한다.

## 편집 모델

페달은 같은 캔버스에서 노트·스텝·피치 벤드와 동등한 MIDI 모드로 직접 선택한다. 별도 고정 패널이나 깊은 하위 메뉴를 추가하지 않는다. 초기 채널은 화면에 1…16으로 표시하고 CC64 raw 0…127, 이벤트 위치/raw 두 필드를 편집한다. raw 0…63 off·64…127 down을 함께 표시한다. 보간은 hold이며 같은 beat 이벤트의 원래 순서를 안정적으로 유지한다.

초기값 변경·추가·수정·삭제·전체 해제를 제공한다. 화면을 열기만 해서는 nil 시퀀스를 만들거나 schema를 승격하지 않는다. 실제 편집은 schema7 계약을 따르고 nil 상태의 no-op은 음악·revision·Undo를 만들지 않는다. 원래 Note 길이를 늘려 페달을 대신하지 않는다.

## 대상과 입력 보호

이번 use·섹션 원본·공유 pattern의 범위를 구분한다. 일반 node 주소와 공유 pattern/track 주소를 혼합하지 않으며 원래 선택·source identity와 현재 이벤트를 확인한다. 같은 beat가 여러 개여도 과거 index로 다른 이벤트를 덮지 않는다.

유효 draft는 명시적 작업 전에 확정하고 invalid 또는 stale draft는 현재 편집기에서 오류를 표시한다. 선택 대상·sequence·원본 범위가 바뀌었으면 이전 이벤트 선택을 안전하게 해제하거나 작업을 거절한다. 단순 탐색과 Undo/Redo·설정 왕복·파일 가져오기 취소는 기존 음악 및 workspace 계약을 유지한다.

MCP는 명시적인 `sustainChange` packet으로 편집 의도를 전달한다. 일반/공유 주소와 revision·atomic batch·preview·capability를 같은 Core helper에 연결한다. 실제 wire 필드의 정확한 형태는 구현 동결 후 소스와 대조하며 계획상의 이름을 이미 사용 가능한 API로 제시하지 않는다.

## native 검증 흐름

1. 기존 파일의 페달을 직접 열어 raw·상태·이벤트 순서를 확인하고, nil source를 열기만 할 때 음악·schema가 그대로인지 비교한다.
2. 초기 channel/raw, 이벤트 위치/raw·같은 beat 추가·삭제·전체 해제를 실행한다. Undo/Redo와 이벤트 선택의 정확한 복구를 검사한다.
3. 이번 use/원본/공유 패턴의 적용 범위, 다른 use 보존, 외부 MCP 변경 후 stale 선택·draft 차단을 확인한다.
4. 작은 캔버스·콘솔에서 직접 모드 전환, 첫 수치·키보드·오류 가시성, Tab/Escape·설정 왕복·import 취소·저장/재시작을 실제 실행한 범위로 기록한다.
5. GUI/MCP 동일 편집·실패 batch 불변과 내장 신스 오프라인 연주·SMF 왕복·바운스/복원을 연결한다. raw 데이터와 합성 export 종료는 별도로 대조한다.

물리 I/O·청취·모든 backend·모든 입력 조합은 별도 검증이다. 결과 수치는 실제 실행 후 추가하며 기존 source·테스트와 다른 작업자의 변경을 보존한다.

## UI 합의 세부

공통 MIDI 파일 작업을 재사용한다. hold graph에는 64 임계선을 표시하고 같은 beat의 127→0→127을 index·대괄호 키·Home/End로 각각 선택할 수 있게 한다. Return은 추가, Delete는 삭제, 좌우는 위치, 위아래는 raw 1씩(Shift 10씩), Tab은 두 필드, Escape는 초안 처리 후 graph로 돌아오는 계약이다. 전체 점 보기는 범위 밖 이벤트의 접근을 제공한다.

compact에서는 다중 범례 행을 늘리지 않고 scope/선택 한 줄·최소 72pt graph·두 필드를 사용한다. bend와 다른 channel을 지정하면 atomic 거절한다. 공유 편집은 모든 사용처, 일반 편집은 original/이번 use 범위를 보존한다. import 취소·섹션/서클/편곡 왕복과 재열기의 모드·선택 복귀 및 외부 source 변경의 index 무효화를 검증한다. 이는 UI 합의이며 native 완료 결과가 아니다.

## build151 실행 결과

소스·Core/MCP/App 독립 리뷰는 PASS했다. Swift 초기 회귀 686개 중 685개가 통과했고 저장 복원 검사 1개는 fixture의 enableAlbum 누락으로 실패했다 (`.build/sustain-editing-regression.log`, 28.424초). fixture를 보완하고 주소 존재 assertion을 추가한 뒤 `SustainSavedWorkspaceTests` 3개·실패 0개를 0.015초에 재검증했다 (`.build/sustain-editing-savedview-final.log`, build 0.96초). 초기 전체를 686개 무실패로 기록하지 않는다. Python MCP는 29개·실패 0개, 0.017초였다 (`.build/sustain-editing-mcp.log`). Release는 89.22초에 통과했으며 helper stub 패키지와 서명을 확인했다 (`.build/build151-release.log`).

native 증거는 02–17의 JPEG/AX 16쌍이며 이전 CUA 연결에 실패한 01은 제외했다. r236에서 열기만 해도 음악은 변하지 않았고 raw 63→64 r237, invalid 128 및 mode 이동 차단을 확인했다. 같은 beat의 index 2/raw 0과 index 3/raw 127을 개별 선택했고 약 674px compact에서 graph·두 필드를 확인했다.

MCP beat 80/raw 127 추가 r238은 이전 선택을 지웠으며 End로 81박 위치에 접근했다. stale r237 요청은 거절했다. clear r239는 nil, 다시 nil clear는 no-op r239였다. Undo r240→Redo r241→Undo r242를 확인했다. 섹션 설정 왕복과 미지원 import preview 취소 후 mode·index·표시 범위를 복원했다. final/reopened r242를 캡처했으며 전체 manifest 독립 감사도 PASS_DATA_ONLY다.

Core/PCM 검사는 typed 편집→컴파일→렌더를 확인했다. 공유/원본의 실제 native 편집·초기 channel 변경·외부 변경 뒤 stale draft 입력·같은 beat 이벤트 3개의 연속 native 입력·실제 오디오 연주는 실행하지 않았다. 처음과 재열기 focus는 outer canvas이므로 자동 편집 focus 성공을 주장하지 않는다. 물리 I/O는 실행하지 않았으며 QA 앱을 종료하고 사용자 PID 86114를 보존했다. 파일 권한 대기 UX와 더 넓은 제작 동선은 여전히 후속 범위다.

최종 `sustain151/independent-data-audit.json`은 state/manifest 캡처 14개에서 build151·schema7·revision·no-I/O와 자산 SHA 7개를 확인했다. raw 64·beat 80·nil clear·Undo/Redo는 대상 sustain 이외의 음악을 바꾸지 않았다. final/reopened/디스크의 전체 manifest·hierarchyView와 재시작 runtime은 정확히 같았으며 PID 69416→69889, selectedIndex 5·displayedBeats 80을 보존했다. source150 파일 SHA와 Codex 25개 파일·MCP parity·main UUID·helper 5개·서명도 PASS했다. UI 독립 감사는 02–17의 16쌍에서 PASS_WITH_SCOPE_LIMITS이며 autofocus는 포함하지 않는다. 별도 Core target build는 2.15초였다 (`.build/sustain-editing-core-build.log`); 위 savedview 재검사 build 0.96초와 구분한다.
