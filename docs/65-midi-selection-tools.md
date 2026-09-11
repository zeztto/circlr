# MIDI 파트와 코드 빠른 선택

`session-bootstrap-v1`: owner=development-lead; baseline=cdcb11f; branch=codex/daw-integration; delegation=none. 직전 build 50은 구현·native 검증·private push 완료로 progress다. 실제 agent slot 제한을 확인했으므로 UI/UX → native Swift utility → read-only review → QA를 순차 수행한다.

## 작업 계약

같은 음높이의 드럼/신스 파트, 같은 시작 박의 코드를 여러 번 Shift 클릭하지 않고 선택한다. 현재 노트 속성 영역의 위쪽에 선택 유무와 관계없이 노출하는 메뉴와 해제 버튼을 둔다. 피아노 롤·궤도·스텝 모두 같은 선택 명령을 사용한다. 별도 창이나 dock, 저장 schema와 오디오 경로는 추가하지 않는다.

- 전체 선택, 전체 해제, 반전, 같은 음높이, 같은 시작 박을 제공한다. 기준은 현재 서클/lane 전체이며 화면 밖 음역·마디도 포함한다. 여러 노트를 선택한 경우 선택된 모든 음높이/시작 박의 합집합으로 확장한다. 기준 선택이 없으면 조건 확장을 비활성화한다.
- 같은 시작 박은 0.0000001박 이내의 부동소수점 오차만 허용한다. 격자 기준 양자화나 실제 off-grid 노트 이동은 하지 않는다. 순서가 섞인 큰 lane에서도 중첩 전체 탐색을 피한다.
- 원래 선택 anchor가 결과에 남으면 그 anchor와 커서를 유지한다. 없으면 시간·음높이·ID 순서의 첫 노트를 선택하고 보여준다. 해제는 음악과 현재 입력 커서를 바꾸지 않는다. 선택만으로 revision·Undo·저장 음악·audition이 바뀌면 안 된다.
- 편집기에 키보드 포커스가 있을 때만 ⌘A 전체, ⇧⌘A 해제, ⌥P 같은 음높이, ⌥T 같은 시작 박, ⌥I 반전을 처리한다. 텍스트 작성 중에는 기존 문자/전체 선택을 유지한다. 메뉴의 선택 명령 뒤 해당 편집기로 포커스를 돌려 방향키 편집을 이어간다.
- 숫자·드래그와 같은 full edit identity로 메뉴를 열 때의 범위를 보호한다. 메뉴가 열린 뒤 외부 revision/대상이 바뀌면 과거 선택을 적용하지 않는다. 기존 MIDI 파일 메뉴의 전체/해제도 공통 명령을 사용한다.

## 파일 소유와 검사

Core: `Sources/CirclrCore/MIDINoteSelection.swift`, `Tests/CirclrCoreTests/MIDINoteSelectionTests.swift`. App: `Sources/CirclrApp/MIDIWorkspace.swift`, `MIDINoteInspector.swift`, `MIDIGridWorkspace.swift`, `MIDIOrbitWorkspace.swift`, `CanvasCommands.swift`. build 51 `Resources/Info.plist`, README/CHANGELOG/로드맵, 전용 QA helper/기록을 갱신한다. 승인된 private source branch에만 commit/push하며 root/ports·사용 앱 0.19·원본 음악은 보존한다.

Core에서 선택 집합·다중 기준·시간 오차/그루브·전체 lane·빈 선택·오래된 ID·음악 비변경을 검사한다. `./scripts/swift-local.sh test --scratch-path .build/automation-time-quality --skip testArrangementRenderExportAndPlayback`, `python3 -m unittest mcp.test_server qa.test_agent_kit`, `./scripts/swift-local.sh build -c release --scratch-path .build/integration-release`를 사용한다.

직접 작성한 전용 QA MIDI 사본에서 같은 음높이가 여러 마디에 있고 코드와 근접 off-grid 노트를 포함하도록 준비한다. 실제 세 편집기의 메뉴/키보드 선택, 화면 밖 선택, 그다음 음악 편집·한 번 Undo, text-field 보호, 작은 창/콘솔, 저장/재열기를 확인한다. 출력/audition·MIDI 입력·마이크는 시작하지 않는다. 과거 앱은 재실행하지 않으며 전용 QA 앱만 정상 종료한다.

## 실행 결과

build 51에서 구현했다. Swift 386개·Python 26개와 최종 release/패키지를 통과했다. 실제 피아노 롤·궤도·스텝의 조건/전체/반전/해제와 편집/Undo, 숫자 입력 보호, 다른 사용으로 이동한 메뉴의 조건 비활성화, 원본 저장/재열기를 확인했다. 메뉴 화살표의 중복 AX 항목을 native 검사에서 발견해 수정했다. [검증 기록과 한계](../qa/midi-selection-tools-review.md), `qa/check-midi-selection-tools-evidence.py`에 결과를 연결했다. CC·페달·피치 벤드와 장치 lifecycle·전체 DAW 출고 조건은 남아 있다.
