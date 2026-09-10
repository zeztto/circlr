# 오디오 편집 Undo·Redo의 작업 위치 복귀

상태: build143 오디오 history 복귀의 최종 후보를 검증했다. 최종 state 독립 감사는 PASS, UI 감사는 `PASS_WITH_SCOPE_LIMITS`다. 기준 HEAD는 `acc3ef3`이며 아래 실행 범위와 남은 공유 화면 가시성 문제를 구분한다.

## 확인한 문제와 수정 범위

build142의 split Undo는 음악을 정확히 복원했지만 overview로 이동해 파형에서 연속 편집하는 흐름이 끊겼다. 음악 복원과 편집 위치 복원을 별도로 다룬다.

오디오 split·duplicate·delete history에 세션 내 before/after 편집 상태를 연결한다. Undo·Redo 시 현재 주소·scope·공유 clip이 해당 작업의 복귀 조건과 일치할 때만 파형 작업 위치를 복원한다. 사용자가 다른 노드나 다른 공유 clip으로 이동했다면 그 탐색을 유지하며 이전 편집기로 강제로 돌아가지 않는다. Core 음악 변경·Undo 데이터 계약은 바꾸지 않는다.

복귀 상태는 transient이며 저장된 편집 view의 재열기와 history ticket의 세션 간 영속화를 구분한다. 취소한 작업은 history를 만들지 않는다. 삭제 뒤 target 존재 여부와 공유 clip identity를 확인하고 임의의 첫 clip으로 이동하지 않는다.

## 검증 계획

- 일반/공유 오디오 split→Undo→Redo에서 음악과 의도한 편집 주소·scope·파형 viewport를 대조한다.
- delete→Undo에서 원래 clip과 파형 복귀를 확인하고 duplicate의 전후 target·Undo를 검사한다.
- 작업 후 다른 노드 또는 같은 공유 source의 다른 clip으로 이동한 경우 Undo가 음악만 복원하고 현재 탐색을 유지하는지 확인한다.
- 취소가 history·음악·revision을 만들지 않는지, 저장/재열기가 저장된 편집 화면을 복원하는지 검증한다.
- 실제 실행한 모드·작업과 source 검토 범위를 구분하고 AX/JPEG·manifest·자산을 비교한다. 물리 I/O·청취·전체 편집 history 완료는 별도 조건이다.

## 별도 UX 후보

긴 캔버스 이름이 잘리는 현상은 multi142에서 관측했으며 hover 표시도 한 줄인 점을 읽기 전용 검토에서 확인했다. `StudioRouteBar`의 일반 HStack에는 폭 부족 fallback이 없어 보이지만 native 재현은 아직 없다. 두 항목은 다음 후보이며 이번 오디오 history 구현 완료에 포함하지 않는다.

## build143 후보와 최종 검증

초기 `audiohistory143-final`은 Release 49.11초·관련 테스트 43개와 package 검사를 통과했다. native 22쌍 감사는 공유 복귀의 focus가 window에 남아 PARTIAL이었다. 일반 split Undo/Redo·delete Undo·duplicate Undo/Redo·다른 노드에서 Undo 시 탐색 유지와 공유 마지막 clip 삭제 Undo는 확인했지만, 이 결과로 공유 focus까지 통과했다고 선언하지 않는다.

공유 branch의 focus request, 이전 clip view의 isCurrent 검증과 mount gap 대기를 수정한 `audiohistory143-verified` Release는 45.24초에 통과했다 (`.build/build143-verified-release.log`). package.json UUID는 `FBCEDA94-58EE-36B5-AE34-47A414F6DE36`이며 package 독립 감사도 PASS했다.

최종 native에서는 공유 split Undo/Redo와 duplicate Undo가 파형 focus로 돌아오고 Tab으로 수치에 접근했다. 일반 split Undo/Redo 및 다른 노드의 Undo 시 탐색 유지도 재검증했다. 원 fixture는 r194→198에서 baseline 음악으로 복구했고 저장/재시작의 전체 음악·hierarchyView·runtime이 정확히 같았다. 일정 tempo 전용 사본은 초기 r194에서 consumer use의 tempo override 2개만 제거해 만들었으며 공유 작업 r204 후 해당 사본 기준으로 복원했다. 원 fixture와 전용 사본의 baseline을 혼합하지 않는다.

최종 state 독립 감사는 PASS, UI 감사는 `PASS_WITH_SCOPE_LIMITS`다. 공유 화면의 첫 수치가 화면 아래에 있는 가시성 문제는 별도 개선으로 남겼다. Tab 접근 성공을 전체 수치 가시성 완료로 세지 않는다. 모든 scope·빠른 입력/IME·장치 I/O·전체 suite는 이번에 검증하지 않았다. 전체 DAW 목표는 유지한다.

최종 state 감사는 캡처 5개에서 원 fixture와 일정 tempo 사본의 경로별 split·복원·자산 6개 SHA 및 재시작 전체 상태를 확인했다. UI 감사는 15쌍에서 공유 파형 focus 53 복귀와 Tab으로 배치 2 수치의 가시성을 확인했다. 재시작 직후 canvas focus는 창 활성화 전 상태이므로 재시작 키보드 조작 성공으로 주장하지 않는다. 모든 QA 앱을 종료했고 사용자 PID 86114는 유지했다.
