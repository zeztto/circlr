# 편집기의 보기 위치 유지 — build 68

planning-gate-v1: development-lead, baseline=acf8490, branch=codex/daw-integration. build67 구현/native/private push는 progress. 실제 1 slot. 사용자 한도 해제 안내 후 read-only 검토를 dispatch했으나 `agent thread limit reached`로 거절되어 delegation none. UX → Core/native utility → read-only review → QA 순차 소유.

## 계약

같은 프로젝트 세션에서 서클·이번 사용/공유 원본별로 MIDI 스텝 페이지·분할·행 모드·행 검색·음역, 궤도 MIDI 마디/음역, 오디오 원본 표시 구간을 기억한다. 현재 서클의 보기 상태는 build67 workspace에 optional로 저장하여 재열기에서도 복원한다. 오토메이션은 서클·범위·볼륨/팬별 표시 길이를 기억하고 현재 파라미터의 길이를 저장한다. 피아노롤/스텝 목록과 설정 등의 스크롤은 실제 콘텐츠 범위 안에서 복원한다.

설정/연결 왕복 및 다른 서클 방문이 임의 맞춤·첫 페이지 이동을 일으키지 않아야 한다. 사용자가 선택한 새 노트의 명시적 탐색·편집은 기존 reveal 동작을 유지한다. 보기 변화는 음악 revision/Undo를 만들지 않는다. MIDI 길이가 줄면 페이지를 제한하고, 오디오 asset이 바뀌면 이전 원본의 범위를 버린다. 유효하지 않은 저장 숫자·위치는 기본값 또는 유효 범위로 정리한다. 이전 문서의 nil은 기존 최초 맞춤 동작이다. 세션 경계를 지난 view callback은 새 문서에 기록하지 않는다.

## 책임과 검증

Core utility: `EditorViewportState.swift`, `MIDIOrbitViewport.swift`, `AudioSourceViewport.swift`, `AutomationViewport.swift`, `StudioWorkspace.swift`, `Tests/CirclrCoreTests/EditorViewportStateTests.swift`. Native utility: `EditorWorkspace.swift`, `EditorScrollMemory.swift`, `InlineCircleEditor.swift`, `MIDIGridWorkspace.swift`, `EditorView.swift`, `MIDIOrbitWorkspace.swift`, `StepEditor.swift`, `AudioWorkspace.swift`, `AppStore.swift`, `AlbumCanvas.swift`, `SavedWorkspace.swift`, `Resources/Info.plist`. 공용 스크롤 modifier는 기존 콘텐츠 내부에 붙이고 새 창/고정 패널을 만들지 않는다. 네트워크·인증 변경 없음.

`./scripts/swift-local.sh test --scratch-path .build/editor-position-quality --skip testArrangementRenderExportAndPlayback`, `python3 -m unittest mcp.test_server qa.test_agent_kit`, release build. 모델 구조 변경 때문에 새로운 scratch를 사용한다. 숫자/범위/asset 교체·문서 왕복·음악 보존 검사와 native 페이지/스크롤→설정 왕복→다른 서클 왕복→Undo→저장/재열기 흐름을 비교한다. 실제 범위 축소와 처음 여는 서클도 검사한다. 작은 창 AX/이미지, 저장 문서 전체, source/app/kit hash와 서명을 검증한다. 원본 fixture/root/ports/사용자 앱과 물리 입출력 경계를 유지한다.

README/CHANGELOG/docs25/31/82·QA 도구와 보고서를 갱신하고 검증한 텍스트 파일만 승인된 private 브랜치로 commit/push한다. 전체 DAW/UX 목표는 계속 유지한다.

## 검증 결과

Swift485개·Python28개, native19상태·43화면과 전체 음악/패키지 비교를 통과했다. 최종 앱은0.20.0 build68, 정상 종료했다. 현재 서클 보기만 문서에 저장하고 다른 서클 cache는 세션 내에서 유지한다. 선택 노트/점/오디오 커서와 보조 폼 전체의 영속화는 후속이다. 실패·수정·두 후보 및 CUA 잘못된 프로세스 참조 기록은 [QA](../qa/editor-position-review.md)에 구분했다.
