# 스텝·피아노 롤 작업 공간 검증

2026-09-09, `codex/daw-integration`, 기준 `4d397fd`, 0.20.0 build 37. [실행 계약](../docs/51-midi-grid-workspace.md). 실제 root 포함 1슬롯에서 UI/UX → native Swift utility → 읽기 전용 code/security review → QA를 순차 수행했다. 독립 에이전트 리뷰로 계산하지 않는다.

## 결과와 검사

스텝/피아노 롤 아래에 쌓인 속성을 같은 캔버스 오른쪽으로 옮겼다. 세 MIDI 편집기가 공통 수치·일괄 편집을 사용한다. 스텝의 번호와 피아노 롤의 박/음높이 눈금은 스크롤 중에도 보인다. 선택 노트의 실제 페이지·음역·위치를 따라가며 입력 확정 후 해당 편집기에서 키보드 작업을 이어간다. 최종 1019×768 캡처·콘솔 열림·선택 상태에서 스텝 약 6개 행, 피아노 롤 약 9개 행의 라벨과 눈금을 확인했다. 모든 창 크기에 대한 보장은 아니다.

- Targeted StepEditingTests **6개**, 실패 0, **0.002초**. 새 onset 주소 검사는 여섯 분할에서 오프그리드, epsilon 경계, 마지막 부분 페이지와 잘못된 beat를 기존 contains 계약에 대조한다.
- 최종 소스 offline Swift **319개**, 실패 0, **24.078초**: `./scripts/swift-local.sh test --scratch-path .build/integration-quality --skip testArrangementRenderExportAndPlayback`. 이전 HAL 지연의 물리 출력 검사 한 개는 제외했다.
- Python **26개**, 실패 0, **0.215초**: `python3 -m unittest mcp.test_server qa.test_agent_kit`. MCP/kit 구현은 유지했다.
- 최종 release **24.96초**, warning/error 없음. 최종 header 소스로 전체 Swift 검사와 release를 수행했고 이후 제품 소스는 바꾸지 않았다.
- `python3 qa/check-midi-grid-workspace-evidence.py`: 실제 노트 값·스텝 입력/Undo·Tab/포커스·충돌·복원, 원본/asset checksum, Mach-O **37개** 영역, 소스 해시 **10개**, 내장 kit **25개**, codesign strict 통과. 핵심 screenshot의 JPEG 형식·크기·SHA-256도 기록했다.

## 후보와 실제 시나리오

검증 프로젝트 `midi-grid-workspace.circlr`, ID **2288FBF7-9BA4-5C8B-A750-6370E99FC2F4**. 기존 authored tone fixture의 별도 사본에서 MIDI lane 3개 노트를 사용했다. 스텝 Return은 음악 데이터만 편집하는 경로이며 피아노 키 audition·새 피아노 노트 입력·물리 출력·마이크는 시작하지 않았다.

