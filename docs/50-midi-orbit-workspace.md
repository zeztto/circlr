# MIDI 궤도 작업 공간

2026-09-09, 기준 `fedbd5a`, `codex/daw-integration`. development-lead → UI/UX → native Swift utility → 읽기 전용 검토 → QA. root 포함 실제 한 슬롯으로 delegation은 none이다.

## 결과 계약

작은 창과 콘솔 열림에서 선택 노트의 속성이 궤도의 높이를 줄이지 않게 배치한다. 왼쪽의 같은 캔버스에는 표시 음역·마디 범위·이전/다음 노트, 중앙에는 확대된 궤도, 오른쪽에는 음높이·시작·길이·세기와 선택 편집을 둔다. 새 dock나 창은 만들지 않는다. 기본 4마디/1옥타브를 사용하고 연주 음역에 맞춰 최대 2옥타브로 조절하며 전체 길이와 음역 이동도 제공한다. 범위 변경은 음악 데이터를 바꾸지 않는다.

원에서 각도는 표시된 로컬 시간 범위, 반경은 표시된 음높이다. 현재 마디 범위와 음역을 명시한다. 다른 페이지에 걸친 노트는 잘린 부분임을 표시하며 실제 끝점에서만 길이를 조절한다. 격자는 화면상 간격을 기준으로 줄이되 입력 스냅은 원래 박 분할을 유지한다. 선택 노트 탐색은 시간·음높이 순이며 필요한 음역/마디로 따라간다.

현재 마디에 일부가 보이는 긴 노트는 선택 시 시작 페이지로 뛰지 않는다. 궤도/스텝/자유 배치를 왕복해도 같은 편집기의 음역·마디 범위를 유지한다. 화면 밖 선택 복귀는 탐색 줄에 두어 속성 영역의 높이를 바꾸지 않는다. 짧은 단축키 안내와 전체 도움말을 함께 제공한다.

숫자는 공통 Return/Tab/Esc·범위·stale guard를 사용한다. Return/Esc 뒤 궤도에서 방향키 편집을 이어간다. 궤도 진입/배치 전환 후 포커스를 제공하며 검색/콘솔의 문자 입력은 가져오지 않는다. 드래그는 프로젝트·세션·원본·대상·선택·revision·viewport 변경 후 적용하지 않는다. 접근성에서 각 노트의 실제 음높이·위치·길이·세기를 읽고 선택할 수 있어야 한다.

## 소유와 검증

- Core: 새 `MIDIOrbitViewport.swift`, 새 `MIDIOrbitViewportTests.swift`. 로컬 박자별 페이지 범위·tempo map 좌표·음역 경계·노트 탐색/가시성·clipped endpoint를 검사한다.
- Native Swift: 새 `MIDIOrbitWorkspace.swift`, `OrbitMIDIEditor.swift`, `InlineCircleEditor.swift`; 필요 시 `MIDIWorkspace.swift`. 새 UI는 궤도 MIDI에 적용하고 기존 피아노 롤/스텝은 보존한다. 공통 viewport와 native focus holder를 사용한다.
- QA: `.build/integration-quality` targeted 후 전체 offline Swift, Python MCP/kit, `.build/integration-release` release. build 36 QA 앱/별도 authored fixture에서 작은 창·콘솔, 실제 선택/숫자/방향키/이동/길이·Undo·외부 변경 거절·표시 범위·배치 전환·저장 복원을 확인한다. 물리 장치 지연이 남아 있어 native 입력 검증은 기존 노트 편집으로 수행하고 새로운 노트의 audition은 시작하지 않는다.
- Git: build 36 소스·문서·검사만 승인된 private 동일 브랜치에 저장한다. 사용자 앱·음악·권한·출력 설정과 raw QA 미디어는 유지한다. 전체 DAW 목표·피아노 롤/스텝 전체 UI·실시간 오디오/출고 acceptance는 이 범위로 축소하지 않는다.

실행 결과·순차 검토·후속 범위는 [build 36 QA](../qa/midi-orbit-workspace-review.md)를 따른다. 이번 턴에도 서브 에이전트 할당이 `agent thread limit reached`로 거절되어 독립 검토로 계산하지 않는다.
