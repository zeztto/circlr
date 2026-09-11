# MIDI 편집 작업 도구의 전체 폭 배치

상태: build97 Release38.38초·아래 native 확인. QA checker 최종 대조 통과. [QA](../qa/workflow-visibility-review.md).

## 기준 재현과 표시 계약

build96 native에서 MIDI Orbit의228pt 왼쪽 footer에 menu·bounce·record가 몰려 MIDI 메뉴가 숨는 것을 확인했다. 공통 toolbar를 전체 편집 폭에 배치해 mode·MIDI 메뉴·bounce·record에 접근할 수 있게 한다. Orbit 이전/다음·count도 이 배치에 맞춰 이동한다.

Grid도 inspector 폭에 묶이지 않는 전체 폭 toolbar를 사용한다. 편집기 내부의 기존 canvas는 유지한다. 숨은 기능을 복제 패널로 늘리거나 데이터 편집 의미를 바꾸지 않는다.

## 검증 조건

1. 작은 창·콘솔 열림에서 mode·MIDI 메뉴·bounce·record와 Orbit 이전/다음·count가 보이고 선택 가능하다.
2. Orbit/Grid 전환 시 inspector와 독립된 도구 폭을 유지하고 canvas의 편집·선택·키보드 동선을 보존한다.
3. 메뉴 실제 열기·탐색·취소와 현재 대상 표시를 확인한다. bounce/record 표시를 실제 렌더·입력 녹음 성공으로 확대하지 않는다.
4. 음악·revision 보존과 필요한 Undo·저장/재열기를 검사하고 최종 Release·native·QA의 실제 범위만 완료로 기록한다.

## 최종 후보의 실제 범위

Release38.38초, UUID `A2991ADB-048F-3EE2-B41E-3B731FB9B92E`. baseline snapshot1/AX2/PNG2와 final snapshot19/AX12/PNG11을 수집했다. 수집량은 snapshot20/AX14/PNG13이다. checker는 상태20개와 AX 내용6개를 대조했다. 원본 자산2개·offline bounce1개·physical0도 확인했다.

실제1020×768·콘솔 기본122/compact40에서 Orbit·step·drum step·piano 메뉴/bounce/record 가시성을 확인했다. note66→67·Undo, 직접⌘A로3개 선택→Delete0→Undo를 확인했다. 실제 바운스는34초·48kHz·24bit stereo, peak0.0951693·RMS0.0095503이며 Undo 뒤 음악·원본 자산2개를 복원했다. revision30의 saved/reopened/disk manifest는 전체 strict 동일하다.

메뉴 전체 선택 click 두 번은 효과를 확인하지 못했다. 메뉴 탐색 Down이 노트 편집으로 전달돼 Undo로 복원했다. 메뉴 항목 노출을 action 성공으로 해석하지 않으며 이후 직접⌘A의 성공과 구분한다. 실제 MIDI 녹음·물리 출력은 실행하지 않았다. 사용자 dist PID86114를 보존하고 검증 앱을 종료했다.

## 후속 UI 조사

`UnifiedSectionView`에서 isEnd가 켜져도 다음 edge가 active로 표시되어 compiler의 의미와 다를 수 있다. 종료 표시·연결 표현을 compiler와 대조하는 별도 과제로 유지한다.

`ArrangementPicker`에서 다른 candidate를 복제하려면 먼저 현재 안으로 적용해야 하는 왕복도 후속 과제다. 명시한 candidate 복제의 대상·선택 보존 계약을 먼저 정의한다. 두 과제는 이번 toolbar 작업에 구현된 기능이 아니다.
