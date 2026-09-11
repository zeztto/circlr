# 신호 출력 레벨의 dB 표시

상태: build91 최종 final-scroll 후보의 관련17개 테스트·Release20.04초·아래 native 검증 확인. QA 최종 대조 통과. [QA](../qa/signal-level-review.md).

## 표시 계약

effect·mix·router의 출력 볼륨에서 단위 없는 gain1 표시를 기존 `.gainDecibels` 표현의0.00dB로 통일한다. gain1은0dB, gain0은−∞dB로 표시한다. 기존 편집 행을 사용하며 추가 패널이나 새 데이터 모델을 만들지 않는다.

저장·MCP·renderer·automation 값은 기존 선형 gain을 유지한다. 표시 단위 변경이 프로젝트 데이터·렌더 결과·자동화 값의 변환이나 migration을 일으키지 않는다. 기존 dB 입력·확정·취소·Undo 동작을 따른다.

## 작은 창의 router 접근

baseline1020×768에서 콘솔을 열면 router 하단 경로 버튼·음소거·출력 볼륨이 잘려 보이지 않는 것을 실제 화면에서 확인했다 (`baseline/router.png`). `InlineCircleEditor`의 `.router`를 기존 `rememberEditorScroll` 기반 `ScrollView`·`VStack`으로 감싸 하단 컨트롤로 이동할 수 있게 한다. 기존 스크롤 복원 방식을 사용하며 하단 접근과 dB 입력을 최종 후보에서 함께 검증한다.

## 검증 기준

1. effect·mix·router의 gain1과 gain0을 실제 UI에서0.00dB/−∞dB로 확인한다.
2. dB 입력의 선형 값 반영, 취소·Undo와 저장/재열기를 확인한다.
3. 단위 변경만으로 음악·MCP·automation의 선형 값이 바뀌지 않는지 대조한다.
4.1020×768·콘솔 열림에서 router 하단 경로·음소거·출력 볼륨으로 스크롤해 접근하고 기존 스크롤 복원과 편집 동선을 확인한다.

## 앞선 후보와 발견 이력

- Swift8개 (`.build/signal-level-tests.log`), 앞선 Release38.99초 (`.build/signal-level-release-final.log`), UUID `15CEA7CC-4CF4-3A69-BA1F-48069D8EC81C`.
- effect/mix/router 각각−6dB 선형 gain 변경·Undo 확인. effect 대표 경로에서−∞ 무음·0dB 원래 값·no-op·20dB 거절·Esc를 확인했고 오래된−9dB 초안의 router 전환 보호도 확인했다. 관측 revision18→26.
- 1020×768 콘솔 열림에서 router 하단 scrollbar1 접근·실제 입력·Undo와 저장/재열기 확인. saved/reopened 전체 manifest는 strict 동일하다. 왕복/재열기 AX의 scrollbar는0이므로 스크롤 위치 보존은 검증 완료로 계산하지 않는다.
- 앞선 후보19개 상태·AX16개는 광범위 dB 편집과 복원 누락 발견 이력이다. physical 출력0회·사용자 앱 유지.

 이 최소 UI 개선을 사용자 앱 교체나 물리 오디오 문제 해결로 계산하지 않는다. 기존 사용자 앱을 보존하며 physical 오디오 출고 조건은 미완료로 유지한다.

## 최종 스크롤 복원 후보

`EditorViewportState.restored`의 scroll whitelist에 router가 없어 왕복 위치가0으로 돌아가는 원인을 수정했다. 최종 관련17개 테스트와 Release20.04초를 통과했다. UUID는 `05742A9A-97FE-31C5-B729-A1109FE9A083`이다.

최종7개 snapshot·AX4개, revision26→28을 확인했다. router 하단 scrollbar1이 mix 왕복·gain 변경/Undo·저장 재열기 뒤 모두1을 유지한다. 재열기 화면에서1020×768의 하단 가시성을 확인했고 saved/reopened 전체 manifest는 strict 동일하다. 앞선 후보의 하단 접근 성공과 위치0 회귀를 이 최종 결과와 구분한다.

사용자 앱을 유지했고 physical 출력0회다. QA checker의 앞선19개 snapshot/AX16개·최종7개 snapshot/AX4개 대조를 통과했고 routerScroll{x:0,y:169} 보존을 확인했다. 종료 점검에서 기존 사용자 PID86114만 남았으며 검증 앱·빌드·worker는 모두 종료됐다.
