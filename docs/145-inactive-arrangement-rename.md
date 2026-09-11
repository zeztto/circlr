# 적용하지 않은 편곡안의 이름 변경

상태: build125 baseline 결함을 재현한 뒤 build126 소스·최종 Release와 아래 native 이름 편집을 검증했다. 저장/재열기·독립7개 snapshot 감사·production 서명/UUID도 통과했다. 전체 편곡 왕복·편집 위치 기억은 별도 후속 범위다.

## 문제와 완료 방향

현재 적용 편곡이 A일 때 목록의 B를 강조한 뒤 ⇧⌘N을 누르면 A의 이름 입력이 열렸다. B를 정리하려면 먼저 편곡을 적용해야 하므로 현재 음악 작업을 불필요하게 전환하게 된다. `qa/generated/arrangement-naming/baseline-wrong-target`의 JPEG/AX가 실제 관측 근거다. fixture 프로젝트76594812…·musicRevision40, 현재 A95B906…·강조 B94300CA6…를 사용했다.

이름 변경은 강조한 B를 대상으로 하고 현재 적용 A·캔버스·musicRevision을 유지해야 한다. 목록의 강조와 실제 편곡 적용을 구분하며 Return의 편곡 적용 동작을 이름 편집으로 바꾸지 않는다.

## 구현 계약

[ArrangementInputCoordinator](../Sources/CirclrApp/ArrangementInputCoordinator.swift)는 ⇧⌘N과 버튼에 같은 active sourceID를 사용한다. 이름 변경 모드는 해당 choice의 sourceID·sourceTitle을 보관하고 AX label도 실제 이름 변경 대상을 명시한다. 편곡 적용 상태와 달라도 현재 유효한 후보이면 이름 변경할 수 있다.

[ArrangementPickerView](../Sources/CirclrApp/ArrangementPickerView.swift)는 요청 identity와 최신 composition catalog에 실제 source가 있는지 확인한다. 이름 변경은 기존 musical:false mutation을 유지하고 편곡 적용·음악 revision을 바꾸지 않는다. 이름 변경 후 목록을 새로 만들 때 source를 다시 강조하여 B에서 작업을 이어간다. 버튼·도움말·키보드 안내를 강조 대상 기준으로 맞춘다.

선택 강조 유지 보완도 적용했다. 오래된 request·빈 이름·취소·외부 변경 등은 기존 검증 경계와 함께 확인하며 source guard의 존재를 모든 native 경쟁 조건 통과로 세지 않는다.

## 최종 검증 조건

- A가 적용된 상태에서 B 강조→⇧⌘N 후 B의 이름과 명확한 대상 표시가 나타나는지 실제 화면/AX로 확인한다.
- B 이름 적용 후 B만 변경되고 A 적용·캔버스·musicRevision이 유지되는지 저장 상태로 대조한다. 변경 후에도 B 강조가 유지되어 추가 정리를 이어갈 수 있어야 한다.
- 취소·유효하지 않은 이름의 거절, Undo와 정확한 저장/재열기를 확인한다. 수행하지 않은 IME·stale 직접 주입은 별도로 남긴다.
- Release·바이너리 식별·서명과 native 화면·데이터 감사는 각각 기록한다. 현재 실행 중인 빌드의 성공을 미리 선언하지 않는다.
- noIO QA 범위에서 검증한다. A 유지란 적용된 재생 편곡 선택의 보존이며 실제 소리를 재생해 확인했다는 의미가 아니다.

## 현재 검증 결과

최종 Release는42.19초에 성공했고 UUID는 `B21296C8-736F-3BA7-B73A-00CCD9A2360E`다. `.build/build126-release.log`의 첫 빌드는 빌드 중 소스 보완으로 실패했다. 성공 근거는 `.build/build126-final-release.log`이며 실패 후보와 구분한다.

native에서 B 강조 후 ⇧⌘N의 정확한 B 대상, 빈 이름 거절, 마우스로 B 재이름 변경, 완료 뒤 B 강조 유지, Escape 후 A의 원래 출력/오토메이션 화면 보존을 확인했다. 한글 typeText 요청이 실제로 B와 공백으로 축소돼 첫 이름은 B로 적용됐다. 실제 IME와 도구 중 원인은 확정하지 않았으며 한글 입력 통과를 주장하지 않는다. 이후 ASCII `B - Short Intro`로 정확히 변경했다.

두 이름 변경 동안 musicRevision40을 유지했다. Undo1회는41에서 B, Undo2회는42에서 원래 이름, Redo2회는44에서 `B - Short Intro`로 복귀했다. revision44 재열기의 실제 JPEG/AX에서 적용 A와 B의 `B - Short Intro` 이름을 확인했다. 독립7개 snapshot 감사는 saved=reopened=disk의revision44 정확한 일치, active A·선택/view·음악 내용 보존, 자산4개 SHA·noIO를 확인해 PASS했다. production strict 서명과 위 UUID도 통과했다.

 [현행 개발 계획](138-current-development-plan.md)의 편곡 대안 왕복·작업 위치 기억과 전체 제작 흐름을 이어가며, 이름 변경 하나로 편곡 편집 전체를 완료 처리하지 않는다.

다음에는 한국어 입력 축소가 도구 전달과 앱 입력 중 어느 경계에서 발생하는지 분리 진단하고, 편곡 전환별 이전 작업 위치 복귀를 이어서 검증한다. 전체 제작 목표는 계속 남아 있다.
