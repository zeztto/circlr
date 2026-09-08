# C3b · 연결 키보드와 접근성 검증

검증일: 2026-09-08. 대상은 `codex/eight-direction-ports`의 `b477aaf` 이후 변경이다. 별도 `com.circlr.portsqa` 앱과 허용된 `ports-playback.circlr` 사본만 사용했다. 실제 사용자 프로젝트·설치 앱·녹음 branch를 수정하지 않았다.

## 계약과 변경

- 캔버스 K/Shift K: 케이블 순환. P/Shift P: 선택 서클의 논리 포트 순환.
- 케이블 Tab: OUT/IN 끝점 선택. 좌우: 선택 끝점의 8방향 위치 변경. 상하: 케이블 순환. 위치 변경은 음악 revision을 유지하며 한 번의 Undo로 복원한다. 위치 키의 repeat 이벤트는 추가 편집을 만들지 않는다.
- Return/L: 정확한 케이블 또는 포트를 미리 지정한 같은 캔버스의 연결 편집기. Delete: 선택 케이블 해제. 포트 선택 상태에서 Delete는 서클을 삭제하지 않는다. Esc: 선택 해제.
- 편집기의 자체 Tab 순서는 검색 → 대상 → 시작 위치 → 대상 위치 → 적용이다. Shift Tab으로 역순 이동한다. macOS의 전체 Keyboard navigation 설정을 바꾸지 않는다. 팝업은 닫힌 상태에서 위아래 키로 값을 바로 바꿀 수 있다. 텍스트 입력은 캔버스 K/P 단축키로 처리하지 않는다.
- 포트의 8개 표시 위치를 하나의 논리 포트 AX 항목으로 제공한다. 케이블에는 실제 출발·도착 포트 이름과 선택 상태를 제공하며 접근성 객체를 재사용한다. 가려진 표시의 AX 노출을 제한한다. 실제 VoiceOver 발화는 검증하지 않았다.

## Native 근거

모든 원본은 Git에서 제외한 `qa/generated/ports-ui/`에 보관한다. 아래 이름은 JSON이며 `*-focus`와 `*-cycle`은 CUA 접근성 상태 기록이다. MCP snapshot·저장 manifest·effective graph를 실제 조작 전후 대조했다.

| 시나리오 | 근거 | 결과 |
|---|---|---|
| 케이블 K/Shift K 순회 | `c3b-key-cycle` | 네 연결 순서·역순·되돌아오기 확인 |
| IN 끝점 키보드 위치·한 Undo | `c3b-cycle-base`, `c3b-input-key-move`, `c3b-key-move-undo` | 음악 r1 유지, 배치 r0→1→2, 원래 위치 복원 |
| 키보드만으로 재연결·한 Undo | `c3b-keyboard-reconnect-base`, `-applied`, `-undo`, `c3b-arrow-focus` | 음악 r1→2→3, 같은 edge ID의 target만 변경, 원래 graph 완전 일치 |
| 네 논리 포트 순회·정확한 OUT 1 prefill | `c3b-port-cycle` | IN 1→IN 2→OUT 1→OUT 2, Shift P 역순 확인 |
| 포트 선택 중 Delete 보호 | `c3b-port-delete-protection` | 음악 r3·graph 유지 |
| 케이블 Delete·한 Undo | `c3b-cable-delete-base`, `c3b-cable-deleted`, `c3b-cable-delete-undo` | 음악 r3→4→5, 선택 edge 하나만 제거 후 ID 포함 복원 |
| OUT/IN 각각 8방향 | `c3b-16-key-octants`, `c3b-16-key-octants-state` | 실제 방향키 16회, 음악 r5·graph 유지, 배치 r2→18 |
| 마우스로 OUT 잡기·Undo | `c3b-final-pointer-end`, `c3b-final-pointer-undo` | IN 선택 상태에서 OUT을 잡으면 선택도 OUT으로 이동, 방향·Undo 일치, 음악 r5 유지 |
| 같은 파일 재열기 | `c3b-before-reopen`, `c3b-after-reopen` | editor intent·케이블·포트 선택 제거, graph 유지 |
| 좁아진 세로 작업 공간 | `c3b-small-editor` 및 PNG, `c3b-final-editor.png` | canvas 1080×673, editor 1019.616×537, 적용 버튼·목록 스크롤 확인. 최소 1024 너비 전체 검증은 아님 |

`c3b-native-assertions.json`은 실제 저장 증거의 ID·graph·음악 revision·배치 revision 비교가 통과한 결과다. 리비전이 증가하더라도 마지막 음악 내용은 원래 네 연결과 같다.

## 발견 및 수정

