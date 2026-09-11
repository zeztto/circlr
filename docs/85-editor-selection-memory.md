# 편집 선택 복귀 — build 71

planning-gate-v1: development-lead. 기준ef72893, `codex/daw-integration`. 직전 turn은 build70 검증/commit/push로 progress다. 실제1 slot에 따라 delegation none. UX → Core/native utility → code/security review → QA 순차 소유. 기존 앱/root/ports/원본 음악은 보존하며 새 authored 사본만 검증한다.

## 사용자 계약

서클을 돌아왔을 때 선택한 MIDI 노트·오토메이션 점·오디오 분할 커서를 다시 찾지 않도록 한다. 서클/원본과 이번 사용을 분리하고, 볼륨/팬 점도 각각 기억한다. 현재 작업의 선택은 workspace 보기 정보로 저장한다. 저장/복원은 음악 revision·Undo를 추가하거나 재생을 시작하지 않는다. 삭제된 ID를 복원하지 않고, 같은 오디오 클립·asset에서 원본 시간 커서를 유지하며 trim 범위에 맞춘다. 다른 프로젝트/세션으로 선택이 넘어가지 않는다.

## 소유 파일과 검증

- Core: `EditorSelectionState.swift`와 `StudioWorkspace.swift`. 선택 ID/anchor·beat·source cursor·parameter별 점 ID를 저장하고 실제 편집 자료에 대해 검증한다. 기존 workspace는 선택 없이 열리며 잘못된 선택 메타데이터는 무시한다.
- Native: `EditorSelectionMemory.swift`, `AppStore.swift`, `AlbumWorkspace.swift`, `SavedWorkspace.swift`, `AutomationEditor.swift`. 탐색 직전 캡처/대상 해석 후 복원, 원본·parameter 전환, reset guard, 현재 workspace 저장/재열기.
- Tests: `EditorSelectionStateTests.swift`의 삭제/중복/anchor/trim/asset교체/파라미터/비유한/legacy·문서 roundtrip. `swift-local.sh test --scratch-path .build/selection-memory-quality --skip testArrangementRenderExportAndPlayback`; Python MCP/kit 회귀; release 및 native.
- QA: 전용 package/capture/checker/report로 MIDI 다중/다른 사용/원본 왕복, 볼륨·팬 선택, 오디오 커서, 저장 재열기와 음악/자산 보존을 확인한다. 물리 장치 출력/녹음과 VoiceOver 발화는 이 선택 개선의 완료 근거로 사용하지 않는다.

## 결과와 후속

Swift496개·Python29개, native30상태/34화면 통과. 처음 발견한 트림 Undo 커서 이동을 수정하고 최종 앱에서 MIDI/오디오 이력과 재열기를 다시 확인했다. 전체 음악·자산·compiled source/kit를 대조하고 세 QA 앱을 종료했다. 원본/다른 사용과 파라미터별 선택은 세션에서 구분하며 문서는 현재 작업의 선택만 보관한다. 모든 방문 이력의 영속화·화면 밖 선택 직접 보기·오디오 폼 가시성은 후속 범위다. [QA](../qa/selection-memory-review.md)에 후보별 근거와 남은 검증을 기록했다.
