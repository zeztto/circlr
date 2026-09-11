# 캔버스 접근성 좌표와 직접 조작 — build 70

planning-gate-v1: development-lead, 기준544715b, `codex/daw-integration`. 실제 agent 한도 거절로 delegation none. UX → native Swift utility → code review → QA 순차 소유. 이전 goal turn은 build69 commit/push로 progress다.

## 사용자 결과와 경계

스텝 행을 접근성 이름으로 선택할 때 `elementHasNoFrame`이 발생했다. 같은 캔버스의 MIDI 노트·오토메이션 점·서클·포트·케이블도 가상 `NSAccessibilityElement`를 사용한다. 화면의 실제 위치와 접근성 좌표를 일치시키고 창 이동/스크롤 후에도 따라가도록 한다. 새 창·패널을 추가하지 않는다. 행 선택은 음악을 바꾸지 않고, 셀 입력과 Undo는 기존 편집 경로를 사용한다.

기존 root/ports checkout·사용 앱0.19 build21·원본3트랙/2톤을 보존한다. `accessibility-geometry.circlr`와 전용 QA 앱만 실행한다. 물리 출력/입력은 이번 검사에 포함하지 않는다. 소스/문서/QA만 이미 승인된 private branch로 push한다.

## 구현 및 검증

- `Sources/CirclrApp/AccessibilityGeometry.swift`: AppKit screen conversion과 부모 AX frame의 차이로 부모 좌표를 계산한다. flipped view의 위아래 반전과 bounds origin을 임의 가정하지 않는다.
- `StepEditor.swift`, `EditorView.swift`, `OrbitMIDIEditor.swift`, `AutomationEditor.swift`, `AlbumCanvas.swift`, `CanvasConnectionNavigation.swift`: 공통 계산을 사용한다. 음악/agent protocol/kit 계약은 유지한다.
- `qa/AccessibilityGeometryChecks.swift`: 실제 AppKit 부모/자식 좌표, 창 이동, scroll, bounds/size 변경을 같은 production helper로 확인한다.
- `qa/prepare-accessibility-geometry-qa.py`, `qa/verify-accessibility-geometry-native.py`, `qa/check-accessibility-geometry-evidence.py`: signed candidate와 authored 사본, 전체 음악/소스 보존, 실제 스텝 선택·셀 입력·Undo·스크롤/검색 및 MIDI/오토메이션/서클 경로의 증거를 대조한다.
- release build, `swift-local.sh test --scratch-path .build/accessibility-geometry-quality --skip testArrangementRenderExportAndPlayback`, 기존 Python MCP/kit 검사. 테스트 수치로 VoiceOver 발화나 물리 장치 작동을 주장하지 않는다.

## 원인 조사 근거

build69의 실제 보이는69번 행 클릭에서도 동일한 오류를 재현했다. AppKit 단독 실험에서는 `setAccessibilityFrame`의 최초 좌표는 일치했다. 따라서 최초 setter 자체가 항상 빈 frame을 반환한다고 단정하지 않는다. Apple은 가상 요소에 [부모 기준 frame](https://developer.apple.com/documentation/appkit/nsaccessibility-c.protocol/accessibilityframe)을 권장하며, [부모 이동을 따르는 계약](https://developer.apple.com/documentation/appkit/nsaccessibilityelement-swift.class/accessibilityframeinparentspace)을 명시한다. flipped view에서 local rect를 그대로 부모 AX 좌표에 넣으면 Y가 반전되어 실제 변환이 필요하다.

## 최종 결과

부모 좌표만 적용한 최초 후보는 스크롤 경계에서 객체가 바뀌어 여전히 실패했다. 같은 편집 문맥에서 행/셀 객체를 재사용하고 identity/페이지/격자 변경 시 초기화해 최종 후보에서 해결했다. 실제8종 선택·입력/Undo·검색/페이지·창 크기·저장 재열기와 AppKit14개, Swift491개/Python29개, native14상태/21화면을 검증했다. 음악·자산·서명을 대조하고 세 QA 앱을 종료했다. 후보별 실패/성공과 남은 범위는 [QA](../qa/accessibility-geometry-review.md)에 기록했다.
