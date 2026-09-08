# 스텝·피아노 롤 작업 공간

2026-09-09, 기준 `4d397fd`, `codex/daw-integration`, build 37. development-lead → UI/UX → native Swift utility → 읽기 전용 검토 → QA. 실제 root 포함 1슬롯이므로 delegation none. 기존 활성 DAW 목표와 장치/출고 조건을 유지한다.

## 계약

작은 창과 콘솔 열림에서 스텝/피아노 롤의 노트 영역을 확보한다. 같은 캔버스의 왼쪽에 편집 방식/음역/파일 명령과 격자, 오른쪽에 음높이·시작·길이·세기와 일괄 편집을 둔다. dock나 창을 만들지 않는다. 기존 궤도 편집도 같은 선택 속성 구현을 공유해 입력/Undo/충돌 의미를 유지한다. 드럼과 음정 스텝을 모두 제공하고 드럼 행 추가를 편집기 도구 줄에서 바로 수행한다.

스텝의 분할·페이지·드럼 행은 같은 편집기에서 궤도/피아노 롤로 왕복해도 유지한다. 선택 노트를 바꾸거나 수치로 이동하면 실제 onset이 있는 페이지/행/열을 표시한다. 수동 페이지 이동은 선택을 해제하며 음악을 변경하지 않는다. 각 셀의 키보드 커서는 선택 노트와 일치해야 한다. Return은 해당 셀을 켜거나 끄고, Tab은 수치 필드로 이동한다. 수치 확정/취소는 스텝으로 포커스를 돌린다.

Native 첫 후보에서 행 스크롤 시 열 번호가 사라지고 음높이 Tab이 페이지 필드로 이동하는 것을 확인했다. 열 번호를 스크롤 밖에 고정한다. `CommittedNumberField.swift`에 선택적 필드 순서를 추가하고 `MIDINoteInspector`만 음높이→시작→길이→세기와 역순을 등록한다. 그 외 숫자 필드는 기존 AppKit 순서를 유지한다. 그룹의 잘못된 입력은 Tab에서도 해당 필드에 남으며 Esc로 취소한다.

피아노 롤은 선택 노트를 음역·가로/세로 스크롤로 따라간다. 화면 전환 뒤 문자 입력 포커스를 빼앗지 않으며, Return/Esc 뒤 방향키 편집을 이어간다. 드래그는 한 번만 적용하고 이전 프로젝트·세션·대상·선택·revision·음역/disabled 상태에서 적용하지 않는다. MIDI 0…127 밖의 키를 생성하지 않는다. 길이/시작·오프그리드 노트 정밀도와 음악 저장 형식은 유지한다.

피아노 롤의 박 번호와 음높이 키는 visibleRect의 위/왼쪽에 고정한다. 실제 노트 좌표는 원래 beat/pitch 좌표를 유지하고 키/헤더 hit 영역만 고정 위치를 따른다. scroll bounds 변경 시 눈금을 다시 그리며 클릭 드래그 중에는 자동 따라가기를 보류한다. 스크롤 구독은 view 제거 때 해제한다.

## 소유·검증·Git

- Native Swift: `InlineCircleEditor.swift`, `MIDIOrbitWorkspace.swift`, `OrbitMIDIEditor.swift`, `StepEditor.swift`, `EditorView.swift`, 새 `MIDINoteInspector.swift`, 새 `MIDIGridWorkspace.swift`. 공통 선택 속성/focus holder, 별도 grid view state, 기존 native canvas를 확장한다.
- Core: `StepEditing.swift`의 beat→step 주소와 `StepEditingTests.swift`의 경계/오프그리드/마지막 페이지 계약. 새 UI 모양을 그대로 복제하는 테스트는 만들지 않는다.
- QA: `.build/integration-quality` offline Swift, Python MCP/kit, `.build/integration-release` release. build 37 별도 앱/복사 fixture에서 작은 창·스텝 입력/선택/세기·분할/페이지·왕복·피아노 롤 Tab/스크롤·숫자/드래그/Undo·충돌 거절·저장 복원을 확인한다. 피아노 롤의 새 노트 audition/물리 출력/마이크는 시작하지 않는다. 스텝 쓰기는 원래 음악 모델만 바꾸는 경로다.
- Git: 동일 승인된 private 브랜치에 소스·검사·문서만 커밋/push한다. 앱·프로젝트·미디어는 로컬 QA에 유지한다. 기능별 증거와 미검증을 보고하며 전체 목표를 완료로 축소하지 않는다.

결과·수정된 native 발견·후속 범위는 [build 37 QA](../qa/midi-grid-workspace-review.md)에 기록한다.
