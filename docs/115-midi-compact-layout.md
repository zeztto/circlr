# 작은 MIDI 편집기의 배치와 도구 접근

상태: build100 최종2 Release41.85초·아래 native 확인. 저장 재열기 checker 대조도 통과했으며 신규 Core 동작은 없다.

## 기준 재현과 배치 계약

build99 실제 baseline에서 radius326·body591.4 조건의 inspector 시작/세기와 노트 이동이 잘리는 것을 확인했다. 기존 최소 폭700에 대응해 compact 폭574(160+210+180+24)를 사용하며 전환 threshold는700이다. 편집기 진입 threshold는 바꾸지 않는다.

inspector 폭210·개별 field 폭97과 label wrap을 적용한다. toolbar는 두 그룹을 가용 폭에 따라 한 줄/두 줄로 배치하되 view identity를 유지한다. 배치 전환이 입력 초안·선택·포커스를 새로 만들거나 지우지 않아야 한다.

첫 빌드는 `Layout`이 `CirclrCore.Layout`과 모호해 실패했다. `SwiftUI.Layout`을 명시해 수정했고 이후 중간 후보를 거쳐 최종2 빌드를 확인했다. 최초 실패와 후속 성공 근거를 구분한다.

## 검증 조건

1. 기준 compact geometry에서 inspector 시작/세기·노트 이동과 주요 도구가 보이고 접근 가능하다.
2. 한 줄/두 줄 toolbar 전환의 view identity와 입력 draft·선택을 보존한다.
3. geometry와 viewport state를 확인하고 편집기 진입 조건이 바뀌지 않았는지 대조한다.
4. 실제 노트·step·tail 조작과 필요한 Undo·저장/재열기를 확인하며 UI 확인을 신규 Core 테스트로 합산하지 않는다.
5. 최종 Release·native·QA의 실제 근거가 확보된 범위만 완료로 기록한다.

기존 header 끝 아이콘 잘림은 별도 잔여 범위다. 이번 compact 배치가 해당 문제까지 해결했다고 기록하지 않는다. 사용자 앱·물리 출력 출고 조건을 유지한다.

## 후보별 근거와 최종 범위

중간 Release41.96초 후보는 Orbit body591.4의 초안1. 확대/축소 유지·길이0.5→1/Undo·invalid999 Tab 차단/Esc·3노트 이동/Undo·page5–8 줌을 확인했다. 그러나 step header intrinsic 폭 때문에 inspector 오른쪽이 잘리는 것을 발견해 완료 처리하지 않고 Grid/StepEditor를 추가 수정했다.

최종2 Release41.85초, UUID `DA62630D-4EA0-3F48-9471-122345AAF4B7`에서 다음을 확인했다.

- step compact4개 필드와1/16 수평 page, 검색66·줌 왕복 보존.
- 3노트+1 pitch revision35·Undo36의 정확한 복원.
- Orbit 다중 길이 초안1.의 줌 왕복 보존·Esc 후0, inspector 하단 ScrollDown의 퀀타이즈 등 접근.
- revision36 저장 뒤 completed open job 확인. checker가 saved/reopened/disk strict 일치·완료 job·UUID 일치를 확인했다. physical0·자산2개 유지.

긴 셋잇단 메뉴 선택의 적용을 확인하지 못했다. `triplet-compact` 증거도1/16이므로 셋잇단 성공으로 계산하지 않는다. header 일부 잘림도 남아 있다. 이번 compact 동선 검증을 전체 MIDI·DAW 완료로 확대하지 않는다.

최종2에서 tail 새 조작·긴 셋잇단 적용·128페이지 native는 검증하지 않았다. 검증 앱 종료 뒤 기존 사용자 앱 PID86114만 실행 중임을 확인했다.

최종 checker는 baseline2+first9+final7의18개 snapshot·AX3+2의5개·자산2개·physical0 대조를 통과했다.
