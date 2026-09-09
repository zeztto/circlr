# 연결 편집기 폭 전환의 focus 유지

상태: build104 final3 Release40.00초·아래 native/checker·시각 검토 통과.

## 기준 재현과 계약

build103 실제 native에서 연결 editor 폭800 분기의 control 재생성 뒤 search focus가 window로 빠지는 것을 확인했다. 폭 전환에서도 사용 중인 search와 편집 상태가 이어지도록 개선한다. 동일한 `ScrollViewReader`·outer `ScrollView`·`PortConnectionColumns` Layout과 compose/list `ScrollView`를 유지한다. compact는 내부 스크롤을 비활성화하고 측정한 목록 높이를 사용하며 wide는 내부 스크롤을 사용한다. 폭 전환 시 focus를 새로 설정하지 않고 현재 responder를 reveal한다. jump bar는 같은 identity로 유지하되 wide에서는 숨김·disabled·AX hidden 처리한다. connections 전용 reanchor로 목록 이동을 정렬한다.

query·ports·octants·replacing 상태와 기존 compact jump/wide 두 열 동작을 유지한다. 폭만 바꿔 프로젝트 음악이나 revision을 변경하지 않는다.

## 검증 조건

1. search 입력 중 compact↔wide 왕복에서 focus와 query를 유지한다.
2. 재연결 입력·취소와 기존 목록 이동의 상태를 보존한다.
3. 음악/revision·자산 보존과 필요한 저장 재열기를 대조한다.
4. 최종 Release·native·QA의 실제 관측 범위만 완료로 기록한다. 사용자 앱·물리 출력 문제는 별도 유지한다.

## 후보별 관측과 남은 수정

초기 Release41.24초 (`F7CACE1D-E4E8-384F-B5B8-D932E8658474`)는 search 선택/caret와 filter focus의 폭 왕복을 확인했으나 compact 목록 jump의 빈100px·row 잘림을 발견했다. query ‘출X’는 caret 삽입/forward-delete 검사 중 만든 입력이며 음악 revision36은 유지됐다.

reviewed final2 Release40.08초 (`BD28DD23-892B-36D0-BD36-0E7C1078F22A`)에서 목록 jump·filter focus wide/compact·재연결 키보드와3개 상태의 revision36 불변을 확인했다. 그러나 target list가 전체 table bounds를 reveal해 선택 행이 화면 밖에 남았다. final3에서 focus/resize의 selected row rect reveal을 수정했다. 앞선 부분 성공과 최종 근거를 구분한다.

## 최종3 근거와 제한

Release40.00초, UUID `B16B8E8C-434B-3D8F-BB19-23EAF5BC3737`. 공통 `PortKeyboardFocus`에 선택 행의 inner/outer reveal helper를 추가했다.

실제 target compact/wide/return에서 파란 mix 행 전체가 보였다. search compact/wide/return의 선택 ‘출력’을 유지하고 caret 사이 삽입 ‘출X력’을 확인한 뒤 ‘출력’으로 복원했다. 목록 jump의 heading·첫 row 버튼이 온전했고 filter wide/return focus도 유지했다. Tab/Return 재연결과 취소를 확인했다.

최종 snapshot5개는 target-roundtrip/search-roundtrip/reconnect/cancelled/reopened다. checker는 후보 이력을 포함한 전체11개 상태의 음악 revision36 불변·자산2개·source hash·strict manifest/disk·completed open을 통과했다. 시각 검토 통과·physical0, 검증 앱 종료 뒤 사용자 PID86114만 유지했다.

실제 케이블 적용·그룹 관리·IME composing·숨은 jump 버튼 focus의 폭 전환은 검증하지 않았다. compact에서 target을 reveal하면 상단 port actions는 스크롤 위로 밀리므로 동시에 노출한다고 표현하지 않는다.
