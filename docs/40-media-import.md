# 파일 가져오기 · 같은 캔버스로 직접 전달

2026-09-08, 기준 `415e62b`, branch `codex/daw-integration`. 이전 턴은 출력/키보드 구현·native QA·private push로 progress다. development-lead → UI/UX → Core/Audio utility → App utility → read-only review → QA. 사용자의 슬롯 해제 안내 후 독립 리뷰 spawn을 다시 시도했으나 agent thread limit reached가 반환되어 delegation none. 전체 목표는 유지한다.

## 작업 계약

현재 오디오 가져오기는 MainActor에서 파일을 열고 여러 파일에 각각 Undo를 쌓으며 원본 절대 경로를 저장 전까지 참조한다. 캔버스는 외부 파일을 받지 않는다. 먼저 공통 비동기 import 경로를 만들고 메뉴와 file-URL drop을 연결한다.

- 파일 선택 전에 대상 프로젝트·섹션·track·박을 고정한다. 작업 중 문서/음악이 바뀌거나 STOP이면 늦은 결과를 적용하지 않는다. 원본 파일은 변경하지 않고 소유한 새 staging 폴더에 복사·hash·형식을 검증한다. 하나라도 실패하면 batch 전체를 적용하지 않는다.
- 정상 batch는 한 번의 음악 Undo다. 한 파일을 현재 트랙에 넣는 기존 동작은 유지하며, 여러 파일 또는 트랙을 지정하지 않은 drop은 파일별 새 트랙을 만든다. 기존 MIDI/클립/route/포트 배치와 다른 섹션 사용은 보존한다. successful staging은 Undo/Redo·복구 참조를 위해 유지한다. 참조 없는 파일 GC/중복 catalog는 이후 라이브러리 범위다.
- 섹션/그 내부 음악 서클로 파일을 끌면 대상과 파일 수를 표시한다. orbit에서는 섹션의 각도를 박으로, freeform에서는 drop 좌표를 서클 위치로 쓴다. 음악 순서를 공간 좌표로 바꾸지 않는다. 편집기·콘솔·도구막대 영역의 drop은 캔버스가 가로채지 않는다.
- MIDI 한 파일은 기존 트랙 선택/길이 확장 화면을 재사용한다. 오디오+MIDI 혼합 batch와 여러 MIDI는 부분 적용 대신 안내하고 거절한다. MIDI 노트 이외 이벤트를 가져왔다고 주장하지 않는다.
- NSFilePromiseReceiver/Splice companion·로컬 검색은 이 공통 경로 뒤에 연결한다. file promise를 파일 URL로 간주하지 않으며, 지원 전에는 성공으로 응답하지 않는다. 실제 Splice 구매·인증·라이선스 조건은 이번 변경에 포함하지 않는다.

## 소유와 실행

Core utility: `AudioImportEditing.swift`, 대상 검증/atomic batch/음악 위치 회귀 검사. Audio utility: `AudioFileImport.swift`, bounded streaming copy·취소·정규 파일/포맷/미디어 검사와 checksum, 실패 소유 폴더 정리, 제어된 WAV 검사.

App utility: `AppStore.swift`, 새 `MediaImportWorkspace.swift`, `MIDIImportView.swift`, `AlbumCanvas.swift`와 새 `CanvasFileDrop.swift`, 필요한 진단. 파일 panel과 I/O 분리, 한 음악 mutation, STOP/reset hook, drop hover와 target 고정. UI는 한국어·단일 다크 캔버스이며 build 26. MIDI URL 분리 시 기존 revision/노트 경고를 유지한다.

QA: 순수 Core/Audio → 전체 Swift/Python → release → 별도 QA 앱에서 여러 파일/Undo/저장 복원·오류 rollback·최소 창·직접 drop과 MIDI 미리보기. native 불가 경로는 미검증으로 남긴다. 입력 녹음·장치/TCC 설정·원본 곡·기존 사용자 앱은 보존한다. 독립 리뷰는 실제 실행될 때만 그렇게 기록한다.

Git: 같은 private branch에 검증한 source/docs/test만 commit/push. 오디오/프로젝트/앱/인증정보는 제외한다. `README.md`/`CHANGELOG.md`/로드맵에 실제 구현 및 남은 범위를 반영한다.

AppKit 근거: [performDragOperation](https://developer.apple.com/documentation/appkit/nsdraggingdestination/performdragoperation(_:))은 accept 이후 실제 가져오기를 시작하는 지점이다. [file promise 수신](https://developer.apple.com/documentation/appkit/nsfilepromisereceiver/receivepromisedfiles(atdestination:options:operationqueue:reader:))은 별도 operation queue에서 파일 생성 완료/오류를 받아야 한다. 다운로드가 완료되지 않은 promise를 동기 파일처럼 읽지 않는다.

## 구현 체크포인트

Core `AudioImportEditing`은 별도 candidate에서 batch 전체를 검사한다. 한 파일/현재 트랙과 다중/새 트랙을 구분하고 기존 signal 좌표를 복구한다. Audio I/O는 파일당 2 GiB, batch 4 GiB, 64개, mono/stereo, 1시간을 상한으로 한다. 1 MiB 단위 복사와 SHA-256, 취소 검사를 사용한다. 성공한 import 디렉터리는 세션/Undo/복구 참조로 유지한다.

`MediaImportWorkspace`는 project/revision/session generation을 고정하고 detached worker 결과를 MainActor에서 한 번 적용한다. STOP/reset은 generation과 Task를 취소한다. 편집 도중 이동한 화면을 불필요하게 뺏지 않고, 다중 가져오기 뒤에는 섹션 전체를 표시한다.

검토 중 저장→Undo→저장→Redo에서 패키지의 미디어 삭제가 세션 참조를 끊는 문제를 확인했다. 추가 범위 `SessionMedia.swift`, AppStore/AgentWorkspace 저장 경로는 패키지에는 복사본을 쓰면서 열린 세션의 절대 로컬 참조를 유지한다. `AudioFileImportTests.testSaveUndoSaveRedoKeepsImportedMediaAlive`는 패키지에서 파일이 제거된 뒤에도 retained staging으로 렌더하고 다시 저장한다. 이는 전체 자산 catalog/GC나 파일 이동 재연결을 완료한 것이 아니다.

배포 대상은 같은 private 개발 브랜치다. 실제 Finder↔앱 간 drag 좌표는 현재 CUA의 창별 관찰만으로 확정할 수 없어 그 제스처는 미검증으로 기록한다. MIDI 미리보기는 기존 16 MiB 제한을 유지하는 동기 파서다. file promise·MCP import job·checksum 중복 catalog·참조 추적 GC를 다음 독립 단계로 진행한다. 검증 상세는 [QA 기록](../qa/media-import-review.md)을 따른다.
