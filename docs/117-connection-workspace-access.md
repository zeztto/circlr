# 좁은 연결 편집기의 목록 접근

상태: build102 final2 Release38.32초·아래 native/checker 통과. 첫 Release39.90초 후보와 최종 키보드 수정 결과를 구분한다.

## 실제 기준 재현

build101 compact viewport 높이 약230에서 compose 높이340 뒤의 기존 연결3개가 모두 화면 밖에 있는 것을 확인했다. 기준 화면은 `qa/generated/connection-access/baseline/compact.png`다.

## 이동 계약

compact의 고정 jump bar에 ‘연결 만들기’·‘기존 연결 N개’를 제공해 compose와 목록으로 직접 스크롤한다. 목록에서 재연결을 선택하면 compose로 이동하고 search에 focus한다. wide의 기존 두 열 배치는 유지한다.

query·ports·octants·replacing 상태는 이동 중 보존한다. jump와 focus 이동만으로 프로젝트 음악·revision·실제 연결을 변경하지 않는다. 연결 적용은 기존 확정 동작과 검증을 따른다.

## 검증 조건

1. 기준 compact 높이에서 기존 연결3개로 직접 이동하고 compose로 돌아올 수 있다.
2. 목록의 재연결 선택이 compose·search focus로 이어진다.
3. 이동 전후 query·ports·octants·replacing을 비교하고 의도하지 않은 초기화를 막는다.
4. wide 두 열과 기존 연결 편집·취소·Undo의 필요한 경로를 확인한다.
5. UI 이동의 프로젝트 무변경과 실제 적용 결과를 구분하고 최종 Release·native·QA 범위만 완료로 기록한다.

사용자 앱을 유지하며 physical 출력은 실행하지 않는 범위다. 이 접근 개선을 연결 신호나 정상 출력 검증으로 확대하지 않는다.

## 중간 후보와 후속 수정

첫 후보에서 mouse jump·목록 이동·query 보존을 확인하고 compact/query/list/query-return 증거를 보존했다. 그러나 keyboard jump order−90/−80이 header 앞에 있어 search에서 Shift+Tab 두 번으로 header 설정까지 우회하는 문제를 발견했다.

final2는 jump order를−7/−6으로 옮겨 header−8 다음·기존 own10 이전에 둔다. 최종 키보드 관측은 아래에 기록하며 첫 후보의 mouse 근거와 구분한다.

## 최종2 관측과 제한

Release38.32초, UUID `36B23420-6ADF-3A38-8347-FEAC5E6F4C38`. search에서 Shift+Tab 두 번·Return으로 기존 목록의 filter70/첫 row를 노출하고, row 재연결 click으로 compose/search20에 이동했다. replacement source/destination·target·octants는 목록/입력 왕복에 유지됐고 취소로 reset됐다.

wide 두 열·compact 왕복의 workspace를 보존했다. 다만 폭 전환 때 focus는 window로 돌아간다. 기존 분기 구조에서 남은 UX이며 포커스 보존 성공으로 계산하지 않는다.

checker는 baseline1+first4+final9의14개 상태·focus AX5개·음악 revision36 불변·자산2개·studio SHA 보존·resized/reopened/disk strict 일치와 completed open job을 확인했다. 검증 앱 종료 뒤 사용자 PID86114만 실행됐으며 physical0이다.

실제 케이블 적용·빈 연결·그룹 관리·외부 intent는 이번 native에서 검사하지 않았다. 기존 source call 경로 확인을 이 동작의 실제 검증으로 확대하지 않는다.
