# 편집 화면 연속성 검증

2026-09-09, `codex/daw-integration`, 0.20.0 build 35. 기준 `773da53`. [실행 계약](../docs/49-canvas-editing-continuity.md).

실제 root 포함 한 슬롯에서 development-lead → UI/UX → native Swift utility → read-only code/security review → QA로 순차 수행했다. 독립 리뷰로 계산하지 않는다.

## 결과와 자동 검사

배치를 바꿀 때 선택 서클의 화면상 중심과 반경을 보존한다. 같은 scene 갱신 경로가 메뉴·명령·Undo/Redo에 적용된다. 새 프로젝트에는 이전 anchor를 적용하지 않고 기존 viewport 복원을 따른다. 오토메이션 범위는 session 값으로 고정하고 scope 변경 시 reset한다. 겹친 점의 일반 클릭은 선택을 유지하며 Option 클릭은 순환한다. 음악 저장·DSP·ID는 유지한다.

- Targeted Swift **11개**, 전체 offline Swift **311개**, Python **26개** 모두 실패 0. 새 4개 검사는 실제 두 레이아웃의 모든 circle 왕복 중심/반경, 마지막 점 이동/삭제 중 범위 유지, 새 범위 재맞춤과 base 변경, 세 개 hit 순환/선택 유지/없는 점을 검사한다.
- 전체 Swift: `./scripts/swift-local.sh test --scratch-path .build/integration-quality --skip testArrangementRenderExportAndPlayback`, **24.497초**. 실제 출력 장치 의존 검사 한 개는 이전 HAL 지연 때문에 제외했다. Python: `python3 -m unittest mcp.test_server qa.test_agent_kit`, **0.229초**.
- 최종 release **49.84초**, warning/error 없음. 최종 source로 전체 검사와 release를 수행했고 이후 제품 소스 변경은 없다.
- `python3 qa/check-editing-continuity-evidence.py`: native JSON/AX·음악 복원·원본/asset checksum·Mach-O **37개** 영역·소스 해시 **8개**·내장 kit **25개**·codesign strict 통과. 이후 release를 바꾸면 최신 바이너리 대조 대상도 바뀌므로 역사적 증거는 UUID/해시/로그로 식별한다.
- 순차 코드/보안 검토: 카메라의 동일 ID·유한 좌표·유효 반경 검사와 zoom 범위, 동일 프로젝트/배치 변경 guard, 이전 제스처 취소, 기존 명시 명령 우선, 범위의 model-level reset, point ID에 기반한 hit/drag를 확인했다. 인증·권한·DSP·외부 호출은 추가하지 않았다. 기존 QA packager는 NAME/BUILD만 매개변수화해 authored fixture 검사·원본 보존·이전 후보 덮어쓰기 거부를 공유한다.

최종 앱은 `qa/generated/editing-continuity/써클러 통합 검증.app`, UUID **80B8397C-45B3-33A6-B3FB-DEF41397D870**다. native QA 뒤 정상 종료했다. 사용자 0.19.0 build 21 앱과 다른 작업 앱은 유지한다.

## Native 시나리오

검증 프로젝트 `editing-continuity.circlr` ID **F37977C8-9E22-5966-9F37-2ECD1C27A1E5**. 기존 authored tone fixture를 복사해 두 번째 섹션 사용을 추가했다. 원본·사용자 곡·구매 샘플은 수정하지 않았다. 물리 출력·마이크도 시작하지 않았다.

| 경로 | 실제 관측 |
|---|---|
| 메뉴 전환 | r15, 자유→궤도. 선택 qa-start와 오토메이션 표시 상태가 같다. editorFrame은 양쪽 모두 `[29.856,78,964.288,370.5]`. screenshot에서도 같은 외곽 서클과 편집 위치를 확인했다. |
| 겹친 끝점 선택/드래그 | 대괄호로 qa-end(64박)를 선택한 뒤 같은 화면 위치 일반 클릭은 r15와 끝점 선택 유지. 드래그 r16은 끝점만 56박으로 이동하고 시작점은 그대로다. Cmd-Z r17에서 64박 복원. |
| Undo/Redo | 배치 Undo r18은 자유 배치, Redo r19는 궤도. 선택 끝점과 편집기가 유지된다. |
| 명령 검색 | ⇧⌘P에서 궤도 명령 검색→Return. 자유 배치로 돌아가도 끝점 선택·편집기 위치/크기 유지, 음악 r19 유지. |
| 범위 고정 | 끝점 96박(r20)→전체 점 보기→80박(r21). MCP displayBeats와 눈금은 96박을 유지한다. |
| 범위 재맞춤 | 끝점 128박(r22)에도 displayBeats=96. 전체 점 보기로 128에 맞춘 후 궤도로 전환해도 범위/선택 유지. |
| 원본 전환 | 공유 원본으로 전환 후 돌아오면 displayBeats=64와 ‘전체 점 보기 (1)’ 안내. r22 유지. 다른 서클 진입도 기본 범위로 돌아온다. |
| 스텝/MIDI/오디오 | 각각 두 레이아웃으로 전환해도 같은 node와 editorFrame 유지. 스텝 모드·3개 MIDI 노트·오디오 분할/길이 속성 유지. view 변경 외 음악 데이터 동일, r22 유지. |
| 저장/재열기 | r32에서 global/tracks/sections/arrangements/assets/patterns/portLayout/circleLayout 모두 최초 복원. 저장 후 재열기도 일치하며 자동 표시 범위는 기본 64박이다. |

스크린샷은 `menu-orbit.png`, `end-drag.png`, `layout-undo.png`, `range-fixed.png`, `range-layout-kept.png`, `midi-orbit-preserved.png`, `audio-freeform.png`에 있다. AX/JSON과 `restoration-log.json`은 같은 generated 폴더에 보존한다. 원본 `studio.circlr` manifest SHA-256은 **12c3e536731148d2085a14d498beffaca3a682126f2ad411ae653e4576d2be6d**이며 원본과 사본의 두 authored asset checksum도 같다. raw 프로젝트·이미지·앱·오디오는 Git에 포함하지 않는다.

## 미검증과 다음 UI

CUA의 문서화된 native click API에는 modifier 유지 클릭이 없다. Option 클릭은 Core 순환 검사와 실제 event 연결 검토까지 수행했으며 이 조합을 native에서 눌렀다고 주장하지 않는다. 대괄호→일반 클릭→드래그 경로는 실제로 확인했다. 명령 창이 열린 직후 typeText가 입력되지 않아 현재 search field를 확인한 뒤 paste/Return으로 검증했다.

같은 작은 창에서 MIDI 궤도가 약 120 px로 작고 음역이 밀집했다. 스텝은 두 행 정도만 보이고 오디오 속성은 아래 스크롤이 남는다. MIDI/오디오 전환 뒤 first responder는 창으로 보고되어 키보드 포커스도 다음 편집 UI 범위에 넣는다. 오토메이션의 길이 밖 점은 표시되지만 마디 눈금은 기존 local clock 길이까지만 생성된다. 이 동작들을 현재 개선 결과로 합산하지 않는다.

실제 VoiceOver, 재생 follow 중 전환, 밀집 그룹·긴 이름 전체 조합, mouse-down 중 외부 배치 변경은 미검증이다. 사용자 앱 출고와 실제 오디오 장치/녹음/MP4 acceptance, 다른 로드맵 기능은 남아 있다.
