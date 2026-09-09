# 편곡 후보의 직접 복제

상태: build99 Core11개 실패0·0.007초·source guard review·Release41.58초·strict 서명 및 아래 native 확인. QA 최종 대조 통과.

## 사용자 동선과 데이터 계약

각 편곡 후보 행에서 해당 안을 직접 복제한다. 현재 안으로 먼저 적용할 필요가 없으며 ⇧⌘D는 강조된 candidate를 사용한다. 이름 변경은 현재 편곡 대상임을 명시한다.

복제 이름 입력을 시작하면 원본 arrangement ID를 고정하고 입력 중 다른 행 전환을 잠근다. 취소는 음악·선택을 변경하지 않는다. 확정은 한 번의 mutate로 clone과 select를 적용하고 한 번의 Undo로 복원한다. 검색 결과0개·오래된 대상·프로젝트/편집 세션 변경을 의도치 않은 다른 안의 복제로 처리하지 않는다.

## 검증 기준

1. 현재 A를 유지한 채 B 행에서 복제를 열고 취소했을 때 무변경을 확인한다.
2. B 직접 복제·선택과 한 Undo 복원, 키보드 B 강조·⇧⌘D 복제를 확인한다.
3. 검색0개, 현재 안 이름 변경의 명시 대상, 입력 중 행 잠금과 stale 거절을 확인한다.
4. 원본 ID 고정·원본/다른 편곡 보존·저장 재열기를 검사한다.
5. 최종 Release·native·QA 근거가 확보된 범위만 완료로 기록한다.

build98 문서의 다른 후보 직접 복제 미구현 표기는 당시 상태다. 이번 build99의 진행과 구분하며 사용자 앱·물리 출력 조건을 유지한다.

## 최종 후보 관측

UUID `51D8950A-2082-3E72-BF4C-3D20D110F369`, 실제1020×768에서 다음을 확인했다.

- B행 입력 취소 revision14, B행 복제15·한 Undo16.
- Down/⇧⌘D/Return의 B복제17·Undo18. 검색0에서 복제 비활성, 현재A 이름 변경 입력 취소18.
- B복제 입력 중 외부 MCP로 A반복2 변경19 후 Return은 거절되고 전체 manifest strict 불변19. Undo20·재열기 strict20.
- 최종 B복제21·저장 재열기 strict21. 자산2개·output/audition0, AX/PNG 각7개 수집. 검증 앱 종료, 음악 재생 미실행.

## 재현 도구

[fixture 준비](../qa/prepare-arrangement-candidate-qa.py), [native 캡처 helper](../qa/verify-arrangement-candidate-native.py), [증거 checker](../qa/check-arrangement-candidate-evidence.py)를 사용한다. 지정 fixture와 QA 앱을 준비한 뒤 `python3 qa/verify-arrangement-candidate-native.py <새-label>`로 상태를 보존하고 `python3 qa/check-arrangement-candidate-evidence.py`로 대조한다. 최종 checker는 native14개·AX5개 검사·자산2개 보존·physical0을 통과했다. AX7개/PNG7개는 수집량이며 PNG7개 직접 시각 검토도 통과했다. 종료 후 기존 사용자 PID86114만 남았음을 확인했다.
