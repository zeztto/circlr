# 오디오 작업 공간 검증

2026-09-09 KST, `codex/daw-integration`, 기준 `3d57036`, 0.20.0 build 38. development-lead → UI/UX → native Swift → code/security review → QA를 순차 수행했다. 사용자 요청에 따라 별도 읽기 전용 에이전트를 실제 호출했지만 `agent thread limit reached`가 반환됐다. 독립 에이전트 검토를 수행했다고 주장하지 않는다.

## 결과와 출처

- Swift **325개**, 실패 0, **25.564초**. `./scripts/swift-local.sh test --scratch-path .build/audio-workspace-final-quality --skip testArrangementRenderExportAndPlayback`. 기존 장치 재생 테스트 한 개의 제외 조건을 유지한다. 새 검사는 공유 클립 교체/원자적 거절 2개, 원본 시간 범위/trim 경계 3개, 반올림 표시와 실제 정밀도 보존 1개다.
- Python **26개**, 실패 0: `python3 -m unittest mcp.test_server qa.test_agent_kit`. 최종 release build **50.40초**. 상세 로그는 `qa/generated/audio-workspace/`에 있다.
- 첫 증분 테스트는 `AudioEditing.Change` 변경 후 이전 `AudioClipEditingTests` 호출 오브젝트에서 `AudioEditing.apply` → `outlined init with copy of Project` → `swift_retain`의 SIGSEGV를 냈다. 동일 실행의 새 Core 테스트 11개는 통과했다. 새 scratch에서 전체를 다시 컴파일한 뒤 첫 후보 324개, 최종 후보 325개가 모두 통과했다. 실패 로그를 `targeted.log`에 보존했다. 이 enum의 호출 규약 변경 후 기존 증분 테스트 산출물을 검증 근거로 재사용하지 않는다.
- 최종 앱: `qa/generated/audio-workspace/readable/써클러 통합 검증.app`, UUID **47FB56AB-5943-3CDE-AE1A-13B12D1E7D92**. 첫 후보 UUID **67F48F1D-A504-3306-B245-FA0C0EB77447**도 보존한다. 최종 Mach-O 파일 기반 section **37개**, 소스 hash **8개**, Codex kit hash **25개**, build/version 및 ad-hoc strict codesign을 확인했다.
- `python3 qa/check-audio-workspace-evidence.py` 통과. 최종 결과는 `readable/verification.json`. 이 검사는 해당 로컬 산출물이 있는 실행 이력 검사이며 향후 다른 release 바이너리에 대한 보편적인 CI 검사가 아니다.

## 실제 편집

기존 직접 작성한 2개 검증 톤과 3개 트랙의 사본 `audio-workspace.circlr`, project ID **74FCAE6F-29F8-597B-A5FE-2A095681E4F3**을 사용했다. 최종 앱은 r34에서 시작했다. 작은 창 **1019×768**, 콘솔 열림 상태에서 시행했다. 기본 파형 높이를 늘리고 숫자 표시를 수정한 뒤 아래 전체 경로를 최종 앱에서 다시 검사했다.

