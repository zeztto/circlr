# Router 경로 전송량의 dB 편집과 정밀도

상태: build92 Core19개·최종 Release41.35초 및 아래 native 검증 확인. QA 최종 대조 통과. [QA](../qa/router-level-review.md).

## 실제 기준 재현

기존 UI에서 IN1→OUT1의 선형 gain0.5011872336을 수정 없이 Return으로 확정하자0.5로 저장되고 revision28→29로 바뀌었다. 경로 순서도11,22에서22,11로 바뀌었다. Undo로 revision30에서 원래 음악을 복원했다. 표시 반올림을 확정값으로 다시 저장하는 동선과 경로 재정렬을 함께 방지한다.

## 편집 계약

- App의4개 경로 전송량을 dB로 표시하고 `GainFader`·`CommittedNumberField`를 사용한다. 수치 입력과 Tab 순서를 제공한다.
- 수정하지 않은 Return은 기존 정밀한 선형 값을 유지한다. 저장·MCP·renderer의 gain 단위는 선형으로 유지한다.
- `AudioRouterEditing`은 명시한 대상과 이번 사용/공유 원본을 분리하고 expected guard로 오래된 요청을 거절한다.
- 공유 원본 set은 effective 값 전체를 원본으로 복사하지 않는다. 이번 사용 override가 원본을 오염시키지 않게 한다.
- 기존 route 순서를 유지하고 대상 경로만 변경한다. 원본/이번 사용 범위와 한 번의 Undo를 유지한다.

## 검증 완료 기준

1. 기준 gain0.5011872336에서 untouched Return의 음악·revision·route 순서 불변을 확인한다.
2. 네 경로 dB 입력·Tab·취소·오래된 요청 거절과 의도한 선형 값 반영을 확인한다.
3. 공유 원본/이번 사용 수정의 분리, effective 값의 원본 유입 방지, 다른 경로·다른 대상 보존을 검사한다.
4. route 순서·Undo·저장/재열기와 작은 창의 접근성을 확인한다.
5. 최종 테스트·Release·native·QA 근거가 확보된 범위만 완료로 기록한다.

사용자 앱과 physical 출력 상태를 보존한다. 이 편집 수정으로 출력 장치 문제 해결을 주장하지 않는다. 앱별 출력 장치는 별도 계획이며 구현·검증 완료와 구분한다.

## 최종 후보의 확인 범위

- Core19개 (`.build/router-level-tests.log`), 최종 Release41.35초 (`.build/router-level-release-final.log`), UUID `F09EA2C6-0219-3705-A78B-7094AD718D6C`. 동시 수정 감지로 중단한 첫 빌드는 통과 근거에 포함하지 않는다.
- revision30 untouched precision/no-op, 네 경로 Tab 입력34·Undo4 후38, 삭제/추가·Undo 후42를 확인했다.
- slider 직접 click·Right0.5dB/Undo 후46, 공유 원본22 경로만 수정47·Undo48, invalid/cancel/stale switch에서48 유지 확인.
- 이름·cross preset 한 click50·Undo52, 수치 초안 중 default preset53 뒤 늦은 Return 거절53·Esc/Undo54 확인.
- 1020×768·scroll1 유지와 revision54 saved/reopened 전체 manifest strict 동일 확인. QA checker가 baseline3개·후보25개·AX12개·자산2개·physical0을 대조해 통과했다.

원본 안전성은 이번 명시 대상 route helper와 해당 native 범위로 한정한다. 일반 `updateMusic`이나 다른 편집기의 원본 안전성으로 확대하지 않는다. 물리 출력0회·사용자 앱 보존을 유지한다.
