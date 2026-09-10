# 편곡 복제 후 정확한 편집 대상 유지

상태: build112 Release·Core13개·native checker24개 snapshot·source/시각7장 검토 완료.

## 동작 계약

현재 편곡을 복제한 뒤 정확한 audio 클립·MIDI 서클/노트 대상과 오토메이션 point를 복제본에서 계속 편집한다. ⇧⌘E continuation은 workspaceOriginal=false로 이번 사용을 연다. rhythm 대상은 제외하며 다른 candidate에는 이 continuation을 노출하지 않는다.

원본 graph가 nil이면 이를 원본에 그대로 보존한다. 유효하지 않은 색상 주소 역시 원본 데이터는 보존하고 clone에는 복사하지 않는다. 복제·rename·Undo와 원본 scope 전환 후에는 기존 continuation 요청의 유효성을 다시 판단한다.

## 확인된 증거

- `.build/build112-release.log`: Release83.26초·exit0. UUID `9FEBF1B5-482D-321E-807A-6D0AD5C45744`.
- `.build/build112-arrangement-selection-tests.log`: Core13개, 0 failures. 최종 source review blocker0, 시각7장 검토 통과.
- `qa/generated/arrangement-continuation/final`: native 주 시나리오 및 추가 원본 scope·rename·Undo 이후 stale UI disabled 실행 완료. 마지막 final-reopened revision27까지 포함한24개 snapshot의 최종 checker가 통과했다. sharedOriginalModeForcedOff·exactCloneMusic·audio/automation 복귀·sourcePreserved·Undo/reopen·noIO를 확인했다. stale는 UI가 disabled되어 no-op인 경우를 검증했으며 handler를 강제로 호출하지 않았다.

original-before에는 editor가 없고 continued에서 같은 asset의 기존 cached viewport가 구체화되는 차이는 소스 근거를 대조해 한정 허용했다. 임의 viewport 변경이나 음악 차이를 허용한 것은 아니다.

## 제한과 후속 과제

빠른 복제 직후 rename 또는 다음 clone 단축키가 기존 picker 검색 입력으로 전달되거나 clipboard timeout이 발생했다. 해당 폼을 확인한 뒤 실행한 경우 성공했다. 기존 picker의 빠른 연속 단축키·focus 전환은 후속 과제이며 전체 키보드 조작이 완전하다고 주장하지 않는다.

MIDI continuation UI는 native에서 검증하지 않았다. Core 테스트는 주소 mapping을 확인하며 App의 MIDI 복귀 동작을 직접 검증하지 않는다. nonempty 그룹/색상 조합의 native 검증도 수행하지 않았다. 물리 출력은 명시적 QA stub으로 차단했다. QA 앱은 ⌘Q로 종료했고 이후 프로세스 검사에서 사용자 앱 PID86114만 관측했다. 다른 기능의 과거 검증 수치를 이번 후보에 합산하지 않는다.
