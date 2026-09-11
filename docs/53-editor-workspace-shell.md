# 편집 위치와 작업 전환

2026-09-09, 기준 `95a492b`, `codex/daw-integration`, build 39. 이전 goal turn은 build 38 소스·검증·push로 progress다. development-lead → UI/UX → native Swift utility → read-only code/security review → QA 순차 수행. 실제 에이전트 한도 오류가 확인된 현재 호스트에서는 delegation none이다.

## 계약

같은 캔버스의 제목/작업 전환과 트랙 경로, 편집 본문, 하단 안내를 독립적으로 배치한다. 노트 선택 전후의 속성 높이나 MIDI 궤도/스텝·오디오·연결·오토메이션/설정 전환이 제목과 경로를 밀어내지 않아야 한다. 본문은 할당된 높이를 따르고 긴 조작 영역은 그 안에서 스크롤한다. 녹음 테이크 선택은 제목 도구 줄로 옮겨 존재 여부가 본문 높이를 바꾸지 않게 한다.

음악 서클의 작업 전환은 현재 콘텐츠 이름(MIDI/오디오/음색/이펙트/레벨/믹스/라우터), 연결, 오토메이션, 설정으로 명시한다. 현재 선택을 강조하고 해당 버튼의 접근성 selected 상태를 제공한다. 돌아가기 의미가 중복된 ‘편집으로’ 토글을 없애고 본문 버튼을 언제든 눌러 원래 편집으로 돌아갈 수 있어야 한다. MIDI import 초안 처리 중에는 이 전환을 막고 기존 초안 취소/적용 경로를 사용한다. 데이터 변경 없이 view state만 바뀐다.

설정 전환은 열린 `embeddedPlugin`을 정리한다. 본문의 플러그인 표시가 설정 표시보다 앞서므로, 이를 남기면 헤더 selected 상태와 실제 본문이 달라진다. 그룹의 콘텐츠 버튼은 설정 편집을 유지한 채 연결에서 돌아오며, 음악 서클에만 있는 설정 버튼을 요구하지 않는다.

MIDI 선택 속성과 궤도 탐색은 본문 높이 안에서 스크롤하여 작은 창에서도 모든 명령에 접근한다. 숫자 Tab/Return/Esc, 스텝 위치와 피아노 롤 선택 따라가기, 호스트의 프로젝트/대상 identity guard를 유지한다. 오디오의 긴 속성도 내부 스크롤로 접근하며 음소거·삭제는 파일 이름 옆으로 옮겨 잘림을 피한다. 작업 줄 사이 간격을 줄여 편집 면적을 확보한다. 창이나 dock를 추가하지 않는다.

## 소유와 검증

- Native Swift: `Sources/CirclrApp/InlineCircleEditor.swift`, 새 `InlineEditorHeader.swift`, `MIDINoteInspector.swift`, `MIDIOrbitWorkspace.swift`, `AudioWorkspace.swift`, `StudioNavigationView.swift`. 기존 UI/명령을 재사용하며 새로운 음악 모델이나 API/auth 계약을 만들지 않는다. 필요하면 본문 레이아웃에 맞춰 `MIDIGridWorkspace.swift`/`AutomationEditor.swift`의 최소 높이를 정리한다.
- QA: 기존 offline Swift와 Python 검사, release build. build 39 별도 앱/직접 작성한 fixture 사본에서 선택 없음/한 개/여러 개, 궤도/스텝/피아노, 연결/오토메이션/설정 왕복의 제목·경로·본문 위치를 실제 screenshot으로 확인한다. 숫자 입력·Undo·저장/재열기와 원본 보존을 함께 확인한다. 실제 출력·마이크는 시작하지 않는다.
- Git: 동일 승인된 private 브랜치에 소스·검사·문서만 커밋/push한다. QA 앱/미디어/프로젝트는 로컬에 남긴다. README/CHANGELOG/roadmap을 갱신한다. 전체 DAW 목표와 기존 출력·녹음 출고 조건을 유지한다.

## 실행 결과

최종 build 39의 Swift 325개·Python 26개 및 실제 입력·작업 왕복·원본 복원이 통과했다. 첫 후보의 오디오 하단 잘림을 내부 스크롤과 상단 명령 배치로 고쳤고, 코드 검토에서 설정/플러그인 상태 충돌과 그룹 도움말 중복을 수정했다. 후보별 검증 경계·최종 패키지 출처·남은 native 범위는 [QA 기록](../qa/editor-shell-review.md)에 있다. 사용자 앱 출고 및 전체 개발 목표 완료를 뜻하지 않는다.
