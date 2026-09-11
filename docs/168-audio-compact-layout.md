# 낮은 화면의 오디오 편집 배치

상태: build146 Release·아래 native 배치/입력 검증을 완료했다. data 독립 감사는 PASS_DATA_ONLY, 최종 UI 감사는 PASS_WITH_SCOPE_LIMITS다.

## 구현 범위

`AudioWorkspace.swift`에서 `AudioWaveformFieldsLayout`의 availableHeight가 240 미만이고 폭이 600 이상·800 미만일 때 같은 ScrollView 안에 112pt 파형과 즉시 생성되는 수치 8개를 나란히 배치한다. 두 영역의 폭은 각각 `(width - 16) / 2`이며 동일 subtree를 유지한다. 높은 화면과 좁은 화면은 기존 세로 배치를 유지한다. 별도 고정 패널을 만들거나 편집 scope·음악 계약을 바꾸지 않는다.

목표는 compact 최초 화면에서 작업 버튼·파형·첫 수치 4개를 함께 표시하는 것이다. Tab/Shift-Tab, invalid 수치 guard와 공유 scope 안내를 유지한다. 수치가 존재한다는 것과 실제 보인다는 것을 구분해 검증한다.

## 검증 기준

- 낮은 높이·충분한 폭에서 action·파형·첫 수치 4개 동시 가시성을 실제 AX/JPEG로 확인한다. 높은/좁은 조건의 기존 세로 배치도 비교한다.
- 일반·공유 오디오의 수치 순서·Tab/Shift-Tab·오류/취소, 파형과 scope를 확인한다. 실행하지 않은 조합은 source 검증과 구분한다.
- 순수 화면 전환의 음악·revision·자산 보존과 저장된 workspace를 대조한다. 모든 폭·접근성·물리 I/O·청취 완료로 확대하지 않는다.

이전 build145의 route 배치와 남은 compact 수치 문제를 기준으로 비교한다. 테스트·빌드·native 결과는 실제 수행 후 추가한다.

## build146 실행 결과

Release는 48.74초에 통과했고 source·package 감사도 PASS했다. source binding을 바꾸지 않은 배치 변경이며 전체 suite는 이번에 실행하지 않았다.

`audio146-final`의 native 21쌍에서 공유 wide/compact와 일반 wide/compact 모두 최초 수치 4개·파형·action을 확인했다. Tab 1…8과 Escape, 배치 1→2 r209·Undo r210, invalid `x`에서 Command+J 거절·Escape 복구를 실행했다. F로 구간 확대, 분할 위치 0.517 클릭, Right로 trim 0.010 r211→Undo r212를 확인했다. data 독립 감사는 edited의 공유 clip beat 0→1만 변경됐고 restored r212의 음악은 initial r208 및 build145 baseline과 revision/hierarchy를 제외하고 정확히 같음을 확인했다. 자산 SHA 18건과 일정 tempo 사본 r208·원본 r198도 보존돼 PASS_DATA_ONLY다.

모든 폭·Shift-Tab·drag·수치 초안 중 resize·clip 변경·물리 I/O는 실행하지 않았다. QA 앱은 종료했고 사용자 production PID 86114는 유지했다. 실제 청취·전체 DAW 완료로 확대하지 않는다.

최종 UI 감사는 1019×768의 JPEG/AX 21쌍에서 `PASS_WITH_SCOPE_LIMITS`다. 일반·공유 compact의 action/파형/첫 수치 4개 동시 표시와 wide 유지, Tab 1…8의 실제 선택 text·Escape의 파형 55 복귀, 수치 편집/Undo·invalid x/Escape·click/trim/Undo를 확인했다. 뒤 수치 4개로 이동하면 action/파형 일부가 스크롤 밖으로 나가는 한계가 있다. native fallback·Shift-Tab·resize-draft·drag·clip 변경은 미검증이며 전체 배치 조합을 통과했다고 주장하지 않는다.
