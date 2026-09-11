# 오디오 원본 시간 확대와 이동

`session-bootstrap-v1`: owner=development-lead; baseline=6e4c2b6; branch=codex/daw-integration; delegation=none. 독립 UI 검토를 요청했으나 실제 도구가 `agent thread limit reached`를 반환했다. UI/UX → native Swift utility → 읽기 전용 review → QA를 순차 수행한다.

## UX 계약과 완료 조건

긴 오디오의 작은 구간을 찾아 분할·트림할 때 전체 파일/선택 구간만으로는 필요한 배율과 위치를 유지하기 어렵다. 기존 다크 캔버스의 오디오 편집기에만 다음을 추가한다.

- 파형 위 세로 휠은 포인터의 원본 시간을 기준으로 확대/축소한다. 가로 휠 또는 Shift+세로 휠은 표시 시간을 이동한다. 확대해도 외곽의 섹션 궤도와 실제 음악 시간은 바뀌지 않는다.
- 파형 아래의 확대/축소 버튼과 키보드 `−/+`는 보이는 분할 커서를 기준으로, 커서가 화면 밖이면 현재 범위의 중앙을 기준으로 확대한다. 최소 표시 폭은 0.01초이며 짧은 파일은 전체 길이가 하한이다.
- `Page Up/Down`은 화면 폭의 절반만큼 이동하고 `Home/End`는 파일 처음/끝으로 이동한다. `0`은 전체 파일, `F`는 선택 구간, `C`와 ‘커서 보기’는 화면 밖 분할 커서를 현재 배율로 찾는다. 원래 좌우 방향키 trim, Option 끝 trim, 분할/복제 단축키는 유지한다. 숫자 입력 중에는 텍스트 키를 가로채지 않는다.
- 원본 표시 범위를 읽을 수 있고 좁은 범위의 눈금도 서로 다른 밀리초를 표시한다. 편집/Undo/궤도 전환 중 표시 범위는 고정한다. 다른 대상/원본 전환은 기존처럼 전체 파일로 돌아간다. 탐색은 music revision·Undo를 만들지 않는다. 오래된 대상의 이벤트와 표시 변경 중 남은 drag를 거절한다.

## 파일 소유와 검증

Core: `Sources/CirclrCore/AudioSourceViewport.swift`, `Tests/CirclrCoreTests/AudioSourceViewportTests.swift`. App: `Sources/CirclrApp/AudioWorkspace.swift`, `OrbitAudioEditor.swift`, `CanvasCommands.swift`, `AlbumCanvas.swift`의 이벤트 전달, `InlineCircleEditor.swift`의 실제 작업별 안내. 문서/패키지: build 49 Info, README/CHANGELOG/로드맵, `qa/prepare-audio-source-navigation-qa.py`, `verify-audio-source-navigation-native.py`, evidence checker와 보고서.

Core 검사는 원본 좌표 anchor 불변, 파일 경계와 최소 배율, 이동/커서 보기, 비유한 입력 거절을 검증한다. `./scripts/swift-local.sh test --scratch-path .build/automation-time-quality --skip testArrangementRenderExportAndPlayback`, `python3 -m unittest mcp.test_server qa.test_agent_kit`, `./scripts/swift-local.sh build -c release --scratch-path .build/integration-release`를 수행한다.

새 authored QA 사본에서 실제 작은 창의 버튼·휠·키보드·숫자 입력/Undo·배치/대상 전환·저장 복원을 검사한다. 출력/audition/실제 입력을 시작하지 않는다. 실제 Shift+휠과 트랙패드 hardware 입력이 도구로 불가능하면 소스 검토 범위로 구분한다. root/ports 작업 트리, 사용자 앱, 원본 asset을 보존하고 승인된 private branch에 소스·문서·테스트·QA helper만 commit/push한다.

## 결과

build 49 최종 `readable` 후보에서 완료했다. Swift 377개·Python 26개와 release, 실제 앱의 휠·키보드·수치/드래그 트림·Undo·궤도 전환·대상/원본 전환·저장 복원을 확인했다. 첫 후보의 캔버스 휠 가로채기와 중간 후보의 작은 원형 파형을 native QA에서 수정했다. 최종 캡처 9개·AX 35개·JPEG 6개와 검증 범위는 [QA 보고서](../qa/audio-source-navigation-review.md)에 있다. 출력 장치 시작은 0회이며 전체 DAW 목표와 실제 장치 검증은 유지한다.