| 경로 | 확인한 데이터와 UI |
| --- | --- |
| 작업 이동 → 오디오 | ⌘J의 오디오 버튼이 접힌 그룹을 펼치고 편집기로 바로 진입한다. |
| 순차 입력 r40 | 시작 8초 → 끝 16초 → 분할 2초 → −6 dB → 페이드 100/200 ms → 원본 100 BPM을 Tab/Return으로 입력했다. 실제 gain은 `0.5011872336272722`, fade는 `0.1/0.2` source 초다. 확정 후 파형이 first responder다. |
| 파형 trim r41–42 | Right로 시작 8.01초, 시작 핸들 드래그로 `9.031723049869933`초. 끝은 16초다. 표시 범위는 7.36–16.64초로 고정되고 직접 trim 중 절대 분할 위치 10초가 유지됐다. |
| 정밀도와 Undo | 화면은 9.032초지만 그대로 Return을 눌러도 r42와 전체 manifest가 유지됐다. 한 번 ⌘Z 후 r43에서 시작 8.01초로 복원됐다. 분할 커서는 임시 view state라 Undo 이력에 포함되지 않으며, Undo에서는 기존 상대 offset이 유지된다. |
| 궤도와 템포 r44 | 템포 추종을 켜고 그리드 메뉴로 궤도 전환. editorFrame과 7.36–16.64초 범위가 유지됐다. 원본 7.990초·재생 6.658초를 표시했다. 바깥 궤도는 섹션 내 첫 재생, 안쪽은 원본 초 범위다. |
| 궤도 trim r45 | 끝 핸들을 드래그해 source 끝 `14.992094858761898`초, 길이 `6.982094858761899`초. 시작 8.01초와 표시 범위는 유지됐다. |
| 오류와 충돌 | 페이드 인 9000 ms에서 Tab을 눌러도 r45가 유지되며 ms 범위 오류와 해당 필드 포커스를 표시했다. 볼륨 −9 dB 작성 중 MCP가 페이드를 0.3/0.4초로 변경한 r46에서 Return은 충돌로 거절됐다. Esc 후 gain은 −6 dB다. |
| 분할·복제 r47–48 | 분할 위치 2초 확정 후 ⌘T. 앞 길이 2초, 뒤 source 시작 10.01초. 두 조각의 renderWindow와 기존 페이드를 유지했다. ⌘D는 뒤 조각의 실제 재생 끝에 새 ID로 복제했다. |
| 바운스·원본 복원 r49–50 | 편집기 위 트랙 바운스 버튼으로 34초 파일을 생성했다. 원본 복원 버튼은 기존 음악 경로를 복구하고 바운스 서클을 음소거·출력 분리했다. |
| 저장·재열기 r66 | 모든 검사 편집을 Undo하고 저장했다. global/tracks/sections/arrangements/assets/patterns/portLayout/circleLayout이 최초 baseline과 동일하다. 같은 파일을 재열고 다시 저장했으며 두 검증 앱을 정상 종료했다. |

직접 편집 중 원본 섹션, 두 번째 공유 사용, MIDI notes/addedLanes, 다른 자산·트랙은 그대로다. 동일 클립을 가리키는 두 노드 중 선택한 노드만 새 clip ID를 받는 것은 Core 테스트에서 확인했다. 실제 앱에 인위적인 alias를 추가해 검사하지는 않았다.

바운스는 **48 kHz·24-bit·stereo, 1,632,000 frames, 34초**, peak **0.02034783**, RMS **0.00421384**, nonzero sample **489,886개**다. 검증 톤의 낮은 레벨이며 발매 음악의 음질 평가가 아니다. 실제 WAV와 hash/PCM 검사는 로컬 `bounce.wav`, `bounce-asset.json`, `bounce-pcm.json`으로 보존한다. 원본 `studio.circlr/manifest.json` SHA-256 **12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d**와 두 원본 오디오 checksum도 유지됐다.

## 화면·남은 범위

최종 12개 screenshot은 실제 JPEG byte 그대로 `.jpg`로 보존했다. `final-ordered-input.jpg`, `final-orbit.jpg`, `final-invalid-tab.jpg`, `final-bounce.jpg` 등을 확인한다. 숫자 초는 소수 3자리, ms는 1자리로 읽히며 원본 정밀도를 변경하지 않는다. 파형 선택 구간 버튼을 위로 이동해 작은 창에서도 원형 파형과 양쪽 속성을 함께 표시한다. 별도 창/dock는 만들지 않았다.

포인터를 누른 채 MCP를 보내는 중간 드래그 경쟁, VoiceOver 실사용, 모든 긴 파일/이름/최소 높이 조합은 미검증이다. 드래그에는 프로젝트·세션·revision·대상·clip/asset·viewport·layout·bounds·disabled guard가 있다. 화면 밖 선택 안내와 작은 원본/짧은 클립 경계는 Core 검사 및 코드 검토 범위다. 숫자·드래그·키보드 외 legacy `AudioLane`/이전 `AudioTrimView` 전체 재설계는 이번 범위가 아니다.

이번 실행의 출력 장치 획득 시도는 **0회**이며 실제 재생·마이크·MIDI 장치·MP4 재생 회귀를 시작하지 않았다. 기존 HAL 획득 지연과 사용자 앱 출고 조건은 유지한다. 전체 DAW·아티스트 세계관 목표는 진행 중이며, 다음 UI 범위는 선택 전후 위치 변화, 전역/전환/legacy 편집 경로, 밀집 음명·연결의 접근성이다.
