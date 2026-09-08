# DAW 통합 · 실행 계약

2026-09-08. 포트/UI 개발 `1d304eb`와 녹음 수명 주기 `d88ea5d`를 `codex/daw-integration`의 별도 worktree에서 통합한다. 기존 두 작업 디렉터리와 사용자용 0.19 앱은 보존한다. 이전 목표 턴은 D2 구현·native 편집 검증·private push로 progress였다.

## 소유와 범위

- development-lead: 통합 계약·merge 결정·후속 gate. 실제 1슬롯이므로 delegation none. 독립 리뷰로 보고하지 않고 역할을 순차 전환한다.
- native Swift/C utility: 기존 recording/ports 변경의 결합. 충돌 예상 파일은 `AppStore.swift`, `AgentWorkspace.swift`, `RootView.swift`, `CanvasCommands.swift`, `InlineCircleEditor.swift`, `StudioNavigationView.swift`. 새 전용 QA 저장소를 bundle ID에 따라 분리한다. 기존 음악/배치 Undo, stop/permission/recording gate를 모두 보존한다.
- Python backend/kit: `mcp/server.py`, `mcp/test_server.py`, 내장 adapter·operations·manifest를 합친다. record와 그룹/포트 도구를 모두 제공하며 모든 쓰기는 read-only specialist에서 차단한다.
- QA: 합쳐진 전체 Core/Audio·MCP/kit 검사, package/hash/signature, 정확한 통합 QA 프로젝트에서 MIDI/오디오/포트/오토메이션 편집·Undo·저장/재열기와 비녹음 상태의 입력 guard 확인.

그룹 alias는 실제 endpoint, 배치는 layout revision, 음악 편집은 music revision을 사용한다. 녹음 권한 대기·시작·정리 중에는 포트·파일 전환 등과 경쟁하지 않아야 한다. 이전 비동기 작업의 늦은 callback이 새 프로젝트를 수정하지 않는 경계를 유지한다.

실제 마이크 수집은 이전에 별도 허용되지 않은 범위이며 실행하지 않는다. 읽기 전용 관찰과 이미 허용된 전용 QA 앱/작성된 tone 재생은 진행한다. 시스템 출력 장치나 TCC 설정을 바꾸지 않는다. 출력 timeout은 정확한 QA 프로세스의 샘플과 앱 상태로 조사하며 관측 timeout만으로 실행 중 작업을 재시작하지 않는다.

## 검증과 Git

1. 두 기준 commit과 clean 상태를 확인하고 같은 기반 `040bb2b`의 녹음 이력을 merge한다. 양쪽 의미를 결합하고 양쪽 구현 중 하나를 통째로 선택해 버리지 않는다.
2. `swift test --scratch-path .build/integration-quality --skip testArrangementRenderExportAndPlayback`, `python3 -m unittest mcp/test_server.py qa/test_agent_kit.py`와 release build를 실행한다. 통합으로 드러난 실제 경계 오류에만 회귀 검사를 추가한다.
3. `com.circlr.integrationqa` 앱/별도 Application Support/socket과 authored QA 사본을 사용한다. 사용자 파일, ports/recording QA 앱과 프로젝트는 덮어쓰지 않는다. 기존 앱 리소스·내장 키트와 같은 소스 binary를 패키징하고 signature/UUID/hash를 확인한다.
4. 직접 편집/Undo/저장/재열기, MCP의 port/record 계약 공존, 키보드 즉시 이동/가독성을 native 증거와 대조한다. 녹음·실장치·VoiceOver의 미확인 범위를 명시한다.
5. README/CHANGELOG/roadmap과 QA를 갱신하고 승인된 private source 범위만 `zeztto/circlr`에 push한다. main/사용 앱 출고는 전체 E acceptance를 통과한 뒤 결정한다. 이 통합 체크포인트를 전체 목표 완료로 취급하지 않는다.

## 통합 결과와 다음 실행

0.20.0 build 23에 양쪽 변경을 보존했다. Swift 226개·Python 26개, release build와 별도 native 앱의 편집·Undo·바운스·저장/재열기·최소화·출력별 모션을 확인했다. 녹음 테이크를 추가한 뒤 그룹 binding·router port와 PCM을 보존하며, layout Undo가 현재 take를 지우지 않는 교차 회귀 검사를 추가했다. [검증 근거와 제한](../qa/daw-integration-review.md).

다음 slice는 UI/UX 계약 → native App/geometry utility → QA 순서다. 재생 follow 화면에서 부모 궤도를 맞추면 자식 서클이 중앙에 작게 모이고 라벨이 겹치는 실제 문제가 있다. 활성 섹션의 자식과 연결을 읽을 수 있는 카메라 관심 범위, 선택/재생/주변 라벨 우선순위와 직접 편집 진입을 개선한다. 시간·반복·음악 revision·저장된 노드 위치는 보존하고, 수동 조작 시 follow 중단 및 재개를 유지한다. 1440×900·최소 창·콘솔 열림/닫힘·접힌 그룹·두 출력·MIDI가 섞인 현재 fixture로 화면/AX/PCM 불변을 확인한다. 추가 패널을 만들지 않는다.

E 출고 gate는 실제 마이크 입력/취소/장치 변경/종료 복구, VoiceOver 발화, MIDI·sidechain·송폼의 밀집 pointer/키보드 전체 조합과 v4/MP4 통합 회귀다. 입력 검증에 별도 허용이 필요한 상태는 유지하며, 독립적인 UI·엔진·import 작업을 계속 진행할 수 있다.
