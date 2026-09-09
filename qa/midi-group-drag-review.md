# MIDI 다중 노트 드래그 검증

2026-09-09 KST, `codex/daw-integration`, 기준 `05ef533`, 0.20.0 build 50. development-lead → UI/UX → native Swift → 읽기 전용 code review → QA를 순차 수행했다. 사용자의 에이전트 한도 해제 안내 뒤 독립 리뷰를 실제 요청했지만 `agent thread limit reached`가 반환됐다. 독립 에이전트 리뷰를 완료한 상태는 아니다.

## 결과와 패키지

- Swift **382개**, 실패 0, **26.215초**. `./scripts/swift-local.sh test --scratch-path .build/automation-time-quality --skip testArrangementRenderExportAndPlayback`. 기존 출력 장치 검사 한 개의 제외 조건을 유지한다. 새 Core 검사 5개는 off-grid 이동·공통 시간/음정 경계·서로 다른 길이·짧은 노트·기존 초과·비선택/오디오/ID/세기 보존·무효 입력을 다룬다.
- Python **26개**, 실패 0, **0.301초**: `python3 -m unittest mcp.test_server qa.test_agent_kit`. 첫 release **52.67초**, 선택 안내 수정 **25.47초**, 최종 AX 숫자 정리 **25.81초**. Core/Python은 검사 이후 변경되지 않았고 App의 후속 수정은 release와 최종 native 검사로 확인했다.
- 최종 앱: `qa/generated/midi-group-drag/final/써클러 통합 검증.app`, UUID **097CAA66-1E20-37B1-BC30-45DFCEDABA30**. Mach-O file section **37개**, 소스 hash **10개**, Codex kit **25개**, build/version과 strict ad-hoc codesign 일치를 확인했다.
- `python3 qa/check-midi-group-drag-evidence.py` 통과. 최종 snapshot **11개**, AX **20개**, JPEG **20개**를 기록했다. 이 helper는 이번 로컬 산출물을 확인하며 다른 release 바이너리의 CI 검사를 대신하지 않는다.

## 실제 조작과 음악 데이터

직접 작성한 tone 2개·트랙 3개의 전용 QA 사본 `midi-group-drag.circlr`를 사용했다. project ID는 **A7944C14-2ED3-5278-8FBD-99A6BD043A3B**다. 창은 **1019×768**, 콘솔을 연 상태다. 선택 노트 3개는 `(시작 박, 길이 박, MIDI 음정)` 기준 `(0.13, 0.5, 60)`, `(1.13, 0.75, 64)`, `(2.13, 0.25, 67)`이다. 선택 후 비선택 `(8.25, 1, 62)`를 MCP로 추가했다. 실제 입력은 노트 본문/끝과 기존 단축키를 사용했고 빈 공간 입력이나 audition을 시작하지 않았다.

| 검사 | 최종 앱 결과 |
| --- | --- |
| 피아노 롤 본문 | `(119,462)→(167,422)` 드래그로 선택 전체 +1박/+2반음, r24→25. 화면 밖 G4도 A4로 바뀌고 비선택 D4는 그대로다. 세 노트의 간격과 세기/ID/길이를 유지한다. |
| 피아노 롤 끝 | `(179,422)→(191,422)`로 세 길이가 각각 +0.25박, r26. Cmd-Z 한 번으로 길이 r27, 한 번 더로 이동 r28을 복원한다. |
| 시작 경계·클릭 | `(119,462)→(71,462)`로 시작이 0/1/2박에 함께 제한된다, r29. 경계에서 AX는 긴 부동소수점 잔여값 대신 1박을 읽는다. Undo r30 뒤 본문 클릭만 하면 선택 3개·음악·revision을 유지한다. |
| 궤도 본문 | 한 마디 표시에서 `(521,344)→(556,372)`로 선택 전체 +0.5박/+2반음, r31. 시간 밖 비선택 노트와 음역 밖으로 나간 선택 A4를 데이터로 확인했다. |
| 궤도 끝 | `(558,402)→(549,424)`로 세 길이 +0.25박, r32. 각각 한 번 Undo하여 길이 r33, 이동 r34를 복원했다. |
| 키보드 공통 경계 | 원래 길이에서 Shift-Left는 가장 짧은 0.25박 노트 때문에 전체를 유지하고 r34도 그대로다. Shift-Right는 세 길이를 +0.25박/r35로 만들고 한 번 Undo/r36으로 복원했다. |
| 단독 선택 | 배치 Undo/r37로 피아노 롤에 돌아왔다. 비선택 노트 본문 `(513,422)→(561,402)`는 해당 노트만 +1박/+1반음으로 바꾸고 선택을 1개로 만든다, r38. 다른 세 노트는 그대로이며 한 번 Undo/r39로 복원했다. |
| 저장·재열기 | 비선택 추가를 Undo/r40하고 작성된 원래 MIDI 3개를 MCP로 복원/r41했다. 저장·재열기 후 이름/global/tracks/sections/arrangements/assets/patterns/signal/portLayout/circleLayout이 최초 baseline과 일치한다. portLayout revision만 비교에서 제외했다. |

첫 후보 UUID **CBEB62EA-6565-399C-A242-EEF9FD1F9068**에서도 피아노 롤의 이동/길이/경계/Undo를 확인했다. 경계 이동 뒤 AX가 `0.9999999999999999`를 그대로 읽어 최대 세 자리 소수로 표시하도록 수정했다. 음악 정밀도는 유지한다. 첫 후보는 추가한 네 번째 노트를 실제 Undo하고 저장·정상 종료했다. 최종 후보는 해당 r23 사본을 열어 선택 3개와 비선택 추가를 다시 구성하고 위 전체 경로를 수행했다. fixture를 오프라인으로 덮어쓰지 않았다.

## 검토·보존·남은 범위

읽기 전용 diff 검토에서 Core의 단일 원본 기준 delta, 공통 clamp, lane 단위 한 번 적용, 선택 anchor 복원, full identity·layout·viewport/frame·grid guard와 AX 객체 수명을 확인했다. 차단할 추가 결함은 찾지 못했다. CUA가 mouse-down 중간에 다른 작업을 주입하는 API를 제공하지 않아 드래그 도중 외부 revision/선택/창 크기 변경, Shift를 누른 실제 클릭, 오래된 AX 객체 재호출은 native 미검증이다. VoiceOver 발화와 trackpad 손 감각도 확인하지 않았다.

원본 `studio.circlr/manifest.json` SHA-256 **12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d**, 두 tone checksum, root `d88ea5d`, ports `1d304eb`, 사용자 앱 **0.19.0 build 21**을 보존했다. 이번 QA 앱 두 개는 정상 종료했다. 원시 프로젝트·음악·앱·화면은 Git 업로드에서 제외한다.

출력/audition 장치 획득 시도는 **0회**다. 실제 마이크/MIDI 입력·재생·MP4를 이번 MIDI 편집 QA에서 실행하지 않았다. 기존 HAL 출력 지연 및 사용 앱 출고 조건, CC/페달/피치 벤드·고급 연주 편집과 전체 아티스트 도구 목표는 남아 있다.
