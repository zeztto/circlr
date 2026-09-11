# 공유 오디오 편집기의 상단 밀도

상태: build144 배치 개선의 Release·native 검증을 완료했다. 최종 UI 독립 감사는 12쌍에서 `PASS_WITH_SCOPE_LIMITS`, state 감사는 4개 캡처에서 PASS다. 기준 HEAD는 `292dd40`이다. 아래 실행 범위를 전체 DAW 완료로 확대하지 않는다.

## 확인한 문제와 구현 범위

build143 verified 공유 오디오 화면은 상단 picker/count 행과 아래 scope/asset 행이 정보를 중복해 첫 수치 4개가 화면 아래로 밀렸다. Tab 접근과 최초 가시성은 다른 조건이며 기존 history 복귀 통과로 이 문제까지 해결됐다고 세지 않는다.

부모 picker 행에 scope 안내를 합치고 공유 오디오의 아래 중복 행을 제거한다. 일반 오디오 배치는 유지하며 이번 단계에서 파형 높이는 변경하지 않는다. 키보드·수치 guard와 음악 편집 계약도 그대로 유지한다. 같은 공유 패턴을 사용하는 모든 곳에 반영된다는 안내가 공간 절약으로 사라지지 않아야 한다. 이는 서클의 editOriginal 토글과 별개다.

## 검증 기준

- 기존과 같은 작은 창·콘솔 조건에서 공유 picker/count/scope 안내와 첫 수치 4개가 함께 보이는지 AX/JPEG로 비교한다.
- 공유 clip 선택과 Tab·Shift-Tab, invalid 수치·취소, 기존 Undo/Redo 복귀를 실제 실행한 범위에서 확인한다.
- 일반 오디오의 파형·수치·작업 버튼 배치가 바뀌지 않았는지 비교한다. 순수 화면 이동의 음악·revision·자산 불변을 대조한다.
- 실제 창 크기·실행 동선·패키지·검사 결과를 확보한 뒤 완료를 기록한다. 물리 I/O·청취·모든 접근성 조합은 별도 검증이다.

## 긴 캔버스 이름의 후속 범위 정정

`AlbumCanvas`에는 전체 title+subtitle tooltip과 전체 이름 AX가 이미 있다(현재 소스의 203행·701행 부근). 따라서 전체 이름을 보려면 반드시 선택해야 한다고 단정하지 않는다. 실제 native tooltip 표시는 아직 검증하지 않았으므로 기존 지원과 실제 표시 결과를 구분한다.

단순 hover 확대는 layout 깜빡임과 포트 가림 위험이 있으며 이번에 구현하지 않는다. 길이 문제의 후속 결정은 먼저 기존 tooltip의 native 표시를 확인한 뒤 내린다.

## build144 결과

Release는 46.26초에 통과했다 (`.build/build144-release.log`). package 독립 감사도 PASS했다. 시각 배치 변경이므로 구현을 그대로 따라 쓰는 추가 unit test나 전체 suite는 실행하지 않았다. build143의 43개 검사를 build144 결과로 다시 세지 않는다.

`audioheader144/shared-two-clips` r205의 최초 화면에서 picker·공유 경고·action·파형·수치 4개가 동시에 보였다. Tab의 수치 순서 4개와 파형 유지를 확인했다. 첫 Tab에서 22px 자동 스크롤로 action이 가려지는 현상은 별도 한계이며 모든 focus 위치에서 전체 action이 보인다고 주장하지 않는다.

Undo r206·Redo r207, clip 변경·Undo r208 후 baseline r204 음악으로 정확히 복원했다. 일반 오디오 진입과 공유 복귀 r208도 확인했다. 일정 tempo 사본의 저장/재열기 전후 r208 전체 manifest·hierarchyView·주소는 정확히 같았다. 고정 경로 verifier는 다른 사본 경로를 정상적으로 거절했으며 해당 사본을 명시한 별도 비교로 검증했다. QA 앱을 종료하고 사용자 PID 86114를 유지했다.

최종 UI 독립 감사는 12쌍에서 `PASS_WITH_SCOPE_LIMITS`, state 감사는 4개 캡처에서 PASS다. 긴 이름 tooltip·더 좁은 폭의 줄바꿈·VoiceOver·물리 I/O는 이번에 실행하지 않았다. 전체 목표는 계속 남아 있다.

UI 감사는 일반 scope·asset 표시와 재열기 후 수치 4개·파형 52를 확인했다. narrow wrap과 긴 이름 표시는 이번 실행 범위에 포함하지 않는다.

state 감사는 일정 tempo 사본의 shared split·r208 복원·전체 manifest 재열기와 원 fixture r198 보존, 두 경로 각각 자산 6개 SHA를 확인했다. 이번 재열기는 같은 앱 세션에서 파일을 다시 연 것이며 앱 프로세스 재시작은 수행하지 않았다.
