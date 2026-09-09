# 포트별 출력 도달성과 탐색 대상

상태: build90 대상 테스트·최종 Release·아래 native 관측 확인. QA 최종 대조 통과. [QA](../qa/port-navigation-review.md).

## 문제와 공통 계약

node 단위 도달성은 서로 독립된 router bus의 다른 트랙 대상을 함께 노출할 수 있다. 공통 Core structural port reachability로 `StudioNavigation.build`·`StudioNavigation.outputTracks`·`BounceAssessment`의 분류를 일치시킨다.

- router bus는 실제 route 연결을 따라 판정한다. 같은 node라는 이유만으로 다른 bus 경로를 합치지 않는다.
- mute 또는 gain0이어도 구조적 연결은 남는다. 소리가0이라는 이유로 탐색 대상을 제거하지 않는다.
- sidechain에만 연결된 대상은 main 출력 경로의 구성원으로 포함하지 않는다.
- lane 소유의 미연결 대상은 기존 편집 접근을 유지한다. 경로 밖이라는 사실과 편집 대상의 소유를 구분한다.
- UI 후보 목록과 선택 트랙 추론이 같은 판정을 사용한다. 목록에는 제외했지만 트랙 추론에는 포함하는 차이를 만들지 않는다.

## 검증 완료 기준

1. 독립 router bus·실제 교차 route·fanout·implicit port에서 세 소비자의 분류를 대조한다.
2. mute/gain0·sidechain-only·lane 소유 미연결 대상의 포함/제외를 각각 확인한다.
3. 실제 현재 트랙 단축키의0/1/multi·혼합 대상과 후보 선택 뒤 트랙 추론이 일치한다.
4. 탐색 전후 음악·선택·camera의 의도한 범위를 확인하고 저장/재열기·기존 편집 접근을 보존한다.
5. 최종 대상 테스트·Release·native·QA 근거 확보 후 검증한 범위만 완료로 기록한다.

## 최종 후보 관측

- Swift7개 class36개 테스트 실패0 (`.build/port-navigation-tests.log`), Release73.47초. UUID `02B23788-DB57-3B8F-890E-4FC7A283B28C`.
- 실제 독립 bus에서 track2 effect0개·track1 effect2개를 확인했다. track2 선택 후 MCP로 effect에 focus하고 ⌘1을 사용하면 track1 source3개로 정확하게 추론했다.
- 실제 GUI router cross 변경 후 track2 effect2개·track1 effect0개로 바뀌고 Undo를 완료했다. QA checker10개 native 상태·AX7개·자산2개 보존·physical0을 확인했다. 저장/재열기 manifest는 예외 없이 전체 동일하다. Undo 음악은 musicRevision/hierarchyView 제외·circleColors 정규화 후 정상 복원됐다.

## 출력 조사 경계

[장치·클라이언트 관측](../qa/output-device-review.md)은 별도 읽기 전용 조사로 완료했다. 이 탐색 수정으로 HAL 지연이 해결되거나 정상 장치 출력이 확보됐다고 판단하지 않는다. 기존 mixerAcquisition/HAL 대기 원인은 미해결이며 사용자 앱·장치 설정·출고 조건을 유지한다.
