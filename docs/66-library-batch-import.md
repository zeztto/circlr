# 샘플 라이브러리의 여러 파일 가져오기

`session-bootstrap-v1`: owner=development-lead; baseline=927c3dc; branch=codex/daw-integration; delegation=none. 직전 build 51의 구현·native 검사·private push는 progress다. 실제 1 slot 제한을 유지한다. UI/UX → native Swift utility → read-only security/code review → QA 순서로 수행한다.

## 사용 흐름과 계약

기존 라이브러리의 단일 선택을 확장해 여러 폴더의 오디오를 한 번에 골라 각 새 트랙으로 가져온다. 검색 overlay를 재사용하고 새 창/dock는 만들지 않는다. 파일명 검색·원속도 preview·대상 revision 보호·atomic staging/Undo·기존 MIDI 트랙 선택을 유지한다.

- 행 클릭/↑↓는 한 파일을 선택한다. 행별 체크박스로 여러 파일을 선택하고, 검색창의 Shift ↑↓는 기준 행부터 연속 범위를 선택/축소한다. 모든 결과 선택과 해제를 버튼으로 제공한다. Cmd-A는 검색창의 문자 선택을 유지한다.
- 한 번에 최대 64개다. 상한을 넘는 선택은 일부만 적용하지 않고 이유를 표시한다. 검색·폴더/형식 필터가 바뀌면 보이는 결과에 포함된 선택만 유지하며 아무 선택도 남지 않으면 첫 결과를 선택한다. 보이지 않는 파일을 가져오지 않는다.
- 선택 개수·현재 정보/미리 듣기 파일·다중 오디오의 새 트랙 수를 표시한다. preview는 현재 행 하나만 명시적으로 실행한다. MIDI 여러 개 및 오디오/MIDI 혼합은 이유를 보이고 가져오기를 비활성화한다. MIDI 하나는 기존 트랙 선택 화면으로 간다.
- 실행 시 모든 선택의 등록 폴더·파일 종류·정규 경로·크기/수정 시각·한도를 재검증한다. 등록 폴더별 read-only security scope를 작업 전체가 끝날 때까지 유지한다. 원본은 변경하지 않으며 하나라도 실패하면 batch 전체를 적용하지 않는다.
- 오디오 여러 개는 기존 Core의 각 새 트랙·같은 시작 박 규칙으로 한 번 적용한다. 선택만으로 음악/Undo/preview가 시작되지 않는다. STOP/프로젝트/revision/generation 보호를 유지한다. snapshot에는 선택 개수만 추가하며 파일명/경로/검색어를 추가하지 않는다.

## 소유와 검증

Audio utility: 새 `Sources/CirclrAudio/MediaLibrarySelection.swift`, `Tests/CirclrAudioTests/MediaLibrarySelectionTests.swift`. App utility: `MediaLibraryController.swift`, `MediaLibraryView.swift`, `MediaImportWorkspace.swift`, `CanvasCommands.swift`의 선택 확장 callback, `AgentWorkspace.swift`의 개수 telemetry. `Resources/Info.plist` build 52, README/CHANGELOG/로드맵과 전용 QA helper/기록을 갱신한다. 새로운 외부 서비스/API·인증·구매·프로젝트 schema는 없다.

검사: 범위 정방향/역방향·상한·없는 ID·중복·혼합 형식·파일/batch bytes와 순서. 기존 file/atomic import/Undo/미디어 수명 검사를 함께 실행한다. 명령은 `./scripts/swift-local.sh test --scratch-path .build/automation-time-quality --skip testArrangementRenderExportAndPlayback`, `python3 -m unittest mcp.test_server qa.test_agent_kit`, `./scripts/swift-local.sh build -c release --scratch-path .build/integration-release`다.

전용 authored QA 폴더 두 개를 실제 파일 panel로 등록한다. 검색·체크박스·Shift 범위·해제·혼합 거절·오디오 2개 가져오기→새 트랙/section 확인→한 번 Undo/Redo→저장/재열기·원본 checksum·등록 제거를 확인한다. 작은 창과 콘솔에서 선택 수·대상·버튼이 보여야 한다. 실제 출력/마이크/audition은 시작하지 않는다. 보안 검토 후 source/docs/tests/helper만 승인된 private branch에 commit/push하고 root/ports/사용 앱 0.19와 원본 음악은 보존한다.

## 전달 결과

0.20.0 build 52의 실제 두 폴더 선택·혼합/손상 거절·batch import·한 번 Undo/Redo·저장/재열기·등록 정리를 확인했다. Swift 391개·Python 26개, native snapshot 9개와 최종 패키지의 범위/제한은 [QA 기록](../qa/library-batch-review.md)을 따른다. 검증 사본에는 imported 결과를 보관하며 원본 음악은 보존했다. 사용자의 한도 해제 알림 뒤 읽기 전용 검토 agent를 다시 dispatch했지만 실제 호출은 `agent thread limit reached`로 거절되어 순차 검토를 유지했다.
