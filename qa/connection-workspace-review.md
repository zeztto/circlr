# build 41 연결 작업 공간 검증

2026-09-09, `codex/daw-integration`, 기준 `0e0092b`. development-lead → UI/UX → native Swift utility → read-only code/security review → QA 순서로 수행했다. 독립 audit 요청은 `agent thread limit reached`로 실패했다. 동일 실행자의 역할 전환 검토이며 독립 검토로 주장하지 않는다.

## 결과

대상 포트를 별도 메뉴 대신 두 줄 검색 목록에서 직접 고른다. 검색창의 ↑↓는 결과를 선택하고 Return은 선택한 대상만 연결한다. 목록 클릭·Tab 이동·Return도 지원한다. 원래 포트와 양 끝 위치, 검색·연결 버튼을 목록 위에 고정하고 남은 높이를 결과 목록에 할당한다. 케이블 목록은 따로 스크롤하며 전체/현재 포트를 필터링한다. 기존 케이블의 재연결·해제·양 끝 8방향 위치는 같은 행에서 조작한다.

긴 이름은 표시와 포트 이름을 구분하고 전체 이름을 AX/도움말로 제공한다. 화면에 생략된 상속 리듬도 저장된 실제 이름으로 표시한다. 별도 창/dock·스키마·DSP·Core 연결 명령은 추가하거나 변경하지 않았다.

## 빌드와 패키지

- 최종 Swift **330개 / 0 failures**, 23.372초. `./scripts/swift-local.sh test --scratch-path .build/connection-workspace-quality --skip testArrangementRenderExportAndPlayback`. 장치 재생 한 항목을 제외했다. UI 변경의 실제 입력은 Native 시나리오로 검사했다.
- Python **26개** 통과: `python3 -m unittest mcp.test_server qa.test_agent_kit`. 최종 release **23.84초**. [Swift](generated/connection-workspace/swift-tests-final.log), [Python](generated/connection-workspace/python-tests.log), [release](generated/connection-workspace/release-final.log).
- 최종 후보 `top/써클러 통합 검증.app`, bundle `com.circlr.integrationqa`, 0.20.0 build 41. UUID **C11F8B4E-E041-317C-B0B1-C3D0556D22BA**. ad-hoc codesign strict, 소스 4개·Codex kit 25개 hash, 빌드와 패키지의 Mach-O file-backed section 37개 일치.
- [증거 검사기](check-connection-workspace-evidence.py) 통과. [검사 결과](generated/connection-workspace/top/verification.json)에 최종 JPEG 7개(1019×768)의 hash와 범위가 있다. 이미지 무결성 검사는 화면 동작 판정 자체를 대신하지 않는다.

## Native 근거

직접 작성한 톤/MIDI fixture 사본에 긴 이름의 mix bus 8개와 6개 케이블을 추가했다. 초기 선택 악기는 연결 9개, 대상 13개다. 실제 사용자 곡·Splice 미디어를 변경하지 않았다.

| 후보/작업 | 실제 결과 |
|---|---|
| compact 검색·선택 | `07` 검색 후 미선택 Return은 r14 그대로. Down → Tab으로 목록 선택 → Return은 bus 07 케이블 하나를 생성(r15) |
| compact 8방향 | `08` → Down → Tab 목록 → Tab 시작 위치 → Down → Tab 대상 위치 → Down → Tab 연결 → Return. 오른쪽 아래/왼쪽 위(3/7)를 저장(r16) |
| compact 입력 방향 | MIDI 케이블 해제(r17), IN MIDI 포트에서 결과 행 클릭·Return으로 재연결(r18). OUT → IN 정규화와 MIDI signal 보존 |
| compact 재연결/위치 | bus 07의 케이블을 출력 2로 재연결(r19), 기존 ID/gain 유지. 기존 OUT 위치 변경은 음악 r19를 유지하고 배치 revision만 증가. 무결과 검색 Return은 무변경 |
| compact 필터/그룹 | 현재 오디오 OUT 연결 9개, IN MIDI 연결 2개. 그룹 관리의 Tab/Shift-Tab과 연결/편집 복귀 확인. 6 Undo → r24에서 음악·배치 내용 복원 |
| 최종 top 그룹 | r36에서 그룹 노출 OUT → bus 07 연결(r37). 실제 내부 router의 OUT으로 저장. 그룹 전체 4개 중 현재 OUT 포트 필터는 2개만 표시 |
| 최종 top 음악 | 미선택 Return r37 무변경. 음악 OUT → bus 08을 명시적 Tab 순서와 3/7 위치로 연결(r38). 결과 축소/확대·목록 스크롤·무결과에서 위쪽 고정 조작 표시 유지 |
| 최종 top 가독성 | `상속한 MIDI 리듬`의 실제 이름 확인. 콘솔 열림과 접힘에서 위치/검색/연결 버튼 유지, 접으면 목록 높이가 증가. 다른 케이블을 스크롤해도 검색 영역은 고정 |
| 최종 복원 | 2 Undo → r40, layout revision 20. 저장·재열기 후 기준 r14와 음악·포트 연결/binding·배치 내용 일치. 최종 QA 앱 정상 종료 |

