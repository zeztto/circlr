# MIDI 궤도 작업 공간 검증

2026-09-09, `codex/daw-integration`, 기준 `fedbd5a`, 0.20.0 build 36. [실행 계약](../docs/50-midi-orbit-workspace.md).

서브 에이전트 읽기 전용 검토를 요청했으나 실제 도구가 `agent thread limit reached`를 반환했다. development-lead → UI/UX → native Swift utility → 읽기 전용 code/security review → QA로 순차 수행했다. 독립 리뷰나 병렬 에이전트 실행으로 계산하지 않는다.

## 결과와 자동 검사

음역/마디 탐색과 노트 속성을 같은 캔버스에 배치해 작은 창·콘솔 열림에서 궤도의 유효 지름을 약 120 px에서 약 210 px로 확보했다. 두 크기는 해당 검증 창의 screenshot 관찰값이며 모든 창 크기에 대한 비율이 아니다. 기본 4마디·1/2옥타브, 1/2/4/8마디·전체 길이, 노트 탐색, 실제 단위의 선택 속성, 잘린 노트와 실제 끝점을 구분한다. 모델의 노트 시간/길이/정밀도와 공통 키보드 편집은 보존한다.

- 최종 소스 Swift **318개**, 실패 0, **24.010초**: `./scripts/swift-local.sh test --scratch-path .build/integration-quality --skip testArrangementRenderExportAndPlayback`. 이전 HAL 장치 시작 지연에 걸리는 물리 출력 검사 1개는 제외했다.
- 새 Core 검사 **7개**는 로컬 박자별 마디 범위, tempo map 양방향 좌표, clipped endpoint/경계, MIDI 0…127 탐색, 결정적 노트 순서/비변형, 정확히 12개 음높이 맞춤, 현재 페이지에 걸친 긴 노트의 선택 유지를 검사한다.
- Python **26개**, 실패 0, **0.214초**: `python3 -m unittest mcp.test_server qa.test_agent_kit`. MCP/kit 구현은 이번 변경에서 유지했다.
- 최초 release **48.90초** 뒤 native에서 안내 잘림을 발견해 짧은 문구·도움말로 바꾸고, viewport 소유를 Inline 편집기로 이동했다. 순차 검토에서 긴 노트 선택의 시작 페이지 이동을 수정한 최종 release는 **17.69초**, warning/error 없음. 최종 소스로 318개 전체 offline 검사를 다시 수행했다.
- `python3 qa/check-midi-orbit-workspace-evidence.py`: 실제 JSON/AX·노트 값·배치 전환의 선택/편집기 크기·복원·원본/asset checksum, Mach-O **37개** 영역, 소스 해시 **5개**, 내장 kit **25개**, codesign strict 통과.

최종 앱은 `qa/generated/midi-orbit-workspace/compact/써클러 통합 검증.app`, UUID **75D614E5-8BB2-32ED-BCB3-B0BA855C0A66**. 최초 후보 UUID는 **4E1D78BB-D7D5-3CCF-A6B3-4DCCC43B8C3D**이며 같은 generated 폴더 상위에 보존한다. 각 후보의 source-hashes/package와 로그로 구분한다. 최신 release가 바뀌면 검사기의 바이너리 대조 대상도 바뀌므로 역사적 증거는 이 UUID/해시를 사용한다.

## Native 시나리오

프로젝트 ID **5DDA6D8F-E6FF-545A-BB6F-FBE90F904069**, `midi-orbit-workspace.circlr`. 기존 authored tone fixture를 복사한 별도 사본이며 첫 lane의 3개 기존 노트를 편집했다. 새 노트 audition·물리 출력·마이크는 시작하지 않았다.

