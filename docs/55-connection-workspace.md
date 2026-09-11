# 연결 대상과 케이블의 직접 탐색

2026-09-09, 기준 `0e0092b`, build 41 계획. 이전 goal turn은 build 40의 구현·검증·private push로 progress다. development-lead → UI/UX → native Swift utility → read-only review → QA로 수행한다. 독립 audit 요청은 `agent thread limit reached`로 거절되어 delegation none이다.

## UX 계약

같은 캔버스 연결 편집기에서 대상 검색 결과를 목록으로 보여준다. 대상 이름과 IN/OUT 포트 이름을 두 줄로 분리하고 전체 이름을 접근성/도움말로 제공한다. 클릭 또는 검색창의 위아래 키로 대상을 선택하며 Return은 현재 선택을 연결한다. 입력기 조합 중 Return은 연결로 처리하지 않는다. 검색 결과가 없거나 선택 대상이 사라지면 연결을 비활성화하고 잘못된 대상에 적용하지 않는다. 자동으로 첫 결과를 연결하지 않는다.

넓은 화면에서 새 연결의 결과 목록과 기존 연결 영역을 각각 스크롤해 한쪽을 탐색해도 다른 쪽의 시작이 밀리지 않게 한다. 기존 케이블의 OUT/IN 이름, 재연결/해제와 두 위치 선택은 유지하면서 행을 압축한다. 전체 연결/현재 포트 필터로 다중 bus에서 관련 케이블을 찾고 선택 중인 재연결을 표시한다. 별도 dock/창을 추가하지 않는다.

실제 화면 검사 후 새 연결 영역은 포트·위치·검색·연결 조작을 위에 고정하고 **결과 목록만** 스크롤하는 방식으로 구체화했다. 목록의 높이는 사용 가능한 영역에서 고정 행 높이를 뺀 값으로 계산한다. 빈 결과도 같은 높이를 유지한다. 작은 창/그룹 진입에서 목록 아래의 조작이 표시되지 않는 문제를 피하도록 결과 목록을 마지막에 배치한다.

## 소유 파일과 검증

- Native Swift utility: `Sources/CirclrApp/PortConnectionsEditor.swift`, `PortKeyboardControls.swift`, 새 `PortTargetList.swift`. Core 명령과 스키마/DSP는 변경하지 않는다. 기존 그룹 포트 관리의 검색/Tab은 기본 동작을 보존한다. keyboard 순서 10 own port → 20 search → 30 results → 40/50 위치 → 60 연결 → 기존 케이블 순서를 유지한다.
- QA utility: `qa/prepare-connection-workspace-qa.py`, `verify-connection-workspace-native.py`, `check-connection-workspace-evidence.py`, `qa/connection-workspace-review.md`. 긴 이름·다수 bus/연결을 포함한 authored fixture 사본과 별도 build 41 앱. 검색/무결과/클릭/위아래/Return, IN 시작·OUT 시작, 재연결/해제/위치·현재 포트 필터, 그룹 관리와 직접 편집 복귀, Undo/저장/재열기. 장치 재생·마이크를 시작하지 않는다.
- `./scripts/swift-local.sh test --scratch-path .build/connection-workspace-quality --skip testArrangementRenderExportAndPlayback`, `python3 -m unittest mcp.test_server qa.test_agent_kit`, release `--scratch-path .build/integration-release`. UI 수정만으로 Core 검사를 추가하지 않으며 Native 시나리오로 실제 동작을 검증한다.
- read-only code/security review 후 필요한 수정만 utility로 수행한다. README/CHANGELOG/roadmap 갱신, 소스·문서·검사 allowlist를 동일 승인된 private `codex/daw-integration` 브랜치에 commit/push한다. 사용자 0.19 앱, 다른 checkout, 음악/미디어/인증/로컬설정은 보존한다. 전체 DAW/실제 출력·입력·VoiceOver 출고 조건은 계속 남는다.

## 결과

최종 build 41 `top` 후보의 Swift 330개·Python 26개, release·codesign·소스/kit hash·Mach-O section 비교가 통과했다. Native에서 검색/선택/양방향 입력·재연결·위치/Undo, 그룹 논리 포트 필터와 콘솔을 접은 확장 영역을 검사했다. 음악과 연결/binding/배치 내용은 r40에서 기준 사본으로 복원하고 재열기 뒤 종료했다. layout revision은 오래된 제스처를 무효화하도록 20으로 증가했다. [후보별 근거와 제한](../qa/connection-workspace-review.md)을 따른다.

다음은 캔버스 자체의 긴 이름/밀집 포트 hit와 실제 file-URL drop 흐름이다. 현재 결과를 VoiceOver·모든 legacy 조합·정상 물리 출력/입력 검증의 대체로 삼지 않는다. 전체 goal은 active를 유지한다.
