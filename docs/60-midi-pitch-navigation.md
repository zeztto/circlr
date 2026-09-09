# MIDI 궤도의 음역 탐색과 음명

`session-bootstrap-v1`: owner=development-lead; baseline=bca805c; branch=codex/daw-integration; delegation=none (직전 실제 subagent 한도 거절). 이전 build 45는 구현·검증·push 완료로 progress다.

## UX·실행 계약

현재 궤도는 12/24개 반음 범위만 보여준다. 왼쪽의 C/F♯ 음명은 같은 높이에 몰려 특히 24행에서 겹친다. 넓은 음역의 연주는 ±옥타브와 순차 노트 탐색에 의존한다. 한 다크 캔버스의 기존 MIDI 편집 영역 안에서 개선한다.

- 기존 음역 조작 아래에 MIDI 0–127의 연주 분포와 현재 표시 범위를 그린다. 클릭으로 해당 음역에 이동하고 선택 범위를 드래그하면 잡은 위치를 유지한다. 이 조작은 음악·선택 노트·재생·Undo를 바꾸지 않는다.
- 막대에 포커스를 두면 좌우는 반음, Shift+좌우는 옥타브, Home/End는 양 끝으로 이동한다. Return/Esc는 노트를 추가하거나 화면을 닫지 않고 궤도 편집으로 돌아간다. 접근성은 표시 음역/범위·조작 설명을 제공한다.
- 궤도에서 가리키는 음 또는 선택한 음을 중앙에 음명/MIDI 번호로 표시하고 해당 행을 강조한다. 두 옥타브의 C 기준 음명은 공간이 있을 때만 서로 겹치지 않게 표시한다. 시간·노트 hit 영역은 그대로 유지한다. 새로 그린 강조는 오디오를 재생하지 않는다.
- 1/2옥타브, 전체 연주 분포, 빈 lane, 최저/최고 음, 대상 교체·배치 전환·Undo, 작은 창에서 조작/표시의 일치를 검증한다. 정확한 음역·hover 안내는 이 화면의 상태로만 유지한다.

## 소유 범위와 검증

UI/UX 정의 → native Swift utility → 읽기 전용 review → QA → development-lead 순차 전환이다. Swift 구현: `Sources/CirclrCore/MIDIOrbitViewport.swift`, 새 `Sources/CirclrApp/MIDIPitchNavigator.swift`, `MIDIOrbitWorkspace.swift`, `OrbitMIDIEditor.swift`. Core 회귀: `Tests/CirclrCoreTests/MIDIOrbitViewportTests.swift`. 문서/QA helper/Info build 46은 마지막 QA slice다. 기존 grid/step의 음역 UI는 별도 작업 공간으로 유지하며 신호·MCP 인증·오디오 장치·제작 곡을 수정하지 않는다.

검증 명령: `./scripts/swift-local.sh test --scratch-path .build/connection-workspace-quality --skip testArrangementRenderExportAndPlayback`, `python3 -m unittest mcp.test_server qa.test_agent_kit`, `./scripts/swift-local.sh build -c release --scratch-path .build/integration-release`. Native 전용 authored 사본에 저음/고음/두 옥타브의 노트를 추가해 분포→클릭/드래그/키보드→노트 선택/한 단계 편집/Undo→저장/재열기를 확인한다. 출력·audition·MIDI/마이크 입력은 시작하지 않는다. 실제 VoiceOver 발화와 하드웨어 출력 검증을 대신하지 않는다.

최종 소스·문서·테스트·QA helper만 승인된 private branch에 commit/push한다. root/ports 작업 트리·사용 앱·기존 QA 사본은 보존하고 최종 QA 앱을 정상 종료한다.

## 구현 결과

build 46에서 구현했다. 작은 창에서 밀려나는 노트 이동과 모드 버튼을 발견해 기존 조작 영역의 위/아래에 고정했다. Swift 366개·Python 26개, native 15 snapshots·8 JPEG, 음악/배치 복원과 최종 패키지 검사가 통과했다. 실제 pointer-only hover와 VoiceOver 범위는 [QA](../qa/pitch-navigation-review.md)에 분리했다.
