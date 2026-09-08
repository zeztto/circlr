# build 42 · MIDI 가져오기 위치

## 계획과 소유권

`session-bootstrap-v1`: owner=development-lead; implementation=native Swift utility; communication=Korean; branch=codex/daw-integration; baseline=87dc228.

요청 결과는 파일을 놓은 음악 시간과 가져온 노트의 위치가 일치하고, 시작 위치를 같은 캔버스에서 확인·수정하는 것이다. UI/UX → Swift 구현 → 읽기 전용 코드 검토 → QA 순서다. 독립 캔버스 감사 위임은 실제 `agent thread limit reached`로 거절되어 delegation=none이다.

- Core 소유: `Sources/CirclrCore/MIDIEditing.swift`, `Tests/CirclrCoreTests/MIDIEditingTests.swift`. 명시적 시작 박·자유 배치 위치, 노트 간격/쉼표 보존, 원자성, 기존 routing 위치 보존.
- App 소유: `MIDIImportView.swift`, `CanvasFileDrop.swift`, `MediaLibraryView.swift`, `InlineCircleEditor.swift`. 메뉴/라이브러리/드롭이 같은 초안으로 들어간다. 시작 위치는 1부터 세는 4분음표 박이며 모델은 0부터 센다. 기존 섹션 범위 안에서 시작하고 끝이 넘으면 이번 사용만 늘린다.
- 고정 제목/확정/취소·시작 위치·길이 안내를 목록 위에 두고 트랙 목록만 스크롤한다. 기존 노트와 파일 내부의 선행 쉼표는 유지한다. 악기/CC/tempo map을 새로 가져오는 범위가 아니다.
- 검증: Swift 전체(장치 의존 `testArrangementRenderExportAndPlayback` 제외), Python MCP/kit, release, authored MIDI의 Native 시작 위치 수정→적용→Undo→저장/재열기. Core는 6/8·변박·offset 범위·노트 값·다른 사용·master 위치·freeform 좌표를 검사한다.
- 정확한 QA 사본과 로컬 앱만 사용하며 물리 출력/마이크를 시작하지 않는다. Finder 실제 drag 검증은 도구가 교차 창 gesture를 지원할 때만 수행한다. 소스·문서·검사만 기존 승인된 private branch에 push한다.

## 동작 계약

MIDI 파일의 0박을 선택한 시작 위치에 맞춘다. 첫 노트 앞의 쉼표를 제거하지 않는다. 오디오와 같은 방식으로 drop의 section local 좌표를 자유 배치에서 사용한다. 새 MIDI 서클은 별도 트랙이며 이번 사용에 추가한다. 공유 섹션 원본과 다른 사용의 lane은 바꾸지 않는다.

미리보기는 음악을 수정하지 않는다. 취소·잘못된 위치·외부 revision 변경은 전체 거절한다. 성공한 여러 트랙은 한 번의 Undo로 복원한다. 가져온 단일 서클은 바로 MIDI 편집기로, 여러 서클은 섹션 전체로 이동한다.