복원은 global/tracks/sections/arrangements/assets/patterns/portLayout/circleLayout/signal을 검사했다. portLayout의 revision은 오래된 제스처를 무효화하는 단조 증가 epoch이므로 내용 비교에서 이 숫자만 제외했다. 새 snapshot은 실제 epoch도 기록한다. 화면 선택/camera는 QA 탐색 상태이며 원본 음악 복원 주장에 포함하지 않는다.

원본 `studio.circlr`의 manifest SHA-256 `12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d`와 두 자산의 checksum을 보존했다. 최종 그룹/음악 편집은 기존 MIDI와 공유 두 번째 사용을 바꾸지 않았다.

화면: [최종 그룹](generated/connection-workspace/top-group.jpg), [그룹 포트 필터](generated/connection-workspace/top-group-filtered.jpg), [목록 스크롤](generated/connection-workspace/top-scrolled.jpg), [빈 검색](generated/connection-workspace/top-empty.jpg), [콘솔을 접은 화면](generated/connection-workspace/top-expanded.jpg).

## 발견한 문제와 검토 범위

첫 후보는 목록 때문에 위치 조절까지 전체를 스크롤해야 했다. 고정 영역과 결과 목록을 분리했다. 이후 Native 검사에서 목록 아래의 조작이 간헐적으로 표시되지 않아 여러 후보를 보존하며 확인했다. 높이 고정·레이어 clipping만으로 해결됐다고 보지 않았으며, 최종은 조작을 목록 위에 배치하고 결과 높이를 실제 편집 영역에서 계산한다. 최종 `top`의 그룹/음악 진입·검색/연결·스크롤·콘솔 확장 화면으로 이 구성을 확인했다. 실패 후보의 캡처를 성공 근거로 사용하지 않는다.

QA 도구의 이전 앱 핸들이 첫 후보를 재실행한 한 차례의 충돌을 발견했다. 대상 프로세스를 확인해 중복 앱을 정상 종료하고 후보마다 별도 핸들로 재개했다. 당시 fixture는 r14·clean이었으며 중복 앱은 MCP 연결을 거절했다. 단순 관측 지연을 앱 종료로 오인해 재시작한 것이 아니다.

read-only 검토는 결과 선택/재로딩의 callback 억제, 현재 호환 대상 검증, 그룹 논리 endpoint 필터, 단일 Core mutation과 Undo, 무효 선택/빈 결과·IME 조합 중 Return guard, 기존 그룹 검색 기본값 보존을 확인했다. 최종 변경의 고확신 차단 결함은 찾지 못했다. 실제 한글 IME 조합 입력·VoiceOver 발화·초대형 포트 목록 성능·모든 legacy/좁은 영역 조합은 별도 검사 대상이다. compact의 재연결/해제 시나리오와 최종의 표시/그룹/키보드 시나리오를 구별한다.

모든 snapshot에서 output attempts는 0이며 물리 재생·오디오/MIDI 장치 녹음·MP4를 시작하지 않았다. 사용자 0.19 build 21 앱과 다른 checkout을 보존한다. 이 UI 단계가 전체 DAW와 장치 출고 goal의 완료를 의미하지 않는다.