1. macOS의 일반 키보드 탐색 설정에서 SwiftUI 메뉴·버튼을 Tab으로 건너뛰었다. 연결 편집기 범위의 AppKit 컨트롤과 지역 key loop로 수정했다.
2. 도구의 native popup 메뉴 화살표 입력으로는 대상 변경이 안정적으로 관측되지 않았다. 닫힌 팝업에서 위아래 키로 직접 선택하는 경로를 구현하고 실제 재연결까지 검증했다. 팝업 메뉴 자체의 화살표 탐색을 통과했다고 주장하지 않는다.
3. 서클 내용 변경 시 더 이상 존재하지 않는 포트 선택을 제거하고 AX press에서도 현재 포트 존재를 검사한다. 마우스로 잡은 OUT/IN을 키보드의 현재 끝점과 일치시킨다.
4. 연결 편집기 재생성 시 초기 검색 포커스가 빠졌다. 임시 전환 기록에서 field editor가 생긴 뒤에도 확대 중 레이아웃이 바뀌는 상황을 확인했다. 창 부착·크기·field editor 준비를 검사하고 카메라 이동 완료 시점에 대기 중인 포커스를 처리한다. 상위 이름 필드도 불필요한 false FocusState 쓰기를 피한다. 수정 후 최초 열기 및 연속 3회 재열기의 검색 포커스와 뒤이은 Tab·대상 방향키 이동이 통과했다(`c3b-camera-focus`, `c3b-camera-focus-trace`). 임시 추적 코드는 제품 소스에서 제거했다.

## 검증 범위와 남은 작업

최종 소스 검증은 Swift **190개, 실패 0, 19.775초**(`ports-c3b-verified-tests.log`)와 warning 없는 release **22.30초**(`ports-c3b-verified-build.log`)다. 로그는 `qa/generated/ports-foundation/`에 있다. QA 앱 서명 검증이 통과했으며 실행 파일 UUID는 **433E9981-AB97-3A50-BCA0-4AEA0F4700C7**이다.

최종 실행 파일에서도 최초+연속 재열기 **4회**의 검색 포커스(`c3b-verified-focus`), K/P 검색 텍스트 입력, 대상 방향키 선택, 키보드 재연결·Undo(`c3b-verified-reconnect-base/applied/undo`)를 확인했다. 음악 r5→6→7이며 source 1의 같은 edge ID에서 `toPortID`만 IN 1→IN 2로 바뀌었다가 원래 graph로 복원됐다. `c3b-verified-assertions`에 비교 결과를 보관한다. `c3b-verified-ax.txt`는 라우터의 네 논리 포트가 각각 한 번, 선택 포트가 하나만 노출됨을 확인한 기록이다. 최종 상태는 `c3b-verified-final`, 화면은 `c3b-verified-editor.png`와 `c3b-verified-port-canvas.png`다.

앞 표의 전체 16방향·첫 재연결/삭제는 UUID **BD038C20-DAEC-37A3-B79B-66F0EB567ADA**, 포인터 끝점·재열기는 **0D7E4DF0-0FFE-3521-B6F4-8822898FB772**에서 확인했다. 이후 변경은 검색 포커스 수명 주기와 임시 추적 제거이며 위 최종 실행 검증으로 구분했다. 해당 중간 빌드의 전체 매트릭스를 최종 바이너리에서 전부 다시 실행했다고 주장하지 않는다.

기존 설치 앱은 **0.19.0 / build 21**, UUID **96FDDF3A-D327-3708-80BF-CCF68B31B6F1**을 유지한다. 녹음 작업 디렉터리는 `d88ea5d`에서 clean인 것을 재확인했다. 새 source checkpoint는 비공개 개발 브랜치에만 저장한다.

Core·audio·MCP 쓰기 계약은 변경하지 않았다. 전체 Swift 검사는 `swift test --scratch-path .build/ports-quality --skip testArrangementRenderExportAndPlayback`, release는 `swift build -c release --scratch-path .build/ports-release`를 사용한다. 실제 장치 재생에 의존하는 단일 검사는 기존대로 제외하며, 이번 UI 검사를 실시간 오디오·청감 검증으로 해석하지 않는다.

역할은 development-lead/UX 계약 → native Swift utility → read-only 코드 검토 → native QA로 전환했다. 사용자의 요청에 따라 서브 에이전트를 다시 요청했으나 런타임이 `agent thread limit reached`로 거절했다. 독립 에이전트 리뷰는 수행되지 않았다.

VoiceOver 실제 발화, 모든 신호 종류·접힌 그룹·밀집 배치의 포인터 조합, 최소 너비·시간 손잡이 간섭 전체 행렬은 남아 있다. 다음 D의 typed-port MCP/배치 revision·group binding, E의 녹음 branch 통합·회귀 검증을 마친 뒤 사용 앱 출고를 결정한다. C3 전체 완료나 제품 release를 의미하지 않는다.
