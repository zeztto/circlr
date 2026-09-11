# 편집 위치와 작업 전환 검증

2026-09-09 KST, `codex/daw-integration`, 기준 `95a492b`, 0.20.0 build 39. development-lead → UI/UX → native Swift → read-only code/security review → QA 순차 수행. 사용자의 한도 해제 안내 후 독립 코드 검토 에이전트를 다시 요청했으나 호스트가 `agent thread limit reached`로 거절했다. 독립 에이전트 검토나 병렬 구현을 수행했다고 주장하지 않는다.

## 결과와 후보 경계

- 최종 소스의 Swift **325개**, 실패 0, **23.862초**: `./scripts/swift-local.sh test --scratch-path .build/audio-workspace-final-quality --skip testArrangementRenderExportAndPlayback`. 실제 장치 재생 테스트 한 개의 기존 제외 조건을 유지한다. 이번 UI 변경을 복제한 단위 테스트를 추가하지 않고 기존 회귀 검사와 실제 앱의 동작을 확인했다.
- Python **26개**, 실패 0: `python3 -m unittest mcp.test_server qa.test_agent_kit`. 최종 release build **23.20초**. 로그는 `qa/generated/editor-shell/`의 `swift-tests-reviewed.log`, `python-tests.log`, `release-reviewed.log`다.
- 첫 후보는 고정된 본문 높이 때문에 오디오 아래쪽 조작이 잘렸다. 오디오 속성을 내부 스크롤로 바꾸고 음소거/삭제를 파일 이름 줄로 옮겼다. MIDI 속성·궤도 탐색과 궤도 오토메이션의 긴 열도 본문 안에서 스크롤한다.
- `compact` 후보 UUID **884F6818-B79B-34BD-8AE9-9BC77E1F25F4**에서 전체 선택·레이아웃·입력 경로를 검사했다. 이후 코드 검토로 헤더 두 곳만 수정했다. 그룹 도움말의 ‘편집 편집’ 중복을 없앴고, 설정 전환이 열린 플러그인 편집기를 정리하게 했다. 나머지 일곱 제품 파일 hash는 같다.
- 최종 앱은 `qa/generated/editor-shell/reviewed/써클러 통합 검증.app`, UUID **9AA1B33E-3FB9-3596-AF80-D7C3EAB1D223**. 최종 앱에서도 MIDI/오디오 연속 입력·오토메이션·설정/연결/그룹 왕복·저장 복원을 다시 검사했다. 실제 Audio Unit 편집기를 연 상태의 전환은 코드 검토 범위이며 native 실행 검증으로 표현하지 않는다.
- `python3 qa/check-editor-shell-evidence.py` 통과. 최종 Mach-O 파일 기반 section **37개**, 소스 hash **8개**, Codex kit hash **25개**, version/build와 strict ad-hoc codesign을 확인했다. 결과는 `reviewed/verification.json`이다. 이 검사는 해당 로컬 기록을 검증하며 다른 바이너리의 보편적인 CI UI 테스트는 아니다.

## 실제 화면과 데이터

직접 작성한 검증 톤 두 개와 트랙 세 개를 복사한 `editor-shell.circlr`, project ID **4256ADCF-8FDE-5470-9E33-4F5DC174AD16**을 사용했다. screenshot은 **1019×768**, canvas **1024×673**이다. 다음 경로에서 제목과 트랙 경로의 위치를 실제 이미지로 대조했다.

