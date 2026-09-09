# 섹션 연결 메뉴의 재생 경로 표시

상태: build98 Core6개 실패0·0.004초·Release39.03초·아래 native 확인. 체크 glyph 시각 검증은 미완료다.

## 표시 계약

실제 도달 가능한 `AlbumCanvas` 우클릭 메뉴의 체크 판정을 `SectionFlowSelection.isSelected`로 통일한다. isEnd 상태에서는 ‘끝 해제 후 재생할 연결’ 안내로 저장된 다음 연결과 현재 재생 경로를 구분한다. 기존 연결 선택 동작은 바꾸지 않는다.

앞선 `UnifiedSectionView`는 rg 참조 검색에서 생성 참조를 찾지 못했다. 이번 수정과 검증 대상은 실제 `AlbumCanvas` 메뉴다. 이 검색 결과를 실제 UI 결함 재현으로 계산하지 않는다.

## 검증 기준

1. 일반 경로·선택 분기·isEnd 상태의 체크 표시가 `SectionFlowSelection.isSelected`와 일치한다.
2. isEnd에서 다음 연결을 현재 재생 경로처럼 표시하지 않고 끝 해제 후 의미를 안내한다.
3. 실제 메뉴 열기·기존 선택 동작·Undo·저장/재열기를 확인하며 표시 변경만으로 음악을 바꾸지 않는다.
4. 최종 Release·native·QA 근거를 확보한 범위만 완료로 기록한다.

다른 편곡 candidate의 직접 복제는 별도 미구현 과제로 유지한다. 사용자 앱·물리 출력 문제와 이번 메뉴 표시 개선은 별개다.

## 최종 후보의 근거와 한계

Release39.03초 (`.build/section-flow-menu-release.log`), UUID `91A49FCF-A28B-3FE3-BA91-1DE4964793B4`, QA 패키지 strict 서명 검사를 통과했다. 실제 증거는 `qa/generated/section-flow-menu`에 보존했다.

단일 메뉴 선택은 revision14·전체 manifest strict 불변이었다. end fixture의 isEnd=true+chosen edge에서 ‘끝 해제 후 재생할 연결’ AX 안내를 확인했다. 실제 항목 선택은 isEnd=false와 revision15만 변경했고 ⌘Z로 끝 상태를 복원한 revision16은 revision을 제외한 전체 manifest가 strict 동일했다. output/audition0회다.

AX의 selected는 highlight이므로 체크 증거가 아니다. native popup screenshot을 확보하지 못해 체크 glyph의 시각 확인은 미검증이다. 체크 판정은 Core6개 테스트와 source 확인 범위로 기록하며 native 선택 동작 검증과 구분한다.

총4개 snapshot의 revision은14/14/15/16이다. 검증 앱을 종료한 뒤 실행 중 circlr는 기존 사용자 PID86114만 남아 있음을 확인했다.

각 단계 MCP save는 수행했으나 이번 재열기 검증은 실행하지 않았다. 위 검증 기준의 저장/재열기 전체를 완료로 계산하지 않는다.
