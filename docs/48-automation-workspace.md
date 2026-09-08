# 오토메이션 작업 공간 개선

2026-09-09, 기준 `aeb54c0`, `codex/daw-integration`. development-lead → UI/UX → native Swift utility → read-only review/security → QA. 실제 동시 실행 1슬롯이므로 delegation은 none이며 독립 리뷰로 보고하지 않는다.

## 문제와 실행 계약

현재 오토메이션은 화면 폭의 43%에 곡선을 놓고 오른쪽의 긴 ScrollView에 명령·숫자·설명을 쌓는다. 작은 창에서 선택 점의 편집이 아래로 밀리고 dB 출력 화면과 볼륨 배율이 섞인다. 원본 편집의 범위도 현재 화면에서 바꾸기 어렵다. 드래그는 revision/address/parameter만 검사해 같은 서클에서 공유 원본 전환 시 오래된 preview가 다른 범위로 적용될 여지가 있다.

자유 배치는 한 캔버스에서 위 작업 줄, 폭을 사용하는 곡선, 아래 선택 점 편집 줄로 정리한다. 궤도는 원의 높이를 유지하고 양옆의 같은 캔버스 공간에 명령·선택 값을 배치한다. 볼륨은 dB, 팬은 −100…100%를 직접 입력하며 원래 linear gain과 pan -1…1 저장·DSP·보간은 유지한다. 0 dB/중앙과 무음, 박/마디 기준과 선택 점을 읽을 수 있어야 한다. 공유 원본/이번 사용 전환을 직접 제공하고 원본에 없는 추가 서클은 복귀 방법을 보여준다. 외부 revision/project/selection/원본/parameter 변경 뒤 numeric draft와 drag를 적용하지 않는다. 키보드로 점 선택·시간·dB/팬 조절을 지원하고 한 조작은 한 Undo다.

## 소유와 검증

- Core: `GainScale.swift`, `NumberEditSession.swift`, 새 `AutomationDisplay.swift`, 새 `Tests/CirclrCoreTests/AutomationDisplayTests.swift`. pan 표시/입력·range/finite/no-op 정밀도, 키보드의 실제 단위와 끝값, 기존 automation 시간·PCM 회귀를 검사한다.
- Native: `AutomationEditor.swift`, `AppStore.swift`, `AgentWorkspace.swift`. 명령/곡선/선택 입력 배치, Core 단위 사용, 축·선택/접근성 설명, 드래그의 전체 편집 identity와 enabled guard를 구현한다. 전체 점 보기의 실제 표시 범위를 MCP snapshot에도 반영하고, 숫자 Return/Esc는 곡선 포커스로 돌아온다. `Resources/Info.plist` build 34, README/CHANGELOG/로드맵/QA를 갱신한다.
- QA: `.build/integration-quality`에서 targeted 후 전체 offline Swift, Python MCP/kit와 `.build/integration-release` release. build 34 전용 QA 앱/복제 authored fixture에서 최소 창·콘솔/자유/궤도 배치, 점 추가/선택/삭제·gain/pan 숫자·shape/bypass·원본·드래그·방향키·stale·Undo·저장/재열기를 검사한다. 기존 사용자 앱·곡과 물리 입력/출력 설정은 유지한다.
- Git: 승인된 private `zeztto/circlr`의 동일 개발 브랜치에 검증된 source checkpoint. QA raw 미디어·프로젝트·앱은 제외한다. 전체 목표와 실제 장치/출고 acceptance는 남아 있다.

## 결과와 다음 범위

최종 build 34의 궤도/자유 드래그·방향키·삭제·원본 전환·외부 충돌·Undo·저장/재열기를 확인했다. 전체 offline Swift 307개, Python 26개와 최종 release/패키지 일치 검사가 통과했다. [QA 기록](../qa/automation-workspace-review.md)에 후보별 검증과 남은 범위를 구분한다. 테스트 프로젝트는 r65에서 최초 음악·배치로 복원했다.

전체 점 보기는 마지막 점의 위치에 맞춰 범위가 달라진다. 편집 중 범위를 고정하는 기능과 궤도/자유 전환 때 현재 편집 확대 유지, 궤도의 시작/끝 겹침 선택은 다음 UX 범위다. 실제 VoiceOver 발화·외부 변경 중 mouse-down 유지 조합은 검증하지 않았다. 현재 prepared PCM 재생의 gain/pan 계약을 확장한 것으로 보고하지 않는다.