| 후보/경로 | 실제 관측 |
|---|---|
| 최초, r14–20 | Tab 선택 → 음높이 67 Return → Up 68 → Undo → 시작 1 Tab → 길이 1 Tab → 세기 85 Return. 선택 ID와 다른 두 노트를 보존하고 궤도로 포커스 복귀. |
| 최초, r21–25 | Option-Down으로 세기 80, 실제 끝점 드래그 길이 1→2, Undo 1. 원호 드래그 시작 1→2.75, Undo 1. 드래그마다 한 번의 음악 변경. |
| 최초, r26–27 | 시작 40 입력 후 9–12마디로 이동. 화면 밖 탐색·선택 복귀 확인. 세기 99 입력 중 MCP transpose는 음높이만 68로 변경하고 Return은 stale 오류, Esc는 세기 80 복귀. |
| 최종, r35–39 | 숫자 음높이 67 Return → Up 68, 길이 20 Tab → 세기 90 Return. 모든 필드와 짧은 단축키 안내를 1019×768 screenshot에서 확인. |
| 최종, r39 | 2옥타브·2마디, 3–4마디에서 앞/뒤로 이어지는 20박 노트 선택 해제→재선택. 시작 마디로 뛰지 않고 같은 페이지 유지. Cmd-A는 3개 선택과 일괄 편집만 표시. |
| 최종, r39 전환 | 자유 배치로 전환한 뒤 스텝→궤도 배치→궤도 편집 복귀. 2마디·2옥타브·3–4마디, 같은 노트·selection·editorFrame 유지. 숫자 세기 128은 1–127 오류로 거절하고 Esc로 복귀. |
| 최종, r40–41 | 현재 페이지에서 긴 원호를 드래그해 시작 0→1박, 길이 20·음높이 68·세기 90 유지. Cmd-Z 한 번으로 0박 복원. |
| 최종, r42 | 세기 99 draft 중 MCP가 음높이 68→69 변경. Return 충돌 거절, Esc 뒤 실제 세기 90 유지. 7–8마디에선 0개 표시와 ‘선택 보기’, 누르면 1–2마디로 복귀. |
| 복원/재열기 | 최초 후보 r35와 최종 후보 r50에서 global/tracks/sections/arrangements/assets/patterns/portLayout/circleLayout을 r14와 동일하게 복원. 최종 저장 후 재열기도 동일. 두 QA 앱은 정상 종료. |

최종 배치 왕복의 editorFrame은 `[29.856,78,964.288,370.5]`로 일치했다. 한 번의 메뉴 클릭은 메뉴 상태를 새로 읽기 전에 실행해 전환되지 않았으며 `orbit-return.png`에는 자유 배치가 기록돼 있다. 이후 메뉴 상태를 확인해 다시 선택했고 `range-preserved.png`와 JSON에서 실제 궤도 복귀를 확인했다. 성공 증거에 잘못 이름 붙은 첫 캡처를 사용하지 않는다.

원본 `studio.circlr` manifest SHA-256 **12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d**와 두 authored asset checksum이 같다. `first-restoration-log.json`, `compact/restoration-log.json`, JSON/AX/PNG/앱은 로컬 generated에 보존하고 Git에는 검사 소스·문서만 포함한다. 사용자 0.19.0 build 21 앱과 다른 작업 앱은 유지한다.

## 순차 검토와 남은 범위

검토에서 exact-octave 맞춤이 최저 음높이를 숨기는 경계, clipped 노트 선택이 현재 페이지를 바꾸는 경로를 수정하고 회귀 검사를 추가했다. viewport는 비영속 view state이며 배치/스텝 전환에서만 유지한다. 프로젝트·세션·원본·선택·revision·viewport 변경 시 기존 드래그를 취소하고 숫자 입력은 공통 identity guard를 사용한다. 접근성 노트는 실제 ID·값으로 읽기/선택하며 음악을 생성하지 않는다. 새 권한·인증·네트워크 경로는 없다. QA 파일 경로와 후보 이름은 기존 packager의 고정 fixture·경로 검증·덮어쓰기 거부를 공유한다.

CUA는 mouse-down 유지 중 외부 편집과 Shift 유지 클릭을 제공하지 않아 해당 드래그 경쟁/다중 선택 조합은 소스 연결 검토까지다. 노트별 AX 읽기·선택은 실제 확인했으나 VoiceOver 사용자 탐색 전체를 대체하지 않는다. 일반 짧은 노트 끝점 resize는 최초 후보에서, 최종 후보는 긴 노트 이동/Undo를 확인했다. local tempo/meter 좌표는 Core 검사이며 native tempo 변경 제스처 시험으로 합산하지 않는다.

2옥타브의 내부 음명이 밀집하고 넓은 연주 음역을 한꺼번에 보기는 어렵다. 스텝 두 행·피아노 롤의 화면 밖 선택/전환 포커스, 오디오 속성 스크롤, 오토메이션의 길이 밖 마디 눈금은 다음 UI 범위다. 물리 출력 장치 지연·실제 녹음/재생/MP4·사용자 앱 출고와 전체 DAW 로드맵은 계속 남아 있다.