| 경로 | 근거와 결과 |
| --- | --- |
| 피아노 선택 없음/한 개/세 개 | 제목·경로·격자 시작 위치가 유지된다. 한 노트의 음높이/시작/길이/세기와 다중 선택의 복제/삭제가 본문 안에 표시된다. `final-piano-unselected`, `final-piano-selected`, `final-multi-selected`. |
| 숫자 → 키보드 | `compact` r19에서 67/1박/1박/90을 Tab/Return으로 확정하고 피아노 롤 포커스로 복귀했다. Right로 1.25박 이동, Undo로 1박 복원 후 r21에서 스텝으로 전환했다. 최종 앱에서도 같은 네 항목을 r45에 입력했다. |
| 스텝·궤도 | 세 노트 선택과 작업 전환을 유지한다. 궤도에서 다음 노트로 단일 선택, 왼쪽 스크롤로 하단 명령 접근을 확인했다. `final-step`, `final-step-returned`, `final-orbit-multi`, `final-orbit-selected`, `final-orbit-scroll`. |
| 설정·연결·콘텐츠 | 현재 버튼이 selected 상태이고 한 번의 클릭으로 해당 본문을 연다. 연결 검색이 포커스를 받고 MIDI/오디오 복귀 시 해당 편집기로 돌아간다. 궤도·스텝·피아노에서 확인했다. |
| 오디오 입력 | 시작 1초 → 끝 8초 → 분할 2초 → −3 dB → 페이드 100/200 ms → 원본 100 BPM을 연속 입력했다. 실제 gain `0.7079457843841379`, source duration 7초, fade 0.1/0.2초다. `compact` r27, 최종 r51. Return 뒤 각각 궤도/파형 편집기가 first responder다. |
| 오토메이션 | 오디오에서 바로 열고 Return으로 gain 1/0박의 선형 점을 추가했다. 속성 표시 전후 제목·경로가 유지된다. 궤도는 `compact` r28, 자유 배치는 최종 r52에서 확인했다. 오디오로 돌아가도 편집한 clip을 유지한다. |
| 콘솔 접기 | 같은 편집기의 상단/가로 크기를 유지하며 본문 높이가 370.5→537pt로 늘었다. 작은 창에서도 오디오 하단 안내가 보인다. 콘솔을 다시 펼쳤다. |
| 출력·그룹 | 출력 레벨 화면의 읽기·스크롤 배치를 확인했다. 그룹 편집→연결→편집은 같은 그룹 편집을 유지한다. 최종 `reviewed-group-returned`에서 중복 없는 도움말도 확인했다. |
| 저장·재열기 | `compact`의 검사 편집을 r41에 복원하고 정상 종료했다. 최종 앱에서 재열어 검사한 뒤 r64에 Undo·저장, 같은 문서를 재열고 다시 저장했다. 모든 QA 앱을 정상 종료했다. |

편집기 프레임은 MIDI·스텝·궤도·오디오·오토메이션·그룹에서 약 `[29.856, 78, 964.288, 370.5]`pt다. 원시 Float 값의 차이가 약 1e-13pt여서 기록 검사는 절대 오차 1e-8pt로 비교한다. 스크린샷 대조가 내부 제목/본문의 위치 검증이고, 프레임 값만으로 내부 배치까지 검증했다고 주장하지 않는다.

`compact`의 `final-*.jpg` **28개**, 최종의 `reviewed-*.jpg` **14개**를 실제 JPEG byte로 보존했고 크기/hash를 기록했다. 첫 후보의 잘린 화면은 비교 근거로 별도 보존하며 최종 후보의 성공 근거로 사용하지 않는다.

## 복원·검토·남은 범위

최초 r14와 최종 r64의 **global/tracks/sections/arrangements/assets/patterns/portLayout/circleLayout**이 같다. MIDI 편집은 첫 노트만, 오디오 편집은 첫 사용의 해당 clip만 변경했다. 원본 섹션·다른 노트·두 번째 공유 사용·트랙·자산은 보존했다. 오토메이션은 선택 오디오 노드의 gain lane에 점 하나만 추가했다. 원본 `studio.circlr/manifest.json` SHA-256 **12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d**와 두 오디오 checksum도 같다.

코드 검토에서 설정 본문보다 플러그인 본문의 우선순위가 높다는 점을 확인해 `embeddedPlugin=nil`을 추가했다. 음악 모델·MCP 쓰기 계약·권한·파일 I/O·자격 증명 경로 변경은 없다. 공통 숫자 identity/focus guard, MIDI import 초안 중 헤더 비활성, 테이크의 use/track/lane 필터를 유지한다. 수정을 마친 diff에서 추가로 확신할 수 있는 버그는 발견하지 못했다.

물리 출력 획득 시도 **0회**다. 실제 재생·마이크/MIDI 장치·MP4·VoiceOver, 녹음 중 상태 줄과 테이크 메뉴가 동시에 있는 작은 창, 실제 Audio Unit 창의 전환, 모든 긴 이름/밀집 UI 조합은 미검증이다. 기존 HAL 출력 획득 지연 및 사용자 0.19 앱의 출고 조건은 유지한다. 전역/섹션 전환 효과·legacy 입력 정리와 밀집 음명 가독성이 다음 UI 범위이며 전체 DAW·아티스트 목표는 진행 중이다.
