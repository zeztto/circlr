# 캔버스의 긴 이름과 선택 영역

## 실행 계획

`session-bootstrap-v1`: owner=development-lead; implementation=native Swift utility; branch=codex/daw-integration; baseline=48c2ac6; delegation=none. 사용자의 한도 해제 안내 뒤 독립 포트 검토를 다시 dispatch했으나 실제 도구가 `agent thread limit reached`를 반환했다. UI/UX 계약 → 구현 → 읽기 전용 검토 → QA를 순차 수행한다.

선택한 서클도 230px 한 줄로 생략되고, 정상 배치 후보가 화면 밖에 있으면 이름표 전체가 사라진다. 라벨이 연결 도구와 시간 손잡이를 가릴 수 있으며, 서클 중심이 화면 밖이면 보이는 라벨의 접근성 요소도 제외된다.

성공 조건:

- 주 선택의 이름은 최대 320px·세 줄로 읽는다. 나머지는 기존 한 줄 밀도를 유지하며 hover로 크기를 바꾸지 않는다. 긴 한글·영문·공백 없는 이름을 실제 AppKit 글꼴로 측정한다.
- 주 선택만 정상 후보 실패 후 화면 안으로 조정한 후보를 시도한다. 다른 서클·라벨·편집기·연결 도구·시간 손잡이·선택 포트를 가리지 않는다. 공간이 없을 때 겹쳐 그리지 않는다.
- 그려진 라벨 사각형을 클릭과 접근성에 함께 사용한다. 화면 밖 중심을 가진 서클도 화면 안 라벨이 있으면 접근 가능하다. 선택 테두리와 전체 제목 tooltip을 유지한다.
- 확대·이동·선택은 음악과 궤도/자유 배치 좌표를 바꾸지 않는다. QA 전용 authored 사본에서 작은 창, 긴 이름, 가장자리, 그룹/포트, 키보드 편집 왕복·Undo·저장 복원을 확인한다.

## 소유 파일과 검증

Core: `Sources/CirclrCore/CanvasLabelLayout.swift`; App: `Sources/CirclrApp/CanvasPresentation.swift`, `AlbumCanvas.swift`, `PlaybackVisualization.swift`; Tests: `Tests/CirclrCoreTests/CanvasLabelLayoutTests.swift`. 문서·버전·QA helper는 별도 후속 slice다. 기존 `playback.labels` 진단에는 제목·선택 여부·anchor를 추가해 에이전트와 QA가 화면 좌표를 추측하지 않도록 한다.

검증 명령: `./scripts/swift-local.sh test --scratch-path .build/connection-workspace-quality --skip testArrangementRenderExportAndPlayback`; `python3 -m unittest mcp.test_server qa.test_agent_kit`; `./scripts/swift-local.sh build -c release --scratch-path .build/integration-release`. 제어된 레이아웃 검사와 실제 QA 앱·AX·화면·manifest·코드서명 검증을 구분한다. 실제 VoiceOver 발화와 모든 밀집 조합의 검증을 대신하지 않는다.

원본 프로젝트·이전 QA 앱·사용자 0.19 앱은 보존한다. 이번 UI 검사에서는 출력·미리 듣기·입력 장치를 시작하지 않는다. 검증 후 승인된 private branch에 source/docs/tests/helper만 commit/push한다.

## 결과

Swift 353개·Python 26개, release와 실제 앱 검사 통과. 첫 native 후보의 밀집 선택 라벨 누락을 발견해 화면 둘레 후보로 수정했고 좌표를 회귀 테스트에 추가했다. 두/세 줄·공백 없는 제목, 화면 밖 중심의 AX/라벨 클릭, 연결 도구·그룹 IN 포트·MIDI 시간 손잡이, Undo·저장/재열기를 확인했다. [검증 기록](../qa/canvas-label-review.md).

다음에는 이름 입력 자체를 draft→확정/취소·한 Undo로 바꾼다. IME 조합, 편집 중 대상/revision 변경, 빈 이름, 긴 이름의 전체 읽기를 함께 검증한다. 실제 VoiceOver와 펼친 그룹의 대표 포트 조합은 별도 검증 범위다.
