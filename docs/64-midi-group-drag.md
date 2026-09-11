# MIDI 코드와 프레이즈 직접 이동

`session-bootstrap-v1`: owner=development-lead; baseline=05ef533; branch=codex/daw-integration; delegation=none. 직전 build 49가 구현·검증·push된 progress다. 실제 서브 에이전트 슬롯 제한을 유지하며 UI/UX → native Swift → 읽기 전용 review → QA를 순차 수행한다.

## 작업 계약

로드맵의 MIDI 다중 노트 드래그를 피아노 롤과 시간 궤도 양쪽에서 완성한다. 현재는 선택한 노트를 누르면 `selectedNoteID` setter가 추가 선택을 지우고 한 노트만 이동한다. 코드/프레이즈를 옮기거나 길이를 바꾸는 작업을 직접 조작으로 연결한다.

- 선택 집합 안의 노트를 잡으면 그 집합을 유지하고 해당 노트를 기준으로 삼는다. 선택 밖 노트를 잡으면 기존처럼 단일 선택으로 바꾼다. Shift 클릭은 선택 추가/해제를 유지한다.
- 본문 드래그는 선택 전체의 시간과 음정을 같은 양만큼 바꾼다. 드래그한 이동량을 현재 격자에 맞추며 기존 off-grid 시작과 노트 간격은 유지한다. 모든 선택 노트의 MIDI 0–127·시간 경계를 함께 제한해 코드를 찌그러뜨리지 않는다. 화면 밖 선택 노트도 포함한다.
- 끝 손잡이는 선택 노트의 길이에 같은 증감을 적용한다. 가장 짧은 노트/가장 늦은 끝을 기준으로 함께 제한한다. 이미 격자보다 짧은 노트를 잡기만 해도 길어지는 일이 없어야 한다. 기존에 서클 끝을 넘는 노트는 자르지 않고 초과를 더 늘리지 않는다.
- 드래그 중 미리보기는 모델·오디오·revision·Undo를 변경하지 않는다. mouse-up 한 번에 한 음악 편집을 적용한다. 클릭/0 이동/취소는 Undo를 만들지 않는다. 선택 유지·비선택 노트·오디오·ID·세기는 보존한다.
- 드래그 도중 대상·revision·선택·배치·격자·viewport/화면 크기가 바뀌거나 편집이 비활성화되면 적용하지 않는다. 오래된 AX 노트는 다른 대상에 선택을 적용하지 않는다. 같은 키보드 길이 조절에도 공통 선택 길이 제한을 사용한다.

## 소유와 검증

Core 소유: 새 `Sources/CirclrCore/MIDINoteDrag.swift`, `Tests/CirclrCoreTests/MIDINoteDragTests.swift`. App 소유: `MIDIWorkspace.swift`, `OrbitMIDIEditor.swift`, `EditorView.swift`, `EditorKeyboard.swift`, `MIDIOrbitWorkspace.swift`, `MIDIGridWorkspace.swift`, `MIDINoteInspector.swift`, `CanvasCommands.swift`. 새 dock/창과 새 데이터 schema, 실시간 audition은 추가하지 않는다. build 50과 README/CHANGELOG/로드맵, QA helper/기록을 갱신한다.

Core는 off-grid 선택·한쪽 경계·길이 차이·짧은 노트·기존 초과·비선택 및 audio/ID 보존·무효 입력을 검사한다. `./scripts/swift-local.sh test --scratch-path .build/automation-time-quality --skip testArrangementRenderExportAndPlayback`, `python3 -m unittest mcp.test_server qa.test_agent_kit`, `./scripts/swift-local.sh build -c release --scratch-path .build/integration-release`를 사용한다.

전용 authored MIDI QA 사본에서 3개 선택과 비선택 노트를 두고 두 편집기의 이동·공통 길이·선택 유지·Undo·저장/재열기를 검사한다. 실제 UI 좌표와 변경된 노트 데이터를 함께 확인한다. 드래그 중 modifier/외부 변경 주입의 도구 한계는 소스/Core 검사와 구분한다. 출력/audition/마이크를 시작하지 않는다. 사용자 앱·root/ports·음악/미디어를 보존하며 소스·문서·테스트·QA helper만 승인된 private branch에 commit/push한다.

## 실행 결과

build 50의 공통 Core와 두 native 편집기에 위 계약을 구현했다. Swift 382개·Python 26개와 최종 release, 실제 피아노 롤/궤도 이동·끝 길이·키보드 최소 길이·단독 선택·Undo·저장 복원을 통과했다. 최종 앱의 데이터 snapshot 11개와 AX/화면 20쌍, 코드/패키지 일치를 [QA 기록](../qa/midi-group-drag-review.md)과 `qa/check-midi-group-drag-evidence.py`로 검증했다. 사용자가 에이전트 한도 해제를 알린 뒤 독립 리뷰 dispatch를 다시 시도했으나 실제 도구는 `agent thread limit reached`를 반환했다. 이번 검토는 순차 역할 전환으로 수행했다.
