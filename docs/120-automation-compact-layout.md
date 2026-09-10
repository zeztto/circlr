# 작은 오토메이션 편집기의 곡선과 입력

상태: build105 Release38.43초·아래 native/checker·시각 검토 통과.

## 기준 근거

build104 실제 compact에서는 도구 글자는 읽혔지만 plot이 약50px이고 숫자 9 눈금 하나만 보였다. 소스의 고정 최소폭615가 가용591을 넘는 문제와 실제 작은 plot 관측을 구분한다.

baseline은 빈 revision20에서 Return 두 번으로 점2개를 만든 revision22이며 compact 기준 JSON도 revision22·2points다. 이후 무변경 비교를 점 생성 전 revision20에 잘못 맞추지 않는다.

## 배치와 입력 계약

compact 폭700 미만은 adaptive170/210·gap12×2, wide는 기존225/250·gap20을 사용한다. stable identity를 유지해 폭 전환의 선택·초안이 재생성되지 않게 한다.

도구 flow, 숫자 Tab/Shift+Tab·reveal과 수치 입력 버튼을 제공한다. 레이아웃 이동만으로 점·음악·revision을 바꾸지 않는다. 기존 curve 선택·편집·Undo 의미를 유지한다.

## 검증 기준

1. 기준 compact에서 plot 크기·눈금과 도구 접근을 실제 geometry/화면으로 확인한다.
2. 폭 전환의 선택·초안과 도구 flow를 확인한다.
3. 수치 입력 버튼·Tab/Shift+Tab·reveal·잘못된 입력·취소·Undo를 검증한다.
4. 점2개 기준의 음악 보존·저장 재열기와 최종 Release·QA의 실제 범위만 완료로 기록한다.

사용자 앱과 물리 출력 조건은 별도 유지한다. 소스 폭 계산을 실제 가시성 통과로 대신하지 않는다.

## 최종 후보 검증

UUID `C8CD3657-8610-324F-9055-5248741EC6EB`. compact plot 약160px(기준 약50),1/5/9/13 눈금·64beat 표시를 확인했다.

초안2.를 wide/compact 줌 왕복에 보존하고 Esc로 취소했다. 위치2.5 입력은 beat1.5 revision23·Undo24로 정확히 복원했다. Shift+Tab gain·invalid999 차단/Esc를 확인했다. 빈 pan에서 Return으로 점을 추가25, Shift+Tab pan→position→Tab pan의−25%가−0.25로26에 반영됐고 Undo 두 번28로 원래 gain2points를 복원했다.

수치 입력 버튼은1.25 field 선택을 확인했다. 최소 폭 linear 표시의 겹침은 없었고 더 낮은 줌에서 editor가 닫히는 것은 기존 기대 동작이다. 하단 안내는 우측 스크롤 아래에 있어 전체가 동시에 보인다고 표현하지 않는다.

checker baseline1+final9 상태·자산2개·정확한 음악 delta/복원·source hash·strict reopened revision28·completed open job과 시각 검토를 통과했다. physical0이며 검증 종료 후 기존 사용자 PID86114만 유지했다.

resize drag guard는 소스에 포함했지만 실제 동시 drag/resize는 검사하지 않았다. 원본 범위 사용 불가 group·IME·대량 point도 native 미검증이다.
