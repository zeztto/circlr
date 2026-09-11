# MIDI 선택 바로 보기 — build 72

planning-gate-v1: development-lead. 기준767ed72, integration worktree만 수정. 직전 agent 호출이 실제 슬롯 제한으로 실패했으므로 UX → native utility → review → QA 순차 실행.

피아노 롤 상단에서 선택 보기 또는 F로 선택 위치에 바로 돌아온다. 현재 음역 폭과 시간 배율을 유지한다. 다중 선택이 27행/현재 화면에 들어가면 전체를 보여주고, 범위를 넘으면 기준 노트를 보여준다. 고정 시간 눈금20px·건반60px을 가시 영역에서 제외한다. 자동 탐색과 드래그 동작은 유지한다. 음악 revision/Undo/선택ID는 변경하지 않는다. 저장된 스크롤을 무조건 덮어쓰지 않고 사용자의 명시적 요청으로 이동한다.

소유: MIDIGridWorkspace.swift, EditorView.swift; 필요시 전용 geometry utility와 검사. 검증: 음역 위/아래 경계, 가로·세로 스크롤, 다중 선택/넓은 선택, F/상단 버튼, 선택 없음, 저장 복원 후 이동, 음악 보존. 기존 앱과 원본 프로젝트를 보존하는 고유 QA 사본 사용. 물리 오디오 검증과 사용 앱 교체는 별도다.

## 결과

작은 창에서 여백과 F keyCode를 보완한 최종 후보를 검증했다. Swift496개·Python29개, native9상태와 음악/자산 보존 통과. 자세한 실패·수정·최종 근거는 [QA](../qa/selection-reveal-review.md)에 기록했다. 전체 개발 목표는 진행 중이다.