| 후보 | 관측과 처리 |
|---|---|
| 최초, UUID `1745D0DD-E221-38C5-9E26-61BEB5ABEBCB` | r14에서 기존 66번 노트를 Down 7회로 선택. 수치 음높이 65 Tab(r15)이 페이지 1로 이동했고 행 스크롤 시 번호도 사라졌다. 별도 속성 Tab 그룹·고정 스텝 번호를 추가했다. 음악을 r16에서 최초 복원하고 정상 종료. |
| focused, UUID `34F8CC52-AEEA-3375-BC4F-BD2E01917D49` | r16→20, 음높이 65 Tab → 시작 41 Tab → 길이 1.25 Tab → 세기 88 Return. 페이지 11·165번 셀·65번 행을 표시하고 스텝으로 포커스 복귀. |
| focused 스텝 입력 | Return r21은 그 기존 노트만 제거, Cmd-Z r22 복원. Right→Return r23은 41.25박·65번·길이 0.225·세기 96의 새 노트 하나만 추가. Cmd-Z r24에서 복원. |
| focused 탐색 | 드럼 모드에서 MIDI 36 행 추가, 1/8 셋잇단, 페이지 3/12. 피아노 롤 왕복 뒤 드럼/행/분할/페이지 3을 유지. Tab 세 번으로 41박 노트가 보이는 위치로 이동. |
| focused 피아노 | 드래그 r25는 시작 41→39박·음높이 65→66, 끝점 r26은 길이 1.25→1.75. 먼 노트를 따라갈 때 눈금이 사라지는 것을 발견해 위/왼쪽 고정으로 수정했다. r32에서 음악 전체 복원 후 정상 종료. |
| headers 최종, UUID `D2344B09-EF20-382F-BE06-BCD549F484E2` | 스텝 번호가 한 번만 AX에 표시된다. 시작 41 Tab→길이 1.25 Tab→세기 88 Return(r35), 페이지 11로 따라감. 피아노 전환 후 박 32–43과 음높이 눈금·41박 노트가 함께 보인다. |
| 최종 드래그 | r36은 41→39박·66→67, r37은 길이 1.25→1.75. Cmd-Z r38은 길이만 복원, Cmd-Z r39는 이동만 복원. 드래그별 변경 1개. |
| 최종 음역/키보드 | 음높이 36 Return(r40) → Up(r41)로 37. 스크롤된 C♯2 노트와 음높이/박 눈금이 보이며 피아노 롤이 first responder다. |
| 최종 Tab/충돌 | 세기에서 Shift-Tab은 길이로 이동. 길이 2 Tab(r42) 뒤 세기 128 Tab은 범위 오류로 필드에 남고 음악은 세기 88 유지. Esc 후 세기 99 draft 중 MCP transpose(r43)는 음높이만 38로 바꾼다. Return은 stale 오류, Esc는 88 복귀. |
| 최종 궤도 회귀 | 공통 속성을 추출한 궤도로 전환해 같은 38/41/2/88을 표시. Up r44는 39, Cmd-Z r45는 38. 궤도 first responder와 9–12마디 선택 표시 유지. |
| 복원/재열기 | r53에서 global/tracks/sections/arrangements/assets/patterns/portLayout/circleLayout을 최초 r14와 동일하게 복원. 저장 후 재열기도 동일하며 최종 QA 앱 정상 종료. |

최종 앱은 `qa/generated/midi-grid-workspace/headers/써클러 통합 검증.app`. 나머지 두 후보와 각 source-hashes/package, 테스트/빌드 로그도 같은 generated 아래 보존한다. 최신 release가 바뀌면 검사기의 바이너리 대조 대상도 바뀌므로 역사적 증거는 후보 UUID·해시·로그로 구분한다.

CUA screenshot 바이트는 JPEG였다. 처음 사용한 `.png` 확장자 14개를 실제 형식인 `.jpg`로 바꿨고 픽셀 바이트는 그대로 보존했다. 최종 `step-header.jpg`, `piano-pinned.jpg`, `piano-drag.jpg`, `pitch-follow.jpg`, `orbit-shared.jpg`를 확인했다. 최종 후보 시작 시 이전에 저장된 피아노 모드가 열려 `step-axes`라는 첫 캡처는 피아노 화면이다. 이후 스텝을 명시적으로 선택한 `step-header`를 성공 증거로 사용한다.

원본 `studio.circlr` manifest SHA-256 **12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d**와 두 authored asset checksum이 같다. raw 앱·음악·화면은 Git에 포함하지 않는다. 사용자 0.19.0 build 21 앱과 다른 작업 앱은 유지한다.

## 순차 검토와 남은 범위

수치 focus group은 약한 필드 참조와 같은 window 확인을 사용한다. MIDI 속성만 명시 순서를 등록하고 일반 숫자 입력의 기존 AppKit 순서는 유지한다. invalid/stale draft는 음악에 적용하지 않는다. 스텝 cache는 세션·원본·서클을 포함하며 선택 노트 onset과 커서를 동기화한다. 피아노 드래그는 전체 NumberEditIdentity/음역/disabled guard와 실제 변경 비교로 한 번 적용한다. 드래그 중 자동 스크롤을 보류하고 제거된 뷰의 AX 동작을 거절하며 고정 눈금의 scroll observer도 해제한다. 인증·네트워크·새 권한·DSP 변경은 없다.

mouse-down 유지 중 외부 revision 변경, Shift 유지 클릭, 피아노 건반 audition과 제거 시 note-off, 물리 MIDI 장치, 재생 중 번호 강조, 실제 VoiceOver는 native 미검증이다. 관련 guard/연결 검토와 기존 offline 검사를 물리 동작 성공으로 합산하지 않는다. 재생/마이크/MP4/출고 gate와 전체 DAW 로드맵은 그대로 남아 있다.

선택 속성의 최소 높이에 따라 편집 내용의 위/아래 위치가 달라지는 현상, 오디오 속성의 긴 스크롤과 단위, 많은 드럼 행 추가 후 위치 찾기, 궤도 2옥타브 음명 밀집·오토메이션의 길이 밖 눈금은 다음 UI 범위다.
