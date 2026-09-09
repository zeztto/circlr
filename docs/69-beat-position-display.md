# 음악 위치의 1 기반 박 표시

`session-bootstrap-v1`: owner=development-lead; baseline=f24e9da; branch=codex/daw-integration; delegation=none (직전 실제 dispatch가 thread limit으로 거절됨). UI/UX → native Swift/Core utility → read-only code/security review → QA로 진행한다.

## 문제와 작업 계약

라이브러리/MIDI 가져오기에서 9.5박에 넣은 음악이 오디오·MIDI 편집기의 8.5박으로 보여 사용자가 위치 변경으로 오해할 수 있다. 오토메이션의 마디 정보와 숫자 위치도 같은 차이가 있다. 시작 위치의 ordinal과 길이/경과량을 구별해 한 작업 흐름의 표시를 통일한다.

- 오디오 배치, MIDI 시작, 오토메이션 위치, 부모 안의 서클 시작은 첫 위치가 1인 4분음표 박이다. 가져오기 화면·피아노 롤/궤도 접근성 설명에도 적용한다. 기간/길이/간격과 원본 오디오 시간은 증가시키지 않는다.
- 내부 모델·MCP·편집 명령·geometry는 0 기반을 유지한다. migration·재저장·자동 quantize를 하지 않는다. 공통 `NumberEditPresentation.beatPosition`이 표시/해석만 변환하며 원시 baseline과 draft/identity/정밀도/Undo 계약을 따른다.
- range는 계속 내부 beat로 검증하고 오류는 1 기반 박으로 표시한다. 초기 포커스/Return/Tab/Esc만으로 미세한 기존 위치를 반올림하지 않는다. MIDI 가져오기의 끝 경계를 임의 0.001박 간격 없이 exclusive 검증한다.
- 오토메이션 그래프의 마지막 위치와 전체 길이 표기를 구별한다. 기존 마디 눈금의 1 기반/현재 박자 분모 기준 의미는 보존한다. 새 창·dock는 없다.

## 파일 소유와 검증

Core: `BeatPosition.swift`, `GainScale.swift`, `NumberEditSession.swift`, `AutomationDisplay.swift`, `BeatPositionTests.swift` 및 기존 AutomationDisplay 테스트. App: `CommittedNumberField.swift`, `Theme.swift`의 ValueField 전달, `AudioWorkspace.swift`, `MIDINoteInspector.swift`, `AutomationEditor.swift`, `InlineCircleEditor.swift`, `EditorView.swift`, `OrbitMIDIEditor.swift`, `MIDIImportView.swift`, `MediaLibraryPlacement.swift`, `MediaLibraryView.swift`, `CanvasFileDrop.swift`. build 55와 README/CHANGELOG/계획/QA를 기록한다. 데이터 schema·API/auth·DSP·외부 연결 변경은 없다.

검사: `./scripts/swift-local.sh test --scratch-path .build/automation-time-quality --skip testArrangementRenderExportAndPlayback`, `python3 -m unittest mcp.test_server qa.test_agent_kit`, `./scripts/swift-local.sh build -c release --scratch-path .build/integration-release`.

Native: authored 두-use QA 사본에서 오디오/MIDI/오토메이션/서클 설정의 첫 박, fractional 입력·오류·Esc·stale revision, Tab으로 길이 필드 이동 시 길이 보존, 이번 use 편집→Undo→저장/재열기를 검증한다. 가져오기/편집 위치 일치, 피아노 롤/궤도 표시, 작은 창·콘솔·AX를 확인한다. 실제 출력·audition·마이크를 시작하지 않는다. source/package/kit/codesign과 원본·사용자 앱·root/ports HEAD를 보존한 후 source/docs/tests/QA 도구만 승인된 private branch로 commit/push한다.

## 결과와 사용법

build 55에서 위 공통 위치 표시를 구현했다. Swift 406개·Python 26개, native 오디오/MIDI/오토메이션/설정 입력·오류·취소·충돌·세 MIDI 편집 방식·오디오/MIDI 가져오기·Undo·저장 복원을 확인했다. [상세 QA](../qa/beat-position-review.md).

- 첫 위치는 `1`, 그다음 4분음표 위치는 `2`다. `9.5`는 서클 시작부터 8.5개의 4분음표가 지난 위치다. 실제 초는 해당 서클의 tempo map을 따른다.
- `길이 1박`은 여전히 4분음표 하나의 기간이다. `원본 시작 0초`는 오디오 파일의 시작이다. 박자 분모가 달라도 이 위치 입력은 4분음표 기준이고 마디 안의 박 표시는 현재 박자를 따른다.
- Return/Tab으로 한 번 적용하고 Esc로 작성만 취소한다. 표시되는 자리수보다 정밀한 기존 위치는 단순 진입/퇴장으로 반올림되지 않는다. 프로젝트 파일·MCP 명령의 beat는 여전히 0 기반이다.

검증 중 보기 전환도 기존 Undo 이력에 들어가는 사용성 문제를 확인했다. 모드 왕복 뒤 첫 Undo는 음악보다 보기부터 되돌릴 수 있다. 이번 위치 단위 변경과 별도 계약으로 기록했으며, 음악과 실제 배치의 Undo를 보존하면서 보기 선호만 분리하는 다음 작업으로 이어간다. 사용 앱 교체·장치 출력·마이크·VoiceOver 발화 검증은 이번 완료 범위가 아니다.
