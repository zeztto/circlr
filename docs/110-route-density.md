# 현재 대상의 중복 탐색 버튼 정리

상태: build95 parse·Release40.30초 및 아래 native 탐색 검증 확인. QA 최종 대조 통과. [QA](../qa/route-density-review.md). 기준 build94 commit은 `f65141f`다.

## 표시 계약

현재 서클이 해당 역할의 유일한 target이면 기존 inline route bar에서 같은 대상으로 이동하는 중복 버튼을 생략한다. 작은 창의 가로 공간을 확보하되 탐색 기능 전체를 숨기지 않는다.

여러 대상이 있는 역할은 기존 검색·선택을 유지한다. 다중 오디오·이펙트와 현재 대상이 아닌 유일한 후보는 계속 접근할 수 있어야 한다. header의 모드 복귀와 ⌘1/⌘3 접근도 유지한다.

이 변경은 표시 밀도 조절이며 현재 선택·편집 대상·음악·revision을 바꾸지 않는다. 개수가 같아도 역할과 정확한 target이 다른 경우 중복으로 처리하지 않는다.

## 검증 완료 기준

1. 현재 역할의 유일한 동일 target 버튼만 생략하고 다른 역할/다른 target의 접근을 유지한다.
2. 다중 오디오·이펙트의 검색과 선택, header 모드 복귀·⌘1/⌘3을 실제 UI에서 확인한다.
3. 작은 창에서 확보한 가로 공간과 남은 조작의 가시성을 확인한다.
4. 탐색 전후 음악·revision 보존과 필요한 선택/복귀 동작, 저장·재열기를 확인한다.
5. 최종 근거가 확보된 범위만 완료로 기록한다. 사용자 앱·물리 출력 조건은 기존대로 유지한다.

## 최종 후보 관측

Release40.30초 (`.build/route-density-release.log`), UUID `59D93FC8-5A1C-3898-9FB3-42B37997255F`.

baseline94에 있던 중복 router 버튼이 후보95에서 사라지고 header는 유지됐다. settings/connection에서 header 한 번으로 본문 복귀, audio2 검색 선택 뒤 다중 검색 유지, ⌘3의 effect2 검색·↓/Return 선택을 확인했다. ⌘1의 source3(audio2/MIDI1)에서↓2/Return으로 MIDI를 선택하면 현재 단일 MIDI 버튼을 생략했다. 다른 router 버튼으로 복귀하면 MIDI 버튼이 다시 나타났다.

모든 관측의 음악 revision62와 saved/reopened 전체 manifest strict 동일을 확인했다. MIDI/effect는 원본 범위의 use-only 안내 상태에서 탐색만 검사했으며 실제 편집 검증으로 계산하지 않는다. QA10개 native snapshot·AX12개(기준1+후보11)·자산2개·physical0 대조를 통과했다.

다음 offline AU effect worker는 별도 미구현 계획이다. 이번 탐색 변경을 plugin 격리나 물리 출력 안정성 확보로 확대하지 않는다.
