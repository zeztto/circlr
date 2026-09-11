# 음악 그래프 편집 범위와 원본 보존

상태: build93 관련31개 테스트 실패0·최종 Release45.48초 및 아래 native 관측 확인. QA 최종 대조 통과. [QA](../qa/music-scope-review.md). 시작 기준은 build92 commit `2f4bafd`다.

## 문제 구분

일반 `updateMusic`에서 이번 사용의 effective 그래프를 읽고 공유 원본에 쓰면, 수정하지 않은 override까지 원본으로 전파될 위험이 있다. 이는 의도한 필드 외 원본 값이 바뀌는 경로로 검사한다.

`addedNodes`·`addedEdges`는 별도 경로다. ID collision으로 요청 전체가 실패하는 경우를 원본 전파 성공으로 기록하지 않는다. 실패의 원자성·원본 불변과 유효한 원본 필드 수정의 분리를 각각 확인한다. 실제 build92의 같은 fixture에서 공유 원본 audio 이름 변경이 ID collision alert로 거절되고 revision54가 유지됐다. 이 baseline은 오염 발생이 아니라 전체 실패 재현이다.

## 변경 계약

- 편집용 scope snapshot을 원본/이번 사용으로 명확하게 구분한다. 읽은 snapshot과 쓰기 대상 범위를 일치시킨다.
- 일반 `updateMusic`과 복합 effect 편집은 공유 원본 모드에서 원본 값을 읽는다. effective 전체를 원본에 덮어쓰지 않는다.
- Audio Unit 비동기 결과는 요청 당시 대상·scope·편집 세션을 검증한다. await 뒤 대상이 바뀌거나 요청이 오래되면 다른 범위에 적용하지 않는다.
- 이번 사용에만 존재하는 대상은 공유 원본에 없는 상태를 안내한다. 잘못된 값을 표시하거나 빈 본문만 남기지 않고 편집 범위를 직접 선택할 수 있게 한다.
- scope 선택 자체는 음악을 변경하지 않는다. 기존 명시 대상·expected guard·Undo와 다른 use의 보존 경계를 유지한다.

## 검증 완료 기준

1. 공유 원본과 이번 사용 override를 다르게 준비하고 단일 필드·복합 effect 원본 편집에서 의도한 원본 값만 바뀌는지 확인한다.
2. 이번 사용 편집은 해당 use에만 반영되고 scope 전환만으로 음악·revision이 바뀌지 않는다.
3. added ID collision의 전체 실패·무변경과 유효한 원본 수정 경로를 분리해 검증한다.
4. AU 비동기 요청 중 대상/scope 전환·취소·오래된 결과의 적용 거절을 검사한다. 실제 AU를 실행하지 못하면 그 범위를 명시한다.
5. 실제 UI에서 use-only 안내·범위 직접 선택·키보드·복합 effect·Undo·저장/재열기를 확인하고 다른 use의 음악을 보존한다.
6. group 선택 상태의 router 생성에서 올바른 parent를 해석하고 기존 group 기능·추가 대상·Undo를 보존하는지 검사한다. 첫 후보에서 발견한 회귀를 최종 후보에서 재확인한다.
7. 최종 테스트·Release·native·QA가 확인한 경로만 완료로 기록한다. 일부 helper의 통과를 일반 편집기 전체의 안전성으로 확대하지 않는다.

물리 오디오 지연·장치 선택·출고는 별도 조건이다. 이 scope 수정으로 정상 출력이나 기존 HAL 문제 해결을 주장하지 않고 사용자 앱을 보존한다.

## 최종 후보와 관측 범위

- 관련31개 테스트 (`.build/music-scope-tests.log`), 최종 Release45.48초 (`.build/music-scope-release-final.log`), UUID `6DAA541E-9E77-3F78-B1D3-54F72BFADFF2`. 첫 Release77.02초 뒤 발견한 group parent 회귀는 최종 후보에서 수정했다.
- baseline92 원본 audio 이름 변경은 ID collision으로 실패하고 revision54 유지. candidate는 원본 이름 변경55·Undo56, use-only effect 안내·복귀56 확인.
- effect−9dB 초안에서 원본 scope로 이동할 때 기존 use amount만 확정57·Undo58. group focus의 router 생성은 use added node와 layout만59·Undo60.
- effect−3dB 초안 중 target 변경은 음악60 유지. router 이름 초안에서 원본 선택 시 A override 이름만61로 바뀌고 UI header는 원본 이름 표시. 원본 이름 untouched Return61 무변경·Undo62.
- 1020×768 화면과 revision62 saved/reopened 전체 manifest strict 동일 확인. QA baseline2+candidate16의18개 snapshot·AX1+8의9개·자산2개·physical0 대조 통과.

실제 AU plugin의 비동기 native 동작은 검증하지 않았다. 코드 guard 확인을 실제 plugin 실행 성공으로 확대하지 않는다. 위 대상·scope 경로의 확인과 물리 오디오 문제 해결을 구분한다.
